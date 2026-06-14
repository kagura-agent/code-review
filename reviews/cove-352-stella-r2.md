# PR #352 Round 2 Re-Review — Stella

Repo: `kagura-agent/cove`  
PR: #352 — feat: channel file space with cove.md convention

## 1. R1 Issue Status

### Critical R1 Issues

#### ✅ Fixed — Bot permission bypass on file routes

Verified in `packages/server/src/routes/channel-files.ts`:

- `GET /channels/:channelId/files` checks `requireBotChannelPermission(...)` at lines 19-21.
- `GET /channels/:channelId/files/:filename` checks it at lines 33-35.
- `PUT /channels/:channelId/files/:filename` checks it at lines 53-55.
- `DELETE /channels/:channelId/files/:filename` checks it at lines 85-87.

This addresses the R1 critical bypass: a bot denied `VIEW_CHANNEL` now receives `403 Missing Permissions` before file metadata/content/write/delete access.

#### ⚠️ Partially Fixed — Missing bot permission tests

Verified in `packages/server/src/__tests__/channel-files.test.ts`:

- Denied bot tests cover all four file routes:
  - list → 403
  - get → 403
  - create → 403
  - delete → 403
- Granted bot tests cover:
  - list → 200
  - create + read → 200/content verified

So the important denied-permission regression coverage exists. However the claimed “granted bot can CRUD” is not fully covered: there is no granted-bot update test and no granted-bot delete test. Existing admin CRUD tests cover functionality generally, but not bot permission allow-path coverage for the full CRUD surface.

Recommendation: add granted-bot update and delete tests, or adjust the claim. This is not a blocker for the critical bypass because the denied-path security coverage is now present.

### R1 Suggestions / Claimed Fixes

#### ✅ Fixed — `content_type` max length

Verified in `packages/server/src/routes/channel-files.ts` lines 68-71:

- validates `content_type` is a string when present
- rejects `content_type.length > 255`

One minor gap: there is no explicit test for oversized `content_type`; adding one would strengthen regression coverage.

#### ⚠️ Partially Fixed — Silent UI errors

Verified in `packages/client/src/components/FilesSidebar.tsx`:

- save failure now shows `message.error("Failed to save file")` at lines 197-205.
- create failure now shows `message.error("Failed to create file")` at lines 215-226.

However delete failures are still silent to the user:

```ts
const handleDelete = useCallback(async () => {
  if (!selectedFile) return;
  await deleteFile(channelId, selectedFile);
}, [channelId, selectedFile, deleteFile]);
```

`deleteFile` rethrows after logging to console, but `handleDelete` has no `try/catch` and no `message.error`. If deletion fails, the user still gets no visible feedback.

Recommendation: wrap delete in `try/catch` and show `message.error("Failed to delete file")`.

#### ✅ Fixed — GET/DELETE filename validation

Verified in `packages/server/src/routes/channel-files.ts`:

- GET route validates `filename` with `FILENAME_RE` at lines 37-40.
- DELETE route validates `filename` with `FILENAME_RE` at lines 89-92.

#### ✅ Fixed — `content.length` → `Buffer.byteLength` for cove.md injection limit

Verified in `packages/plugin/src/dispatch.ts` lines 266-272:

```ts
if (coveMd?.content && Buffer.byteLength(coveMd.content, 'utf8') <= 8000) {
  coveMdContent = coveMd.content;
}
```

This correctly enforces the 8KB limit by UTF-8 byte size instead of JS UTF-16 code unit count.

### Other R1 Suggestions Not Claimed Fixed

#### ❌ Not Fixed, escalated to Medium — Rate-limit bucket still does not cover file writes

R1 noted that the channel write bucket did not apply to file writes. This remains true.

In `packages/server/src/middleware/rate-limit.ts`, `CHANNEL_WRITE_RE` is still:

```ts
const CHANNEL_WRITE_RE = /\/channels\/[^/]+\/messages/;
```

So `PUT /channels/:channelId/files/:filename` and `DELETE /channels/:channelId/files/:filename` only consume the global bucket, not the stricter channel-write bucket. This leaves channel file writes less protected than message writes, even though they mutate channel-scoped state and can write up to 100KB per request.

Suggested fix:

```ts
const CHANNEL_WRITE_RE = /\/channels\/[^/]+\/(messages|files)(?:\/|$)/;
```

and add a rate-limit regression test for repeated `PUT /channels/:channelId/files/...`.

#### ❌ Not Fixed — Upsert still has unnecessary SELECT + race window

`ChannelFilesRepo.upsert()` still performs a pre-`SELECT created_at` before `INSERT ... ON CONFLICT`. This remains a small race/readability issue from R1, not newly introduced in R2.

#### ❌ Not Fixed — Client state can still leak across channel switches

`FilesSidebar` fetches files when `channelId` changes, but the global Zustand store still keeps `selectedFile` / `fileContent` until explicitly cleared. If the sidebar remains open during a channel switch, the previous channel’s selected file can remain selected briefly or drive stale UI state until a user backs out/refetches.

#### ❌ Not Fixed — Double-fetch on create

`handleCreateFile()` calls `saveFile()`, which refreshes the file list, then calls `handleFileClick(name)`, which fetches the new file. This remains acceptable but inefficient.

#### ❌ Not Fixed — Oversize check duplicated between route and repo

The 100KB size check still exists both in route validation and in `ChannelFilesRepo.upsert()`. Not harmful, but still duplicated.

## 2. New Issues

### Medium — File writes still bypass the stricter channel-write rate limit

This is both an unaddressed R1 issue and still the main remaining product/security concern. Because file writes are channel-scoped mutations and can store much larger payloads than typical messages, they should be in the stricter channel write bucket, not only the global bucket.

Impact:

- easier channel file churn/spam than message spam
- more DB write pressure, especially with 100KB payloads
- inconsistent API behavior for channel-scoped writes

### Low — Delete UI error handling remains silent

As noted above, save/create now show visible errors, but delete still does not. This is lower severity than the original broad silent-error concern, but still user-visible.

### Low — Granted-bot tests do not actually cover full CRUD

The new denied-bot tests are strong, but the granted bot allow-path only verifies list/create/read. Please add update and delete allow-path tests if the intended guarantee is “granted bot can CRUD.”

## 3. Summary + Verdict

The R2 security fix for the critical bot permission bypass is correctly implemented across all four file routes, and the denied-bot regression tests cover the critical failure mode. The claimed input-validation fixes are also mostly in place, and `Buffer.byteLength` is correctly used for `cove.md` injection size.

Remaining concerns are narrower:

- channel file writes still are not in the stricter channel-write rate-limit bucket
- delete failures still have no visible UI error
- granted-bot tests do not fully cover CRUD despite the fix claim

Build/test verification performed:

- `pnpm -F @cove/server exec vitest run src/__tests__/channel-files.test.ts --reporter=dot` → 29 tests passed
- `pnpm -r build` → passed

Verdict: ⚠️ Needs Changes

I would not block on the original critical permission issue anymore; that is fixed. I would still request changes for the remaining Medium rate-limit gap before merge, or explicitly accept it as a follow-up if the project is comfortable with file writes using only the global bucket.
