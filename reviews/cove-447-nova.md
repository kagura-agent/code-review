# PR #447 — Round 2 Review (Nova)

**Verdict: ✅ Ready (with follow-ups)** — all R1 Critical issues resolved with test coverage; remaining items are minor polish or acknowledged trade-offs.

## Summary

Commit 3 ("fix: address code review — auth, sanitization, tests, FRE") systematically closes every R1 Critical finding from all three reviewers:

- Authorization gate on `invite-agent` (owner OR `MANAGE_GUILD`, with explicit bot-principal rejection).
- Re-invite defaults to `409 Conflict` with an opt-in `{ rotate: true }` escape hatch.
- Bot role label matches its actual permission surface ("Member" instead of "Server Admin").
- Agent name is validated against `/^[a-zA-Z0-9_-]{2,80}$/` before being embedded in shell commands.
- Six new tests in `guilds.test.ts` cover auth (403), non-owner rejection, 409-on-duplicate, `rotate: true` token rotation, invalid-name (400), and bot-principal rejection.
- Guild-creation logic deduplicated into `packages/server/src/helpers/guild.ts` with `createPersonalGuild` (transaction-participant) and `ensurePersonalGuild` (idempotent, transaction-owning) — used by both `register.ts` (inside its own tx) and `auth.ts` Google callback.
- FRE detector now runs an immediate `checkFRE(useMemberStore.getState())` in addition to subscribing.
- `initialSection` is cleared after consumption in `SettingsPanel`.
- Bot list is always visible above the tabs in `BotManagement`, so re-invite / rotation flow is discoverable.

The diff is well-structured, the transaction boundaries are correct, and the test suite meaningfully exercises the security surface.

## Previous Issues Status

