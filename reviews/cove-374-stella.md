# Review: PR #374 — feat: image attachments

## Summary

This PR delivers the full end-to-end attachment path: multipart message creation, local disk persistence, attachment metadata on messages, and client paste/drop previews plus inline rendering. The product shape is solid and close to what users expect, but the server-side upload and serving paths need hardening before merge. Right now the feature trusts multipart clients too much and exposes files through an unauthenticated static route, which creates security and abuse risks for a cross-package attachment system.

## Critical Issues

1. **Blocking: attachment serving is unauthenticated and not authorization-checked.**  
   `GET /attachments/:guildId/:channelId/:attachmentId/:filename` is registered outside the authenticated API routes and does not verify that the requester is logged in or is a member of the guild/channel. Any party with an attachment URL can fetch it. If Cove channels/guilds are private, this leaks private images. At minimum, serve through an authenticated route and verify channel membership/visibility before reading the file, or use signed, expiring URLs if public static serving is intentional.

2. **Blocking: path traversal / filesystem boundary checks are missing.**  
   `getAttachmentPath()` and `storeAttachment()` use `path.join()` with route/form-derived path components and never normalize + verify that the final path remains under the attachment root. The upload path sanitizes the stored filename, but the read path accepts `guildId`, `channelId`, `attachmentId`, and `filename` directly from the URL; encoded slash/dot-dot behavior can vary by router/runtime. Add strict ID validation for path components, sanitize/lookup filenames from DB metadata rather than trusting the URL, and enforce a resolved-path prefix check against the attachment directory before `readFile()`/`writeFile()`.

3. **Blocking: no server-side file type whitelist or content validation.**  
   The client filters pasted/dropped files to `image/*`, but the server accepts any multipart `File`. An API caller can upload arbitrary content and choose misleading names/types. The static route infers response `Content-Type` from extension while stored metadata uses `file.type`, so metadata and served bytes can disagree. The server should enforce an allowlist such as PNG/JPEG/GIF/WebP, validate both MIME type and magic bytes, reject SVG/HTML/scripts unless explicitly supported, and use the validated type consistently in metadata and responses.

4. **Blocking: no upload size, file count, or total payload limits.**  
   `parseBody({ all: true })` plus `file.arrayBuffer()` loads uploads into memory and writes them to disk without any per-file, per-message, or aggregate limits. A malicious or accidental large upload can exhaust memory or storage. Add request/body limits at middleware/runtime level, validate `file.size`, cap number of files, and fail before buffering large content where possible.

5. **Blocking: malformed `payload_json` can produce a 500 instead of validation error.**  
   In the multipart branch, `JSON.parse(payloadRaw)` is not wrapped. Bad multipart input should return a 400 validation response, not an uncaught exception.

## Product Impact

Users will be able to paste or drag images, preview them, remove them before sending, send image-only messages, and view images inline. However, without server validation and access checks, private images may be accessible to anyone with the URL, and oversized or invalid uploads can degrade or take down the service. The client also only shows attachments whose declared `content_type` starts with `image/`, so inconsistent server validation may lead to broken or surprising rendering.

## Suggestions

- Consider storing a canonical sanitized filename in attachment metadata and displaying the original filename separately if needed.
- Make `sendMessageWithAttachments()` follow the existing API helper behavior for non-2xx responses; currently it always calls `r.json()` and casts to `Message`, which can make error payloads look like successful messages.
- Avoid creating preview object URLs directly during render in `MessageInput`; create/revoke them with lifecycle cleanup to prevent memory leaks during repeated previews/removals.
- Add tests for malicious filenames, encoded traversal attempts, oversized uploads, non-image uploads, malformed `payload_json`, image-only messages, and authorized/unauthorized attachment fetches.
- Consider adding `width`/`height` extraction later so clients can reserve layout space and reduce content jumps.

## Positive Notes

- The feature is well-scoped across shared/server/client and follows Discord-compatible multipart conventions, which is a good integration choice.
- The migration is additive and idempotent, with a safe default `attachments TEXT DEFAULT '[]'` for existing rows.
- Message read paths defensively parse attachment JSON and fall back to an empty list on malformed data.
- The client UX covers the important basics: paste, drag/drop, previews, removal, inline display, and click-to-open.

## Rating

❌ Major Issues — the product direction is good, but security and abuse-prevention gaps in upload/serving need to be fixed before merge.
