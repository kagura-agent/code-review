# Review: kagura-agent/cove PR #348

## Summary
This PR implements `global_name` across the main authenticated user, message author, mention, OAuth, and settings flows, and the schema migrations/build mostly look clean. The route-level validation for the new string field is present and bounded, and the live message-author path correctly stopped hardcoding `global_name: null`. However, one important server path still drops `global_name` for guild members, which means two advertised client surfaces (MemberList and MentionAutocomplete) will not actually receive/search/display custom display names from the REST member list. I would fix that propagation gap before merge.

## Critical Issues
- **Guild member API still hardcodes `global_name: null`, breaking MemberList and MentionAutocomplete display/search.** In `packages/server/src/repos/members.ts:23-32`, `toUser()` always returns `global_name: null` even though `MembersRepo.list()` selects `u.*` at `packages/server/src/repos/members.ts:47-54` and `CoveAgent` now supports `global_name`. The client changes in `packages/client/src/components/MemberList.tsx` and `packages/client/src/components/MentionAutocomplete.tsx:59-64,130` depend on `member.user.global_name`, so fetched members will continue to show/search `username` only. This directly contradicts the PR summary for MemberList and MentionAutocomplete. Please add `global_name: string | null` to `UserRow`, return `row.global_name ?? null` in `toUser()`, and add/adjust an API test for `GET /api/v10/guilds/:guildId/members` proving `user.global_name` is populated.

## Product Impact
- UserBar/settings and new message author snapshots should reflect `global_name`, but the member roster and mention autocomplete will not until the member repo issue above is fixed.
- Existing open clients do not appear to receive a user/profile update event after saving a display name, so other clients may not see a rename until they refetch members, receive new messages, or reconnect. That may be acceptable for this PR, but it is a visible consistency limitation.
- The plugin now sends `global_name || username` as the sender name (`packages/plugin/src/dispatch.ts:69`), which is a deliberate behavior change for downstream OpenClaw channel payloads/logs. That aligns with the feature, but consumers expecting stable Google `username` labels may notice renamed senders.

## Suggestions
- Normalize `global_name` on the server, not only in the settings UI. `packages/server/src/routes/agents.ts:87-90` validates type/max length, but `repos.users.update()` at `packages/server/src/repos/users.ts:67-70` persists the raw API value. A direct API client can store leading/trailing whitespace or a whitespace-only truthy string, causing blank-looking display names because the UI uses `global_name || username`. Consider trimming server-side and converting trimmed empty strings to `null`.
- Add focused tests for the new user-input path: `PATCH /users/@me` accepts a valid display name, rejects non-string and >80 chars, clears with `null`, and returns the updated `global_name`. Current migration tests pass, but they do not cover the user-facing update behavior.
- Consider a test for mention resolution with a user whose `global_name` is set, since `packages/server/src/repos/messages.ts:320-334` now includes it and the client mention chip displays `u.global_name || u.username`.
- The migration test name at `packages/server/src/__tests__/migration.test.ts:13` still says `fresh DB gets user_version = 10` while the expected version is now 13; renaming it would avoid confusion.

## Positive Notes
- `PATCH /users/@me` includes route-level string validation with a max length for the new field (`packages/server/src/routes/agents.ts:76-88`), satisfying the new input-validation requirement.
- The migrations are small and idempotent (`packages/server/src/db/migrations/v12-global-name.ts`, `v13-pending-global-name.ts`) and the fresh schema was updated consistently.
- The auth and WebSocket paths now correctly pass through stored `global_name` instead of hardcoding `null` (`packages/server/src/auth.ts:82`, `packages/server/src/ws/index.ts:42-45,96-99`).
- Verification: `pnpm -F @cove/server test` passed (13 files, 237 tests), and `pnpm -r build` passed; the client build only emitted the existing large-chunk warning.

**Rate: ⚠️ Needs Changes**
