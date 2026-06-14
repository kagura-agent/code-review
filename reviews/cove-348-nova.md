# Cove PR #348 Review — `feat: custom display name (global_name) support`

Reviewer: 🌠 Nova
Scope: 21 files, +156/−47

## Summary
A clean, well-scoped feature that aligns Cove's identity model with Discord's `nick > global_name > username` priority. Two SQLite migrations (V12 on `users`, V13 on `pending_registrations`) are correctly idempotent; reads and writes are wired end-to-end through repos, REST, WebSocket gateway, OAuth, and the React client. The most important fix in the PR — restoring `global_name` in `resolveUser`, `findByToken`, the WS path, message author snapshot, and `resolveMentions` — closes a real correctness gap. The feature is shippable, but a few input-validation, accept-spec, and UX consistency issues should be addressed; one of them is a likely user-visible bug.

Rating: ⚠️ Needs Changes (small, mostly tightening — none structural).

## Critical Issues

### C1. PATCH `/users/@me` accepts `global_name=""` and stores empty string (server/client contract drift)
File: `packages/server/src/routes/agents.ts` (PATCH `/users/@me` handler)

The client `SettingsPanel.handleSave` translates `""` to `null` ("empty → clear"), but the server's PATCH path does not. `validateString` allows empty strings unless `required: true`, and the route forwards `body` directly to `repos.users.update` without normalization. Any non-Cove client (or a future bug in the React flow) calling `PATCH /users/@me` with `{ global_name: "" }` will persist `""`. The display chain `nick || global_name || username` then evaluates `""` as falsy, so it happens to render correctly today — but future code paths (`mentionUsers.set(u.id, u.global_name || u.username)`, plugin dispatch, ACP logs) all rely on the same coincidence, and any place that does `global_name != null` instead of truthy checks will break.

Fix: normalize `""`/whitespace-only to `null` server-side before `repos.users.update`, e.g.:
```ts
if (typeof body.global_name === "string" && body.global_name.trim() === "") {
  body.global_name = null;
}
```
Or do this inside `UsersRepo.update`. Document the intent ("empty clears") in a brief comment on the route — it's already the client's contract.

### C2. `validateString` doesn't enforce a sane minimum/charset; abuse vector
File: `packages/server/src/routes/agents.ts`

`global_name` is rendered verbatim across MessageItem, UserBar, MemberList, MentionAutocomplete, and even server logs (`channel.ts:335`). The route validates only `maxLength: 80`. There is no check against:
- control characters / zero-width / RTL override (`U+202E`) — typical impersonation tactics
- newlines (display layout) or `@everyone`-style spoofing in mention pickers
- visually empty strings (whitespace-only)

`validateString` is the project's standard helper; if you don't want to expand its surface, do an inline check here:
```ts
if (typeof body.global_name === "string") {
  if (/[\u0000-\u001F\u007F\u200B-\u200F\u2028-\u202E\u2066-\u2069]/.test(body.global_name))
    return validationError(c, "global_name contains disallowed characters");
}
```
Severity: Critical because (a) the field is shown in mention-autocomplete (where impersonation is highest-impact) and (b) it propagates into log lines that may be ingested elsewhere. Discord enforces similar rules on global_name for this reason.

### C3. `repos.users.update(id, body)` passes the whole request body to the repo
File: `packages/server/src/routes/agents.ts` line ~88: `const updated = repos.users.update(id!, body)!;`

`UsersRepo.update` now whitelists `username|avatar|bio|global_name`, but passing `body` (typed as `Record<string, unknown>` at runtime) is fragile — if anyone adds a new column key to the repo without thinking through the route, it becomes silently mutable from the client. Build the patch object explicitly:
```ts
const updated = repos.users.update(id!, {
  username: body.username, avatar: body.avatar, bio: body.bio, global_name: body.global_name,
})!;
```
This is also the conventional pattern in the rest of this file.

## Product Impact

### P1. Settings hint is misleading for invited (non-OAuth) users
File: `packages/client/src/components/SettingsPanel.tsx`

> "Leave empty to use your Google account name."

For users who registered via invite (which is in fact the only path in `register.ts`), `global_name` is seeded from `given_name`. After they clear it, the chain falls back to `username` (Google `name`, not `given_name`). The hint conflates the two. Also, future SSO providers / non-Google registration would still see this Google-specific text. Suggest: "Leave empty to fall back to your account name."

### P2. Display-name source for OAuth re-link is `given_name`, but new-user flow is identical → no signup choice
The `COALESCE(global_name, ?)` in `auth.ts` is a nice touch — it preserves user-set values across re-login. But for *new* users registering via invite, `global_name = given_name` is silently chosen with no UI. If the user's Google `given_name` is awkward (e.g., legal name vs. preferred name), they only discover this after entering Settings. Consider exposing `global_name` on the registration page (the pending-registration row already carries it). Non-blocking.

### P3. MentionAutocomplete: insertion uses `global_name`, but message rendering relies on a server-side mention list
File: `packages/client/src/components/MentionAutocomplete.tsx` lines 91, 120

