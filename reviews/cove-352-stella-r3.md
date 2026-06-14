# PR #352 Round 3 Re-Review — Stella

## R2 Issue Status

### ✅ Fixed — `handleDelete` missing try/catch + `message.error`
Verified in `packages/client/src/components/FilesSidebar.tsx:213-220`.

`handleDelete` now wraps `deleteFile(channelId, selectedFile)` in `try/catch` and displays `message.error("Failed to delete file")` on failure.

### ✅ Fixed — plugin `getChannelFile` swallows all errors
Verified in `packages/plugin/src/rest-client.ts:175-184`.

`CoveRestClient.getChannelFile()` now returns `null` only for errors whose message contains `404` or `403`, and rethrows all other errors. This means the API client itself now distinguishes “no file / no permission” from server/network failures.

Note: `dispatch.ts:268-273` still catches and ignores rethrown errors while loading optional `cove.md`. That preserves the intended graceful fallback behavior, but it also means server failures are not surfaced/logged at the dispatch call site. I am not treating this as the original R2 issue remaining, because the method under review no longer swallows all errors.

### ⚠️ Partially Fixed — store state leaks across channels
Verified in `packages/client/src/components/FilesSidebar.tsx:177-182` and `packages/client/src/stores/useChannelFilesStore.ts:34-42`.

R3 does clear `selectedFile`, `fileContent`, and local `editing` state when `channelId` changes, so the most visible stale editor/detail leak is fixed.

However, the global store’s `files` array is still not scoped to the current channel and is not cleared or guarded when fetching a new channel:

- `fetchFiles(channelId)` sets only `{ loading: true }`, leaving the previous channel’s `files` in state.
- On fetch failure, it sets only `{ loading: false }`, so the previous channel’s file list remains available/displayed.
- There is no request/channel guard, so a slower request for channel A can complete after switching to channel B and overwrite the store with channel A’s file list.

This keeps the cross-channel file-list leak class partially open. The fix should either clear `files` on channel change/fetch start and on failure, or track `currentChannelId` / request token in the store and ignore stale responses.

Because this is an unaddressed previous-round issue, it should not be downgraded.

## New Issues

No separate new blocking issues found in the R3 changes beyond the partially-fixed store leak above.

Minor observation: the dispatch caller silently ignores server/network errors from optional `cove.md` loading. That may be acceptable product behavior, but a debug-level log would make backend failures easier to diagnose without breaking dispatch.

## Summary + Verdict

⚠️ **Needs Changes**

Two claimed R3 fixes are verified: delete failure handling is now user-visible, and the plugin REST client no longer collapses all `getChannelFile` failures into `null`.

The channel-switch state fix is incomplete: selected file/content/editing are cleared, but the file list itself can still leak across channels on failed or out-of-order fetches. Please scope or clear `files` when `channelId` changes and guard async fetch results against stale channel responses.

Tests were not run locally; this review is based on PR diff/source inspection.