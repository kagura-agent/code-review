# Review: PR #374 — feat: image attachments — Discord-style upload, storage, and display (#114)

## Summary

This PR is a substantial, well-scoped rework of image attachment support across server, client, and plugin layers. The normalized `attachments` table, Discord-style multipart API, preview/lightbox UI, and OpenClaw `MediaUrls` forwarding are all moving in the right direction, and the rewritten version is much cleaner than a JSON-column-only approach. I do think it still needs changes before merge because the new public file surface and upload path have a couple of security/data-lifecycle gaps that are easy to miss but important for a feature that makes files publicly retrievable.

## Critical Issues

1. **Deleted attachments remain publicly accessible on disk.**
   The DB rows cascade via `attachments.message_id -> messages(id)`, but the actual files under `data/attachments/{guild}/{channel}/{id}/{file}` are never removed on single-message delete, bulk delete, channel clear, or channel/message cascade. Because `/api/v10/attachments/...` is intentionally public and cached as immutable, deleting a message only removes metadata; anyone with the old URL can still fetch the image. That is both a privacy/product expectation issue and a storage leak. Please add storage cleanup for message delete/bulk delete/clear paths, or make the serving route verify an attachment row still exists before reading from disk. Ideally do both: DB-backed existence check for access correctness plus best-effort unlink/rmdir cleanup.

2. **Upload limits are enforced only after the multipart body has already been parsed into memory.**
   `await c.req.parseBody({ all: true })` happens before file count/type/size validation, so an oversized multipart request can consume memory before the 8MB/file and 10-file checks run. For a public-ish message upload endpoint, this should be bounded at the request/body parser layer or streaming layer. Please add an aggregate request-size guard and/or a multipart parser with early rejection; the intended logical limit appears to be at most 80MB total payload plus JSON overhead.

3. **MIME validation trusts client-supplied `File.type` only.**
   The whitelist checks `file.type`, which is just the multipart part content type supplied by the client. An attacker can upload arbitrary bytes labeled `image/png`/`image/jpeg`, and the static route later serves based on filename extension rather than verified content. At minimum, validate image magic bytes for jpeg/png/gif/webp before writing, and add `X-Content-Type-Options: nosniff` to attachment responses. If malformed images are allowed intentionally, serve them as attachment instead of inline.

## Product Impact

Users will get the intended Discord-like workflow: paste/drop images, see preview cards, send image-only messages, view inline thumbnails, and open a lightbox. The biggest user-facing risk is deletion semantics: a user can delete a message and reasonably believe the image is gone, while the public URL continues to work. There is also a deployment caveat: attachment URLs are returned as relative `/api/v10/...` paths, so clients configured with a separate `VITE_COVE_API_URL` may fetch messages from the API origin but render images against the web-app origin unless the client normalizes attachment URLs with `API_BASE`.

## Suggestions

- Add focused API tests for multipart upload success, image-only message creation, too many files, oversized file rejection, unsupported MIME rejection, malformed `payload_json`, and attachment retrieval headers.
- Consider storing and serving the DB `content_type` instead of inferring from extension at read time, after validating/sniffing it on upload.
- Wrap message creation + attachment row insertion in a DB transaction, and decide how to clean up already-written files if DB insertion fails.
- Add a small repository method to fetch attachment disk paths by message IDs; it will make delete/bulk-delete cleanup and DB-backed static access checks much easier.
- Include `width`/`height` population later if Discord compatibility or layout stability matters.
- Remove the duplicate `isImage = true;` in the `.webp` branch.

## Positive Notes

- The normalized `attachments` table with `message_id` index and FK cascade is the right long-term model.
- The multipart API shape (`payload_json` + `files[N]`) matches Discord expectations and keeps JSON clients working.
- Client-side `URL.createObjectURL` cleanup is present, which avoids the common preview memory leak.
- The plugin integration is thoughtful: appending image URL context and passing `MediaUrls` should make image messages usable by OpenClaw agents.
- `pnpm -r build` passes, and the server test suite passed locally (`306` server tests).

## Rating

⚠️ Needs Changes
