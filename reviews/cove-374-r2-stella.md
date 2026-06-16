# 🌟 Stella — Round 2 Re-review of PR #374

**PR:** kagura-agent/cove#374 — feat: image attachments — Discord-style upload, storage, and display (#114)  
**Round 2 verdict:** ❌ Major Issues

## Summary

I re-reviewed the updated diff fresh and checked each Round 1 item. The author addressed some symptoms, but several fixes are incomplete and several Round 1 additional issues remain unchanged. This is still not ready to merge because the attachment fetch path is only authenticated, not authorized; path containment is still fragile; file type validation trusts multipart headers instead of bytes; upload limits happen after multipart parsing has already buffered the request; and invalid multipart metadata can still leave orphan files on disk.

`pnpm -r build` passes, so this is not a compile/build concern. The blocker is security and robustness of the file upload/serving design.

## Round 1 Critical Issues — Verification

### 1. Path traversal — **partially fixed, still not safe enough**

The new attachment route sanitizes params and checks `resolve(filePath).startsWith(ATTACHMENT_DIR)`, which is an improvement over direct `join()`. However:

- The check uses plain string `startsWith()` without requiring a path boundary. A sibling directory such as `data/attachments_evil` still has the string prefix `data/attachments`.
- The sanitizer allows `.` and does not reject `..` components; it transforms invalid input instead of enforcing a strict expected shape.
- IDs should be snowflakes, but the route accepts arbitrary sanitized strings for `guildId`, `channelId`, and `attachmentId`.
- Serving still trusts URL components instead of looking up the attachment metadata from the message/DB and serving the stored canonical path.

This is meaningfully better than Round 1, but I would not call the traversal class closed. Use strict validation (`/^\d+$/` for IDs, a safe filename regex with no `.`/`..` special cases), and compare resolved paths with a real directory-boundary helper such as `path.relative(root, target)` where `!relative.startsWith('..') && !path.isAbsolute(relative)`.

### 2. Unauthenticated attachment serving — **only partially fixed**

The route now has `authMw`, so anonymous users are blocked. But any authenticated Cove user with an attachment URL can fetch the file. The route does not verify:

- the channel exists,
- the URL `guildId` matches the channel’s guild,
- the requesting user is a member of that guild/channel,
- bot channel permissions / `VIEW_CHANNEL` rules.

Attachments should inherit the same visibility model as `GET /channels/:id/messages`. Right now private-channel images become readable by unrelated authenticated users if the URL leaks. This is still a blocking privacy issue, even though the narrower “unauthenticated” issue was addressed.

### 3. No upload size/count limits — **partially fixed, still vulnerable to pre-validation buffering**

The PR now enforces `MAX_FILES = 10` and `MAX_FILE_SIZE = 8MB` by checking `File.size`, which is good. But this happens after `await c.req.parseBody({ all: true })`, so the multipart body has already been parsed/buffered before the size checks run. Large requests can still consume memory before validation rejects them.

There is also no explicit total request/body limit at middleware/runtime level. The accepted maximum is effectively at least 80MB per message plus parser overhead, and malicious oversized requests are only caught after parsing.

This fix is better but incomplete for DoS hardening. Add a request/body limit before multipart parsing, preferably with a 413 response, and consider a total attachment payload cap.

### 4. No server-side MIME validation — **partially fixed, insufficient**

The PR now has an `ALLOWED_IMAGE_TYPES` whitelist for `file.type`, allowing jpeg/png/gif/webp. That is useful, but `file.type` is derived from the multipart part’s declared content type and can be forged by an API client. Arbitrary bytes can still be uploaded while claiming `image/png`.

For a file-serving feature, server-side validation should verify magic bytes/signatures for JPEG, PNG, GIF, and WebP, and then store the validated MIME type. SVG should remain rejected unless separately sanitized and isolated.

### 5. `payload_json` uncaught parse — **fixed**

Malformed `payload_json` is now wrapped in try/catch and returns a validation error. This specific Round 1 issue is addressed.

## Round 1 Additional Issues — Verification

### Content-Type from URL suffix instead of stored metadata — **not addressed**

