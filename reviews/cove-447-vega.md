# PR #447 Review — feat: redesign FRE — auto-guild, invite-agent endpoint, Settings > Bots integration

**Reviewer:** 💫 Vega  
**Verdict:** ⚠️ Needs Changes  
**PR:** kagura-agent/cove#447 (795+, 60−, 10 files)

---

## Summary

This PR replaces the multi-page First Run Experience with a streamlined flow: auto-create a personal guild on login/register, detect bot-less guilds on the client, and funnel users into a redesigned Settings > Bots tab with a letter-themed invitation UI. The server gets `ensurePersonalGuild` (auth) / `createPersonalGuild` (register) and a new `POST /guilds/:guildId/invite-agent` endpoint. The client drops the full-screen onboarding pages, introduces `useSettingsStore` for cross-component navigation, and adds `InvitationTab` inside `BotManagement`. Overall design is clean and well-structured, but there's one authorization gap that must be fixed before merge.

---

## Critical Issues

### 1. Missing authorization on `invite-agent` endpoint — `guilds.ts`

**File:** `packages/server/src/routes/guilds.ts`, new route at ~line 110

The `POST /guilds/:guildId/invite-agent` endpoint checks guild existence and membership but does **not** verify the user is the guild owner or has `MANAGE_GUILD` permissions. Compare with the existing `PATCH /guilds/:guildId` route which correctly checks:

```
const isOwner = guild.owner_id !== null && guild.owner_id === userId;
if (!isOwner) {
  const roles = repos.roles.listByGuild(guildId);
  const perms = computeBasePermissions(member, guild, roles);
  if ((perms & PermissionBits.MANAGE_GUILD) === 0n) {
    return c.json({ message: "Missing Permissions", code: 50013 }, 403);
  }
}
```

Any guild member—including bots—can currently call this endpoint to create new bot users and receive their auth tokens. This is a privilege escalation: a bot invited to a guild could invite more bots without the owner's consent.

**Fix:** Add the same owner-or-MANAGE_GUILD check from the PATCH route before processing the invite.

### 2. `createPersonalGuild` in `register.ts` is not wrapped in a transaction

**File:** `packages/server/src/routes/register.ts`, lines 13–35

The `createPersonalGuild` function runs 4 independent SQL statements (INSERT guild, INSERT role, INSERT channel, INSERT member) without a transaction. If any intermediate statement fails (e.g., the role INSERT), the database is left in an inconsistent state with a partial guild.

The equivalent function in `auth.ts` (`ensurePersonalGuild`) correctly uses `db.transaction()`. This inconsistency suggests the register.ts version was an oversight.

**Fix:** Wrap the 4 statements in `db.transaction()(() => { ... })`, matching the auth.ts pattern.

---

## Product Impact

1. **FRE only inspects the first guild** (`App.tsx`, ~line 225): `guildIds[0]` means the check only looks at the first guild's members. If a user has multiple guilds and bots exist only in a non-first guild, the FRE will incorrectly fire, sending them to Settings > Bots. In practice this is low-impact since auto-guild means most users will have exactly one guild initially, but worth noting for future multi-guild scenarios.

2. **Clipboard "Copied!" may be false** (`BotManagement.tsx`, `handleCopy`): `navigator.clipboard.writeText` can fail (permissions, insecure context), and the error is swallowed with `.catch(() => {})`. The button text changes to "✅ Copied!" regardless. Users on HTTP or with restricted clipboard permissions see a false confirmation. Consider gating the "Copied!" state on the resolved promise and showing a fallback (e.g., select-all the text for manual copy).

3. **Re-invite regenerates the token silently**: The re-invite flow (same-name bot already in guild) regenerates the bot's auth token without warning the user. If the bot was already connected, this immediately disconnects it. Consider surfacing a confirmation or at least a visual indicator that this is a re-invite that will invalidate the old token.

---

## Suggestions

### 1. DRY: Deduplicate guild creation logic

`ensurePersonalGuild` (auth.ts) and `createPersonalGuild` (register.ts) are near-identical. Extract a shared helper (e.g., in a `lib/guild-setup.ts` or on `GuildsRepo`) that both routes call. This also ensures the transaction fix from Critical #2 applies in one place.

### 2. Bot creation bypasses `UsersRepo.create` — `guilds.ts`

The invite-agent endpoint constructs and runs raw SQL for user creation instead of using `repos.users.create()`. This means:
- ID generation differs (snowflake vs. slug-from-username in the repo)
- Any future business logic added to `UsersRepo.create` won't apply to invite-created bots

Consider extending `UsersRepo.create` with an `id` option (it already accepts one) or extracting bot creation into a dedicated repo method.

### 3. `SectionKey` type is duplicated

`SectionKey` is defined independently in both `useSettingsStore.ts` and `SettingsPanel.tsx`. If sections change, both must be updated manually. Export the type from one location and import it in the other.

### 4. `X-Forwarded-Proto` trust — `guilds.ts`

The `baseUrl` construction reads `X-Forwarded-Proto` from the request header. This is standard behind a reverse proxy, but if the server is ever exposed directly, clients can spoof this header to produce incorrect `baseUrl` values in the invite letter. Low risk (only affects invite letter text, not auth), but consider making this configurable or validating against a trusted proxy list.

### 5. Minor: `inviterName` uses `username` not `global_name` — `guilds.ts`

The invite-agent route sets `inviterName = c.get("botUser").username`, but the client's `InvitationTab` shows `inviterName = globalName || username`. The server letter will always use the raw username (e.g., "john.doe@gmail.com") even if the user has set a display name. Consider using `c.get("botUser").global_name || c.get("botUser").username`.

### 6. CSS uses hardcoded colors — `onboarding.css`

The new `onboarding.css` (310 lines) uses hardcoded hex colors (`#0f1115`, `#e8e8e8`, `#5865f2`, etc.) instead of the project's CSS custom properties (`var(--bg-base)`, `var(--text-normal)`, `var(--accent)`). The ob-letter-paper intentionally uses light colors for the "paper" effect, which is fine. But the login/invite-code pages (`ob-page`, `ob-login-card`) won't respect theme changes. If theming is a goal, consider using CSS variables for the non-letter-paper elements.

---

## Positive Notes

- **Clean state management**: `useSettingsStore` is minimal and well-designed — the `openTo(section)` / `openSettings()` / `close()` API covers all cases without over-engineering.
- **FRE detection is elegant**: Using Zustand's `subscribe` with a `useRef` guard is a good pattern for one-shot side effects triggered by async store population.
- **Invite letter design**: The letter-paper metaphor is charming and gives the FRE personality. The plain-text version for clipboard copy is thoughtfully formatted.
- **Input validation**: The new endpoint properly validates the `name` field using the existing `validateString` helper, consistent with the codebase.
- **Empty code guard**: Adding `if (!code.trim()) return` to the invite code submit handler is a nice defensive addition.
- **Transaction in auth.ts**: `ensurePersonalGuild` correctly wraps multi-statement creation in `db.transaction()`.