`onSelect(member.user.id, member.user.global_name || member.user.username, ...)` inserts the display token into the textarea. When the message is sent and re-rendered, `MessageItem` line 218 uses `mentionUsers.set(u.id, u.global_name || u.username)`. These will agree most of the time, but if a target user changes their `global_name` after the message is composed but before render, the displayed text in the message body and the resolved mention chip may diverge — historically Discord stores the mention text and re-renders by id. Worth filing as a small follow-up. Not blocking.

### P4. `nick` chain on MemberList is correct; on UserBar/MessageItem it's not used
Files: `UserBar.tsx`, `MessageItem.tsx`

Per PR description, the priority is `nick > global_name > username`, but UserBar (always self) and MessageItem (line 277) only fall through `global_name || username`. UserBar can't have a per-guild nick for "self in current guild" today — fine. MessageItem, however, ignores `nick` entirely; if the future `nick` work lands but no one revisits `MessageItem`, message authors will keep displaying global_name even when a server nick is set. Add a `// TODO: nick override when guild_members.nick lands` comment so the chain stays discoverable.

## Suggestions

### S1. Index `users.global_name` for mention autocomplete?
Not now. Autocomplete filters client-side over `members`, and `resolveMentions` queries by id, so no DB-side scan over `global_name`. Skip the index.

### S2. Migration test additions
File: `packages/server/src/__tests__/migration.test.ts`

The test only updates the expected `user_version` from 11 → 13. Add:
- a test that V12 actually adds the `global_name` column to `users` (PRAGMA `table_info`).
- a test that V13 adds the column to `pending_registrations` only when that table exists (the guard `if (tableExists(...))` is currently uncovered).
- an idempotency test: run migrations twice on a fresh DB, expect no error. (V12 already guards via PRAGMA; V13 uses `addColumnIfMissing`. Worth a test.)

### S3. `findByToken` cast is awkward
File: `packages/server/src/repos/users.ts` line ~109

```ts
return { ..., global_name: (row as UserRow).global_name ?? null, ... };
```
You already typed the row with `UserRow & { expires_at: ... }` — the `(row as UserRow)` cast is redundant. Just `row.global_name`.

### S4. Plugin log line leaks display name
File: `packages/plugin/src/channel.ts` line 335

`log?.info?.(\`cove: [${message.channel_id}] ${message.author.global_name || message.author.username}: ${message.content.slice(0, 50)}\`)`

If display names contain control chars (see C2), they'll appear in logs/log shippers. Once C2 is fixed this is moot.

### S5. `setUser` accepts `global_name?: ... | null`, store seeds to `null`
File: `packages/client/src/stores/useUserStore.ts`

Optional `global_name` in the setter parameter is fine, but `fetchMe()`'s response now always returns `global_name` (server `auth.ts` line 110). You can tighten the type to non-optional `global_name: string | null` so `?? null` becomes a real default only on logout, not on shape mismatch.

### S6. Saved feedback duration is hard-coded
File: `SettingsPanel.tsx` `setTimeout(() => setSaved(false), 2000);`

If `handleSave` is called twice before the timer fires, you get a stale "✓ Saved" flash. Clean up the timer in a ref or use `useEffect` cleanup. Minor polish.

### S7. Hint copy: "Leave empty" → "Leave blank" — house style consistency check (only)
Trivial; ignore unless you have a style guide.

### S8. Missing test for the resolveUser bug-fix
The PR body lists "Bug fix: resolveUser was hardcoding global_name to null (broke message author snapshot)". This is the kind of regression that loves to come back. Add a unit test in `auth.test.ts` (or wherever resolveUser is tested) that asserts `result.user.global_name` is round-tripped from the DB.

## Positive Notes

- **Clean migration design**: V12 uses PRAGMA-based idempotency; V13 reuses `addColumnIfMissing` and guards on `tableExists`. Both gracefully handle pre-existing or missing tables. Good.
- **`COALESCE(global_name, ?)` on OAuth re-login** is exactly the right semantic — never clobber a user-customized display name with `given_name`. Subtle, and noteworthy.
- **End-to-end coverage of the read path**: `MessagesRepo.MSG_SELECT` joins `u.global_name`, `resolveMentions` selects it, both WS code paths in `ws/index.ts` fixed, REST `auth.ts /me` returns it, plugin dispatch propagates it. Very few seams left.
- **The hardcoded-`null` audit** (auth.ts, ws/index.ts, MessagesRepo, resolveMentions) is the meaningful bugfix here; it's the kind of thing that *only* gets caught when you wire the feature through end-to-end. Well done.
- **Schema additions are nullable** (`DEFAULT NULL`) — no backfill required, no compatibility break for older clients that don't read `global_name?`.
- **Client prop is `global_name?: string | null`** with `?? null` defaulting — defensive but not paranoid.
- **Filtering in MentionAutocomplete searches both `global_name` and `username`** — matches Discord behavior so users find each other regardless of which name they remember.

## Verdict
⚠️ **Needs Changes** — primarily input-validation hardening (C2), the empty-string→null normalization (C1), and the body-passthrough cleanup (C3). Migration coverage and the missing regression test would round it out. Once C1–C3 are addressed, this is a quick re-review.
