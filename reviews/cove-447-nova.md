# 🌠 Nova — Review of PR #447

**PR:** feat: redesign FRE — auto-guild, invite-agent endpoint, Settings > Bots integration (#444)
**Repo:** kagura-agent/cove
**Stats:** +795 / -60, 10 files
**Reviewed:** 2026-07-02

---

## Summary

This PR replaces the multi-page onboarding wizard with a simpler flow: auto-create a personal guild on registration/login, detect "no bots in guild" as the FRE trigger, and funnel users directly into Settings → Bots → Invitation tab where they can create a bot and get a ready-to-paste invite letter. The server adds `ensurePersonalGuild` (auth.ts), `createPersonalGuild` (register.ts), and a new `POST /guilds/:guildId/invite-agent` endpoint. The client gets a new `useSettingsStore`, a redesigned `BotManagement` with tabs, and a dedicated `onboarding.css`. The approach is clean and product-wise a major UX improvement. However, there are authorization and code duplication issues that should be addressed before merge.

---

## Critical Issues

### 1. `invite-agent` endpoint lacks authorization check — any guild member can create bots

**File:** `packages/server/src/routes/guilds.ts`, new `POST /guilds/:guildId/invite-agent` handler

The endpoint checks that the caller is a guild member (`repos.members.get(guildId, userId)`), but does **not** verify ownership or `MANAGE_GUILD` permission. Compare with `PATCH /guilds/:guildId` (lines ~76-84 of the base file) which explicitly checks `isOwner || MANAGE_GUILD`. This means any member of a guild — including bot accounts — can create new bot users and generate tokens for them.

**Fix:** Add the same owner/permission check used by `PATCH /guilds/:guildId`:
```ts
const isOwner = guild.owner_id !== null && guild.owner_id === userId;
if (!isOwner) {
  const roles = repos.roles.listByGuild(guildId);
  const perms = computeBasePermissions(member, guild, roles);
  if ((perms & PermissionBits.MANAGE_GUILD) === 0n) {
    return c.json({ message: "Missing Permissions", code: 50013 }, 403);
  }
}
```

### 2. `createPersonalGuild` in register.ts runs outside the registration transaction

**File:** `packages/server/src/routes/register.ts`, line after `const result = register();`

`createPersonalGuild(db, userId, pending.username)` is called **after** the `register()` transaction returns. If `createPersonalGuild` fails (e.g., snowflake collision, disk full), the user is created without a guild and gets a broken FRE. Worse, the cookie is already about to be set, so the user is "logged in" but in a bad state.

Additionally, unlike `ensurePersonalGuild` in auth.ts, this function doesn't use a transaction wrapper — each of its 4 INSERT statements runs independently.

**Fix:** Either (a) move the guild-creation SQL into the existing `register` transaction, or (b) wrap `createPersonalGuild` in its own `db.transaction()` and call it before setting the cookie, with error handling if it fails. Option (a) is strongly preferred for atomicity.

---

## Product Impact

### 1. PR description says "Auto-grant VIEW_CHANNEL on #general for invited bots" — not implemented

The PR description lists this as a server-side feature, but the diff contains no `permission_overwrites` or `VIEW_CHANNEL` logic. If the `@everyone` role's `DEFAULT_EVERYONE_PERMISSIONS` already includes `VIEW_CHANNEL`, this may be a non-issue, but it should be verified and the description updated to match reality.

### 2. FRE triggers on first guild only, ignores multi-guild scenarios

**File:** `packages/client/src/App.tsx`, FRE detection useEffect

```ts
const guildId = guildIds[0];
```

The check only inspects the first guild. If a user is in multiple guilds (e.g., the seed guild + their personal guild), the FRE may trigger incorrectly or not at all depending on which guild appears first in the member store. This is fine for the current single-guild-per-user design but worth a comment noting the assumption.

### 3. Token exposed in the invite letter — clipboard copy is the transport

The invite letter (copied to clipboard) contains the raw bot token. This is the intended design for the FRE flow, but the token is visible in plaintext in the UI letter. Users might screenshot or paste it somewhere insecure. This is acceptable for a personal/small-team tool but worth noting as a conscious tradeoff.

---

## Suggestions

### 1. Deduplicate guild-creation logic between `ensurePersonalGuild` (auth.ts) and `createPersonalGuild` (register.ts)

These two functions are nearly identical — same 4 SQL statements, same guild/channel/role/member creation. The only difference is `ensurePersonalGuild` has an existence check and uses `db.transaction()`, while `createPersonalGuild` doesn't.

**Suggest:** Extract a shared helper (e.g., in a `utils/` or `repos/` file) that both call. This also fixes Critical #2 since the shared version would use `db.transaction()`.

### 2. `InvitationTab` uses `Object.values(guilds)[0]` — order not guaranteed

**File:** `packages/client/src/components/BotManagement.tsx`, `InvitationTab`

`Object.values()` on a Zustand store doesn't guarantee ordering. If the user has multiple guilds, they might invite an agent to a random guild. Consider using the active guild from the router context or an explicit guild selector.

### 3. `handleCopy` silently swallows clipboard errors

**File:** `packages/client/src/components/BotManagement.tsx`, line with `navigator.clipboard.writeText(...).catch(() => {})`

If `navigator.clipboard` is unavailable (HTTP without secure context, or user denies permission), the copy silently fails but shows "✅ Copied!" anyway. Consider at minimum logging or showing a fallback "Copy failed" state.

### 4. `inviterName` uses `username` instead of `global_name` on the server side

**File:** `packages/server/src/routes/guilds.ts`

```ts
const inviterName = c.get("botUser").username;
```

The client-side `InvitationTab` correctly prefers `globalName || username`, but the server always uses `username`. If a user has set a display name (`global_name`), the invite letter will use their username instead. Consider using `c.get("botUser").global_name || c.get("botUser").username`.

### 5. `name` input in `InvitationTab` has no max-length enforcement on the client

**File:** `packages/client/src/components/BotManagement.tsx`

The server validates `maxLength: 80`, but the input field has no `maxLength` attribute. Users can type 200 characters and only get an error on submit. Add `maxLength={80}` to the input.

### 6. `initialSection` is not cleared after being consumed

**File:** `packages/client/src/stores/useSettingsStore.ts` + `SettingsPanel.tsx`

When the settings panel opens via `openTo("bots")`, `initialSection` is set to `"bots"`. If the user manually navigates to another section, closes the panel, and reopens it normally (via the gear icon, which calls `openSettings()`), `initialSection` is cleared — good. But if the user closes the panel without navigating away from bots, then opens it via the gear icon, `openSettings()` correctly clears `initialSection` and the section defaults to `"appearance"` via `useState` — this is fine. No issue, just noting the flow is correct.

### 7. Missing `Content-Type: application/json` header in `inviteAgent` API call

**File:** `packages/client/src/lib/api.ts`

The `inviteAgent` function uses `JSON.stringify({ name })` as body but doesn't explicitly set `Content-Type`. Check that the shared `api()` wrapper sets `Content-Type: application/json` by default — if it relies on the caller or `fetch` defaults, this could send the body without the correct content type, causing `parseJsonBody` to fail on the server.

---

## Positive Notes

- **Great product design** — The letter-paper invite metaphor is charming and makes bot onboarding feel personal rather than clinical. The copy-to-clipboard flow is practical and avoids complex OAuth handshakes.
- **Clean store design** — `useSettingsStore` is minimal and well-typed. The `openTo(section)` pattern for cross-component navigation is elegant.
- **Good validation** — Server-side input validation uses the existing `validateString` pattern consistently. The `name` field is properly required and length-checked.
- **Transaction usage** — The `invite-agent` fresh-create path correctly wraps user/member/role creation in a single transaction, which is the right approach.
- **FRE detection** — Using Zustand's `subscribe()` with a ref guard is a clean way to do one-shot detection without re-render storms.
- **Re-invite flow** — Regenerating the token for same-name bots instead of 409'ing is a thoughtful UX choice that handles the "I lost my token" case.

---

## Verdict: ⚠️ Needs Changes

Two critical issues need addressing before merge:
1. **Authorization gap** on `invite-agent` — any guild member can create bots (security)
2. **Guild creation outside transaction** in register.ts — can leave user in broken state (correctness)

Both are straightforward fixes. The rest is solid work.
