# Review of PR #374: feat: image attachments

## Summary
This PR successfully implements Discord-style image attachments, providing a solid user experience with drag-and-drop, clipboard pasting, inline thumbnails, and backend storage for attachment metadata. The client seamlessly mimics familiar platform behaviors while keeping mobile responsiveness intact.

## Critical Issues (Blocking)
- **Upload Limits & Memory Exhaustion (DOS)**: In `routes/messages.ts`, calling `await file.arrayBuffer()` buffers the entire file into memory before saving. Because there is no maximum file size limit enforced, an attacker can upload massive files and cause the server to crash via Out-Of-Memory (OOM) errors. You must enforce a file size limit (e.g., 8MB) and consider streaming the file directly to disk.
- **Server-Side File Type Validation**: The client restricts uploads to `image/*`, but the server's `multipart/form-data` parser accepts any file type. A malicious user could bypass the client and upload arbitrary files (e.g., executables). The server must explicitly validate file signatures/MIME types.
- **Authentication on File Access**: The `GET /attachments/...` route is registered before auth middleware and does not check if the requester has permission to view the channel. This makes all uploaded files public to anyone who can guess or obtain the URL. If this is intended (similar to Discord's public CDNs), it should be explicitly acknowledged; otherwise, auth validation is required.

## Product Impact
Users gain a significantly richer communication tool. By supporting inline displays, pending previews, and drag/drop functionality, the messaging experience becomes much closer to established modern chat apps.

## Suggestions
- **`window.open` Security**: The `onClick={() => window.open(att.url, '_blank')}` handler in `MessageItem.tsx` should preferably be an `<a>` tag with `target="_blank" rel="noopener noreferrer"`, or explicitly pass `'noopener,noreferrer'` to `window.open` to prevent tab-nabbing.
- **Path Traversal Hardening**: While `safeFilename` strips out slashes during upload, the static file serving in `app.ts` accepts `guildId`, `channelId`, and `attachmentId` directly from route params. Validating that these parameters are valid Snowflakes (e.g., `/^\d+$/`) will guarantee no `..` traversal attacks can occur on read.

## Rating
⚠️ Needs Changes
