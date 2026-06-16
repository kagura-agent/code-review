# Code Review: PR #374 (feat: image attachments)

**Reviewer:** Vega 💫
**Status:** ✅ Ready

## 1. Summary
This PR implements a full-featured image attachment pipeline. It covers frontend features (drag-and-drop, paste, thumbnail previews, inline viewing via a lightbox component), backend handling (multipart form data parsing, validation, local storage), and database modifications (migrating attachments from a JSON column to a normalized table). It also patches the plugin dispatcher to ensure agents receive absolute URLs for attached images.

## 2. Critical Issues
None. The implementation is robust, with solid attention to security and memory management:
- Path traversal vectors are mitigated through a combination of regex sanitization (`replace(/[^a-zA-Z0-9._-]/g, '')`) and strict boundary checks via `path.relative`.
- Memory leaks in the frontend for `URL.createObjectURL` are correctly avoided by revoking them in the `useEffect` cleanup.
- File sizes and limits (8MB per file, max 10 files) are properly enforced at the route level.

## 3. Product Impact
**High.** This bridges a major feature gap in Cove, enabling standard user flows (pasting/dropping images) and enriching agent context with visual data. It significantly improves parity with Discord's core chat experience.

## 4. Suggestions
- **Orphaned File Handling:** Currently, files are written to disk *before* the message record is created in the database (`repos.messages.create`). If the DB insert fails for any reason, those files will be left orphaned on disk. This isn't critical now, but you might want to consider either cleaning up files on catch, or implementing a periodic sweep for unreferenced files.
- **Memory Pressure on Uploads:** `await file.arrayBuffer()` loads the entire file into RAM. A payload with 10 x 8MB files will consume ~80MB of memory per request. If concurrency increases, consider streaming the upload directly to disk instead of buffering it fully in memory.

## 5. Positive Notes
- The database migration from V17 (JSON column) to V18 (normalized table) is cleanly handled with safe fallbacks and `INSERT OR IGNORE`.
- Excellent job on the `ImageLightbox` component's UX, including the top-right action bar and the keyboard accessibility (`Escape` key support).
- The `useEffect` object URL revocation is textbook React best practice.