| R1 Item | Severity | Status | Evidence |
|---|---|---|---|
| C1. No authorization on invite-agent | Critical | ✅ Fixed | `guilds.ts:117-136` — bot-user 403 first, then `owner || MANAGE_GUILD` check via `computeBasePermissions`. Tests: `non-owner without MANAGE_GUILD gets 403`, `bot user cannot invite agents (403)`. |
| C2. Re-invite silently rotates tokens | Critical | ✅ Fixed | `guilds.ts:163-172` — returns `409` + code `40009` by default; only rotates when `body.rotate === true`. Tests: `re-invite same-name bot returns 409 by default`, `re-invite with { rotate: true } succeeds and returns new token`. |
| C3. "Server Admin" label vs perms mismatch | Critical | ✅ Fixed | Client `BotManagement.tsx:106` and server letter both display "Role: Member". Managed role is created with `DEFAULT_EVERYONE_PERMISSIONS`, consistent with the label. |
| C4. Agent name shell injection | Critical | ✅ Fixed | `guilds.ts:146-148` — strict regex `/^[a-zA-Z0-9_-]{2,80}$/`. Since the name is the only user-controlled value inside the single-quoted `'"..."'` wrappers in the shell commands, and the allowed alphabet contains none of `'`, `$`, `\`, `` ` ``, `;`, `|`, `&`, the wrappers cannot be broken. Test: `invalid agent name (special chars) gets 400`. |
| C5. No tests for security-sensitive endpoint | Critical | ✅ Fixed | 6 targeted tests added covering all C1–C4 branches plus happy path. |
| Product: FRE may never fire (subscribe-only) | Product | ✅ Fixed | `App.tsx:224-232` — calls `checkFRE(useMemberStore.getState())` synchronously, then also subscribes. `freCheckedRef` prevents double-fire. |
| Product: Multi-guild FRE targets wrong guild | Product | ⚠️ Partial | `InvitationTab` now correctly reads `getActiveIdsFromRouter()` and falls back to first guild (`BotManagement.tsx:15-19`) — so the *action* target is right. However, the FRE *detection* still uses `guildIds[0]` (`App.tsx:216`), so on a multi-guild account whose first guild happens to have no bots, FRE will misfire even if guild 2 has one. Low practical impact (FRE typically fires at first-run when there's only one guild) but not fully closed. |
| Product: Ghost guilds on login for existing users | Product | ✅ Adequately handled | `ensurePersonalGuild` is idempotent — checks `WHERE user_id = ? AND guild_id IN (SELECT id FROM guilds WHERE owner_id = ?)` before creating. Existing users get exactly one personal guild on next login, and never more. Behavior is a defensible migration policy. |
| Product: No rate limit / bot cap per guild | Product | ❌ Not addressed | Any owner can invite unlimited bots. Since only owner/MANAGE_GUILD can invite, it's self-DoS rather than external abuse — call it Suggestion severity going forward. |
| Sugg: Dedup guild creation into helper | Suggestion | ✅ Fixed | `packages/server/src/helpers/guild.ts` — nice separation of `createPersonalGuild` (tx-participant) vs `ensurePersonalGuild` (tx-owner). |
| Sugg: register.ts not in transaction | Suggestion | ✅ Fixed | `register.ts:68` — `createPersonalGuild(db, userId, pending.username)` is now called inside the existing `db.transaction(() => { ... })`. |
| Sugg: Don't trust X-Forwarded-Proto blindly | Suggestion | ❌ Not addressed | `guilds.ts:151` still reads the header unconditionally. Impact is limited — the value is only interpolated into the plaintext invite letter's `baseUrl` for the human to copy, and shell-quoting protects against injection — but a direct attacker connecting to the origin could still produce a letter with a spoofed scheme. |
| Sugg: Clear initialSection after consuming | Suggestion | ✅ Fixed | `SettingsPanel.tsx:227-232` — `useSettingsStore.setState({ initialSection: undefined })` after apply. |
| Sugg: Bot role position grows unbounded | Suggestion | ❌ Not addressed | `guilds.ts:191-193` still does `UPDATE roles SET position = position + 1 WHERE guild_id = ? AND position > 0` on every fresh invite. Positions grow linearly with the number of bots ever invited. Cosmetic since all bot roles carry `DEFAULT_EVERYONE_PERMISSIONS`, but the newer-bots-outrank-older-bots ordering is arbitrary. |
| Sugg: Surface server error messages in client | Suggestion | ⚠️ Partial | `InviteCodePage` (`App.tsx:71-74`) reads `err.data?.message` — good. `InvitationTab.handleInvite` (`BotManagement.tsx:36-38`) still uses a generic `catch { setError("Failed to create invite. Please try again.") }` — so `409`, `403`, `400` all collapse to the same string. Users hitting the new 409 flow won't understand what's wrong. |

## Critical Issues

None. All R1 Criticals are closed and covered by tests. No new Critical-severity issues discovered in the fresh code.

## Product Impact (remaining)

### PI-1. FRE detection uses first guild, not active guild
- File: `packages/client/src/App.tsx:214-218`
- Symptom: On a multi-guild account, FRE opens Settings if `guildIds[0]` has no bots, regardless of which guild is active or whether other guilds are already bot-enabled.
- Fix: Mirror the pattern in `InvitationTab` — read `getActiveIdsFromRouter().guildId` (with fallback to `guildIds[0]`) and check that guild's members. Same three lines.

### PI-2. No bot cap per guild
- File: `packages/server/src/routes/guilds.ts` `invite-agent` handler
- Symptom: A single owner can create arbitrarily many bot users/roles/members.
- Fix: Add a per-guild bot count check (e.g. `MAX_BOTS_PER_GUILD = 20`) before the fresh-invite branch. Matches the spirit of the existing `MAX_GUILDS_PER_USER = 10`.

## Suggestions

### S1. Show real server error text in `InvitationTab`
```ts
} catch (e: unknown) {
  const err = e as { data?: { message?: string } };
  setError(err.data?.message ?? "Failed to create invite. Please try again.");
}
```
Without this, users hitting `409 "Agent with this name already exists"` cannot discover the `{ rotate: true }` remedy. Small change, big UX improvement now that 409 is a first-class outcome.

### S2. Small race window on re-invite
Between `members.list(guildId).find(...)` (line 157) and the fresh-invite transaction, two concurrent same-name invites can both take the "fresh" branch (no unique constraint on `users.username`) and end up with two bot users of the same name in the same guild. Options: (a) `UNIQUE(guild_id, username) WHERE bot = 1` partial index, or (b) move the existence check *inside* the transaction and re-check on conflict. Low probability but worth noting.

### S3. `MAX_GUILDS_PER_USER = 10` not enforced by helpers
`createPersonalGuild` is called by both `register.ts` and (via `ensurePersonalGuild`) `auth.ts` without consulting the `MAX_GUILDS_PER_USER` cap that `POST /guilds` respects. Practically fine — auto-create only fires for users owning 0 guilds — but if the cap gains meaning later (e.g. across-org quotas), the helper is the wrong entry point to skip it silently.

### S4. Position management for managed roles
The `position + 1` shift means newer bots always sit above older bots. If ordering matters later (hoist, mention prefix), consider inserting at `MAX(position)+1` per bot instead. No action needed now, but note for the next role/hoist feature.

### S5. `x-forwarded-proto` trust
If Cove is meant to run behind a specific trusted proxy, gate the header on an env-configured `TRUST_PROXY=1` flag (or a `TRUSTED_PROXY_IPS` allowlist). For same-origin dev the fallback (`url.protocol.replace(":", "")`) is fine; the header override only matters behind an actual proxy.

### S6. `openTo("bots")` type coverage
`useSettingsStore` defines `SectionKey = "appearance" | "profile" | "bots"`. `SettingsPanel`'s local `SectionKey` should be imported from the store (or the store's type should be exported and re-used) to prevent them drifting apart on future section additions.

## Positive Notes

1. **Excellent test discipline** — 6 tests, one per critical branch, including the subtle "owner-but-a-bot" path that's easy to miss.
2. **Clean helper extraction** — the tx-participant vs tx-owner split in `helpers/guild.ts` is exactly the right shape; comments explicitly document the contract.
3. **Sanitization + shell-quoting layered defense** — regex restricts the alphabet *and* the shell commands use single-quoted-then-double-quoted wrappers, so even a regex bypass wouldn't yield injection.
4. **409 semantics done right** — includes a Discord-style numeric error code (`40009`) alongside the human message, matching the codebase's conventions.
5. **Bot list moved above tabs** — makes rotation/delete discoverable, closing the invisible-side-effect loop that R1 flagged.
6. **Auto-VIEW_CHANNEL on #general** — nice touch; the bot can actually do something the moment it connects, matching the letter's promise ("Say hello in #general").
7. **Transaction correctness in `register.ts`** — moving `createPersonalGuild` inside the existing `db.transaction` (rather than starting a nested one) is the right call and avoids SQLite's nested-tx pitfalls.
8. **Test file also cleans up** — `api.test.ts:1100` narrows the `guild_members` assertion to `defaultGuildId`, so the auto-personal-guild for other users won't cross-contaminate that assertion. Small but shows awareness.

## Recommendation

**Merge**, with two follow-up issues filed:

1. FRE detection should use active guild (matches `InvitationTab` behavior). *[Product]*
2. Enforce a per-guild bot cap and surface server errors in `InvitationTab`. *[Product + UX]*

The X-Forwarded-Proto, role-position, and race-window items are worth a tracking issue but shouldn't block this PR.
