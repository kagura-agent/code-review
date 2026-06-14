# Review: kagura-agent/cove PR #352

## Summary
This PR adds a coherent channel file-space feature end-to-end (migration/repo/API/client/plugin context injection), and the core CRUD path is straightforward and covered by a broad server test suite. I ran `pnpm -F @cove/server test -- channel-files.test.ts` (Vitest ran all server tests: 15 files / 269 tests passed) and `pnpm -F @cove/client build` (passed, with the existing large-chunk warning). The main blocker is an authorization gap: the new channel-files routes enforce guild membership but do not enforce channel visibility for bot users, unlike existing channel/message/webhook routes, which can expose or let bots modify `cove.md` in channels they should not be able to access.

## Critical Issues
1. **Bot channel-permission bypass on all file routes** — `packages/server/src/routes/channel-files.ts:14-20`, `25-35`, `39-63`, `67-77`  
   The new routes call `requireGuildMember(...)` but never call `requireBotChannelPermission(...)`. Existing routes such as `packages/server/src/routes/channels.ts:29-39` and `packages/server/src/routes/webhooks.ts:16-24` explicitly deny bot users without `VIEW_CHANNEL`. As written, any bot that is merely a guild member can list, read, create/update, and delete files for any channel in that guild, including `cove.md`. This is especially sensitive because `cove.md` is automatically injected into agent context in `packages/plugin/src/dispatch.ts:266-299`, so a bot without channel access could read or tamper with private channel instructions/context. Please add the same permission check used by the other channel-scoped routes and add tests for denied bot GET/list/PUT/DELETE file access.

## Product Impact
- The files UI introduces a new per-channel workflow and the `cove.md` convention is useful, but authorization must match the rest of Cove before release; otherwise private channel context can leak or be influenced by bots outside the intended channel scope.
- Save/create failures are currently silent in the sidebar (`packages/client/src/components/FilesSidebar.tsx:197-229` catches and relies on console logging from the store), so users who hit an invalid filename or the 100KB limit will see no actionable error. This is frustrating but not a merge blocker if server behavior is fixed.
- `cove.md` injection currently skips files by JavaScript character count (`packages/plugin/src/dispatch.ts:270`), not UTF-8 byte size, so non-ASCII content can exceed the advertised ≤8KB budget in actual prompt bytes.

## Suggestions
1. **Validate filename consistently on GET and DELETE** — `packages/server/src/routes/channel-files.ts:31-35`, `73-75`  
   PUT validates `filename`, but GET and DELETE accept any route parameter. Because `filename` is user input on every route, apply the same `FILENAME_RE` validation to reads/deletes too. This also gives clients a predictable 400 for malformed names instead of ambiguous 404s.

2. **Add a max length for `content_type`** — `packages/server/src/routes/channel-files.ts:56-60`  
   The route checks that `content_type` is a string but does not cap its length. Per the API validation standard, new string fields should have a max length at route level. A modest limit such as 128 or 255 characters would prevent unbounded metadata storage.

3. **Measure `cove.md` plugin context by bytes, not characters** — `packages/plugin/src/dispatch.ts:270`  
   Replace `coveMd.content.length <= 8000` with `Buffer.byteLength(coveMd.content, "utf8") <= 8 * 1024` (or update the documented limit if the intended unit is characters).

4. **Surface sidebar API errors to users** — `packages/client/src/components/FilesSidebar.tsx:197-229`, `packages/client/src/stores/useChannelFilesStore.ts:56-68`  
   Consider `message.error(...)`/`notification.error(...)` for failed create/save/delete, especially invalid filename and size-limit cases. Console-only errors make the feature feel broken.

5. **Consider channel-file rate-limit bucket coverage** — `packages/server/src/middleware/rate-limit.ts:23-27`, `116-127`  
   The channel write bucket only matches `/channels/:id/messages`, so file PUT/DELETE operations fall through to the global bucket. If file writes should have the same anti-spam posture as channel message writes, extend the route matcher or add a files-specific write bucket.

## Positive Notes
- The migration and schema are simple and correctly use `(channel_id, filename)` as a composite primary key with cascade delete (`packages/server/src/db/migrations/v14-channel-files.ts:5-14`).
- `ChannelFilesRepo.upsert` preserves `created_at` and updates `updated_at`, and it duplicates the 100KB guard defensively (`packages/server/src/repos/channel-files.ts:41-76`).
- List responses exclude file content and pin `cove.md` first with deterministic sorting (`packages/server/src/repos/channel-files.ts:20-31`).
- The server test suite covers CRUD, non-member access, filename validation, size limits, 404s, and content type basics (`packages/server/src/__tests__/channel-files.test.ts`).
- Client build and server tests both pass locally.

**Rate: ⚠️ Needs Changes**
