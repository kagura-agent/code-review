# Code Review: PR #352

**1. Summary**
This PR introduces a channel file space with a special `cove.md` convention. It includes the backend schema migration (V14), CRUD operations for channel files with a 100KB size limit, React client UI for viewing and editing files, and plugin dispatch logic that seamlessly injects `cove.md` into the bot's extra context.

**2. Critical Issues**
* **Input Validation (Violation of Rule 6):** In `packages/server/src/routes/channel-files.ts`, the `content_type` field is validated for type (`typeof body.content_type !== "string"`) but lacks any maximum length validation. This could allow a malicious user to send an unbounded string payload for `content_type`, bypassing the 100KB content limit and bloating the database.

**3. Product Impact**
* Introduces a dedicated "Files" tab alongside the "Members" sidebar.
* Enables users to manage up to 100KB text/markdown files within channels.
* `cove.md` acts as a powerful tool for pinning instructions or channel context directly to the bot, affecting how the bot responds in that channel. The bot limits this injection to ≤8000 characters.

**4. Suggestions**
* **Missing Error Feedback in UI:** In `packages/client/src/components/FilesSidebar.tsx`, the `catch` blocks for `handleSave`, `handleDelete`, and `handleCreateFile` swallow errors (e.g., if a file exceeds 100KB, it just logs to the console). Users won't know why their file failed to save. Consider adding a toast notification or inline error message.
* **Redundant Network Requests:** In `packages/client/src/stores/useChannelFilesStore.ts`, the `saveFile` method ignores the returned file from `api.putChannelFile()`, and immediately calls `fetchFiles()` and `fetchFile()` again. You can optimize this by updating the local Zustand store using the return value from the PUT request instead of re-fetching.
* **Silent Limit on `cove.md`:** If a user makes their `cove.md` longer than 8000 characters, the plugin (`packages/plugin/src/dispatch.ts`) silently ignores it rather than truncating it or warning the user. It might be better to truncate it with a warning suffix so the bot is still somewhat aware.

**5. Positive Notes**
* The file sizing limit implementation efficiently checks `Buffer.byteLength` in both route limits and DB repositories.
* Great test coverage checking all edge cases: CRUD, authentication barriers, non-member access blocks, filename validation, and size limit checking.
* The sidebar component effectively manages mutual exclusivity between members and files, keeping the UI clean.

**Rate:** ⚠️ Needs Changes
