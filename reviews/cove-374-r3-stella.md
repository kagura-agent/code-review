# 🌟 Stella — Round 3 Re-review of PR #374

**PR:** kagura-agent/cove#374 — feat: image attachments — Discord-style upload, storage, and display (#114)  
**Round 3 verdict:** ⚠️ Needs Changes

## Summary

I re-reviewed the Round 3 diff against the Round 2 findings and did a fresh pass over the upload, serving, and client paths. This revision fixes several concrete client and routing issues: attachment serving is now authenticated and guild-membership checked, the filesystem containment check no longer uses a plain `startsWith`, image/non-image `Content-Disposition` behavior was added, preview object URLs are revoked, and multipart send now throws on non-2xx responses.

However, multiple carry-over issues remain in the server upload/serve path. The remaining items are mostly abuse/security-hardening around user-controlled files. For a small-team project I would not block on UI duplication or perfect CDN semantics, but I would still require the server to stop trusting client-declared MIME types and to avoid writing files before request validation/DB success.

Build check: `pnpm -r build` passes. `pnpm -r test` could not be used as a PR signal in my temp clone because the offline install skipped native build scripts and `better-sqlite3` bindings were missing; this appears environmental, not a TypeScript failure.

## Round 2 Issues — Verification

### 1. Attachment route authorization — **mostly fixed, one permission gap remains**

The route is now registered with `authMw`, loads the channel, and verifies `repos.members.get(channel.guild_id, user.id)`. This addresses the major privacy issue from Round 2: a random unauthenticated user, or an authenticated non-member, should not be able to fetch leaked attachment URLs.

One gap remains: normal channel message reads also call `requireBotChannelPermission(...)`, but the attachment route does not. In the current helper this matters for bot users: a bot guild member without `VIEW_CHANNEL` can be denied `GET /channels/:id/messages` but still fetch `/attachments/...` for that channel if it has the URL. Please apply the same visibility check as the message route, or explicitly document that attachment URLs are guild-member-wide.

Also worth tightening: the route should verify `safeGuildId === channel.guild_id`. Today membership is checked against the channel's real guild, while the disk path is built from the URL guild id.

### 2. Path traversal edge cases — **fixed enough for this storage layout**

Round 3 replaced the plain prefix check with a `path.relative()`-style containment check:

- `ATTACHMENT_ROOT = resolve(process.cwd(), 'data', 'attachments')`
- `resolvedPath = resolve(filePath)`
- reject when `rel.startsWith('..')` or `resolve(ATTACHMENT_ROOT, rel) !== resolvedPath`

Combined with route-param sanitization that strips `/` and other unsafe characters, this closes the specific Round 2 boundary-check concern. I would still prefer strict validation (`/^\d+$/` for ids, explicit filename regex) over silently transforming path params, but I do not consider traversal itself a blocker in R3.

### 3. Content-Disposition — **partially fixed**

The route now serves recognized image suffixes inline and non-images as attachments, which is the intended behavior.

Two caveats remain:

- `Content-Type` / inline decision is still based on the URL filename suffix, not stored validated metadata.
- The route treats `.svg` as `image/svg+xml` and inline, even though upload currently rejects SVG via `ALLOWED_IMAGE_TYPES`. That is not exploitable through the normal upload path today, but it is a risky default for same-origin file serving and should be removed unless SVG is sanitized/isolated.

### 4. Client preview object URL leak — **fixed**

`MessageInput` now derives preview URLs with `useMemo` and revokes them in an effect cleanup when `pendingFiles` changes/unmounts. That addresses the practical leak called out in R2. The implementation is acceptable for this PR.

### 5. Client error handling — **fixed**

`sendMessageWithAttachments` now checks `res.ok`, parses error JSON defensively, and throws on upload failure. This fixes the R2 optimistic-reconciliation bug where an error payload could be treated as a successful `Message`.

## Remaining / Escalated Issues from R1/R2

### 1. Server still trusts `file.type`; no magic-byte validation — **blocking**

The upload route allowlists `file.type` against jpeg/png/gif/webp, but `file.type` is client-controlled multipart metadata. A direct API client can upload arbitrary bytes while declaring `Content-Type: image/png`; the server will write the bytes, store `content_type: 'image/png'`, and the client will render it as an image attachment.

Please sniff the uploaded bytes before storage and derive the canonical MIME type from signatures, at least for:

- JPEG: `FF D8 FF`
- PNG: `89 50 4E 47 0D 0A 1A 0A`
- GIF: `GIF87a` / `GIF89a`
- WebP: `RIFF....WEBP`

