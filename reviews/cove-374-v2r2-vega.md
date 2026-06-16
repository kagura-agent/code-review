# Code Review: PR #374 (v2 Round 2)
**Reviewer:** 💫 Vega

## Verification of Round 1 Issues

1. **Orphaned files on delete — cleanup added:** Fixed. ✅
   The server now properly retrieves associated attachments before message deletion (single, bulk, and full channel delete) and asynchronously unlinks the files using `cleanupAttachmentFiles`. 

2. **Deleted attachments still accessible — DB check before serving:** Fixed. ✅
   The attachment GET route now explicitly checks `repos.attachments.exists(safeAttachmentId)` and returns a 404 before reading the file, ensuring deleted file references are inaccessible.

## Fresh Review of Cleanup Code

The cleanup logic is solid. It reconstructs the path safely from the stored URL and catches `unlink` errors to prevent interrupting the main deletion transaction. The path traversal protections and MIME type checks also look robust.

**Minor Polish Notes (Non-blocking):**
- In `packages/server/src/app.ts`, the block `if (!repos.attachments.exists(safeAttachmentId))` is duplicated back-to-back.
- In `packages/server/src/app.ts`, inside the `.webp` check, `isImage = true;` is assigned twice.

## Rating
✅ **Ready** - The requested fixes are correctly implemented.