The static route still decides response `Content-Type` from `safeFilename.endsWith(...)`. It does not consult DB metadata or a validated stored content type. This can also cause correctness bugs: a file uploaded as `image/png` with a `.txt` name is accepted but served as `application/octet-stream`.

### Orphan file risk — **not addressed, escalated**

Files are still written to disk before `repos.messages.create(...)`. If the DB insert or later message-side work fails, attachment bytes remain on disk without a message row referencing them.

Round 1 called this out; it is still present. Use a DB transaction plus temp-file staging/rename, or write after the message record is committed with cleanup on failure.

### Validation after file writes — **not addressed, escalated**

Several validations still happen after file writes in the multipart branch:

- `content` type/length validation,
- `nonce` type/length validation,
- the final “content required if no attachments” check.

For example, a request with valid image files and an invalid nonce can write all files and then return a validation error. Move all payload validation before any `file.arrayBuffer()` / `storeAttachment()` call.

### `URL.createObjectURL` memory leak — **not addressed**

`MessageInput` still calls `URL.createObjectURL(file)` directly during render and never revokes the URLs. Re-rendering the composer repeatedly creates unreclaimed blob URLs. Create preview URLs in state/effect and revoke them on removal, send, channel switch, and unmount.

### `sendMessageWithAttachments` has no `r.ok` check — **not addressed, escalated**

The helper still does:

- direct `fetch`,
- unconditional `.then(r => r.json())`,
- cast to `Promise<Message>`.

A 400/401/413 error JSON can be treated as a successful `Message` by the caller, causing optimistic reconciliation with an error object. This is a real client correctness bug now that the server returns validation errors for uploads. Match the existing `api()` helper behavior: check `r.ok`, handle `204`, and throw on non-2xx.

### Duplicate image rendering block in `MessageItem` — **not addressed**

The image attachment rendering block remains duplicated in both the grouped and non-grouped message branches. Extract a small attachment image component/helper. This is not security-blocking, but it was a Round 1 maintainability issue and remains unchanged.

## Fresh Issues / Regressions Found in Round 2

### Attachment route lacks channel authorization and DB binding

Beyond auth, the route should bind the requested attachment to the message/channel metadata. Currently a URL alone selects a disk path. There is no check that `attachmentId` belongs to `channelId`, that the stored metadata filename matches `safeFilename`, or that the requester can read that channel.

### Sanitization changes user input instead of rejecting it

On read, malicious-looking params are silently transformed by removing characters. That can create surprising aliases. For security-sensitive path parameters, prefer strict validation and reject anything outside the expected grammar.

### Original filename is stored/displayed unsanitized

The URL uses `safeFilename`, but metadata stores `filename: file.name`. React escapes `alt`, so this is not immediate XSS in the current display, but it is still untrusted user input that future UI may render elsewhere. Consider storing both `filename` (display) and `stored_filename` clearly, with display sanitization/length limits.

### No attachment-specific tests

This PR adds a sensitive upload and file-serving surface but no tests for auth, authorization, traversal attempts, MIME rejection, oversize rejection, invalid `payload_json`, invalid nonce cleanup, or round-trip serving. Given the number of security fixes in Round 2, tests should be added before merge.

## Positive Notes

- The build passes: `pnpm -r build` completed successfully.
- The author did add concrete improvements: auth middleware on the attachment route, try/catch for `payload_json`, file count/size constants, and a MIME allowlist.
- The overall API shape remains reasonable and Discord-compatible.
- The migration is additive and idempotent.

## Recommendation

Do not merge yet. The minimum changes I would require before another review:

1. Enforce attachment fetch authorization equivalent to message visibility.
2. Replace path sanitization/string-prefix checks with strict validation plus boundary-safe path containment.
3. Validate image bytes server-side and store/serve the canonical validated content type.
4. Add request/body limits before multipart parsing and keep per-file/count caps.
5. Move all payload validation before file writes and add cleanup/transactional handling for orphan files.
6. Fix `sendMessageWithAttachments` non-2xx handling.
7. Add security tests for the attachment upload and serving paths.

**Final rating:** ❌ Major Issues