Reject mismatches and store the sniffed MIME type, not the multipart header. SVG should stay rejected unless served from an isolated origin or sanitized.

### 2. Validation still happens after file writes — **blocking, escalated**

In the multipart branch, files are written before these validations run:

- final content presence/type/length validation,
- nonce type/length validation,
- some payload shape checks such as non-string `message_reference.message_id` are incomplete.

Example: a request can include valid-looking image files plus an invalid `nonce`; the server writes all attachments, then returns a validation error. This is exactly the R2 orphan-file scenario.

Move all payload validation above `file.arrayBuffer()` / `storeAttachment()`. Treat `payload.content` as untrusted type data, validate `nonce`, validate `message_reference.message_id` is a string, and reject empty `content + no files` before any disk I/O.

### 3. Orphan file risk remains — **blocking, escalated**

The route still writes every file to disk before `repos.messages.create(...)`. If the DB insert throws, or if a later synchronous update in the message creation flow fails, the files remain under `data/attachments/...` with no message row referencing them.

A small-team-friendly fix would be:

1. validate everything first,
2. write files to a temp/staging location,
3. create the message row in a DB transaction,
4. move staged files into the final attachment location,
5. cleanup staged/final files in `catch` when later steps fail.

Alternatively, create the DB row first with attachment metadata and delete/rollback it if file writes fail. The important part is that failed requests should not leave permanent unreferenced blobs.

### 4. Upload limits still happen after multipart parsing — **needs changes**

Per-file (`8MB`) and count (`10`) checks exist, which is a real improvement. But they are still applied after `await c.req.parseBody({ all: true })`, so oversized bodies can be buffered by the multipart parser before the app sees `file.size`.

For this project, I would not demand a full streaming upload implementation before v1, but please add a pre-parse body/request limit where the Hono/node stack supports it, or at minimum reject large `Content-Length` before `parseBody()`. A total attachment payload cap would also make the effective limit clear.

### 5. Response `Content-Type` is still URL-suffix-based — **needs changes**

The static route still decides response MIME from `safeFilename.endsWith(...)`, while upload metadata stores `content_type` separately. This causes both security and correctness drift:

- a file named `photo.JPG` can pass upload as `image/jpeg` but be served as `application/octet-stream` because suffix matching is lowercase-only;
- the response type can disagree with the DB metadata;
- the route has no DB binding to prove `attachmentId + filename + content_type` belong together.

Serve based on stored, validated attachment metadata. If lookup-by-attachment is not available yet, store enough metadata to find the owning message/channel and canonical filename, then use that record to choose `Content-Type` and authorization.

### 6. Duplicate image rendering in `MessageItem` — **not addressed, non-blocking**

The image rendering block is still duplicated in both grouped and non-grouped message branches. This is maintainability noise, not a merge blocker by itself. Extracting a small `AttachmentImages` component would make future fixes safer.

## Fresh Round 3 Notes

- Attachment route auth should match message visibility exactly. Right now it checks guild membership but not `requireBotChannelPermission` and not URL guild/channel consistency.
- `window.open(att.url, '_blank')` should use `noopener,noreferrer` or an anchor with `rel="noopener noreferrer"`. Since URLs are same-origin generated attachment URLs, this is low severity.
- There are still no attachment-specific tests in the diff. Given this is a file upload + private file serving surface, add tests for auth/permission, path traversal attempts, MIME mismatch, oversized/count rejection, invalid nonce cleanup, and a happy-path multipart round trip.
- The send button still appears muted for image-only messages because its color depends only on `content.trim()`. The click works, so this is just UX polish.

## Positive Notes

- The main R2 client correctness issues are fixed: object URLs are revoked and non-2xx upload responses now throw.
- The attachment route is no longer public and the path boundary check is materially better.
- The product behavior remains good: paste/drop, image-only sends, previews, removal, inline lazy display, and click-to-open are all present.
- The migration remains additive/idempotent and the repo build is green.

## Recommendation

Do not merge yet, but this no longer looks like a “major issues” round. The remaining blockers are focused and fixable:

1. validate/sniff image bytes and store the canonical MIME type;
2. move all payload validation before disk writes;
3. add cleanup/transactional handling so failed DB/message creation does not orphan files;
4. add a pre-parse body limit or `Content-Length` guard;
5. serve attachments using stored metadata and match the message route’s visibility checks.

**Final rating:** ⚠️ Needs Changes
