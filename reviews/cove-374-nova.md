# 🌠 Nova — Review of cove#374

**feat: image attachments — Discord-style upload, storage, and display (#114)**
Rating: **⚠️ Needs Changes**

## Summary

This PR ships a complete image-attachment vertical slice across server, shared, and client: a new local file storage helper, a static `/attachments/...` route, a multipart variant of `POST /channels/:id/messages`, an `attachments` JSON column (migration v17), a `Shared.Attachment` type, and a paste/drag-drop upload UI with inline image rendering. The shape is Discord-compatible and the client UX is clean. Functionally the slice looks correct and `pnpm test` is green, but the server-side input handling has several security gaps that must be closed before merge: no upload size limits, no server-side MIME/extension validation, no path-traversal hardening on the static route, and no authorization check on attachment fetches. None of these are subtle — they're standard hardening that file-upload features require.

## Critical Issues (blocking)

1. **No path-traversal protection on `GET /attachments/:guildId/:channelId/:attachmentId/:filename`.**
   `getAttachmentPath` simply `join`s the four URL params with `ATTACHMENT_DIR` and `readFile`s the result. None of the params are validated against snowflake/filename shapes, and there is no `path.resolve(...).startsWith(ATTACHMENT_DIR)` containment check. While Hono's `:param` won't match `/` literally, percent-encoded `/` (`%2F`) is decoded into the param value after route matching in many setups, and `..` segments are accepted as-is. Even if a path-traversal payload typically lands on ENOENT today, the absence of an explicit boundary check is a hard "no" for a file-serving endpoint. Add: validate each id with a `^\d+$` snowflake regex, validate `filename` against `^[a-zA-Z0-9._-]+$`, and after `join`, assert `path.resolve(filePath)` is inside `path.resolve(ATTACHMENT_DIR)` before opening the file.

2. **`/attachments/...` is unauthenticated.**
   The route is registered on `app` directly, before `app.route(API_PREFIX, registerRoutes(db))`, so it bypasses `requireAuth` and the per-guild membership checks. Practically the snowflake IDs in the URL are unguessable, but this is *security by obscurity*: any leaked URL (browser history, log file, screenshot, third-party preview unfurler, link forward) is permanent, public, world-readable, and never expires (`Cache-Control: public, max-age=31536000, immutable`). For a chat product where channels can be private, attachments must inherit the channel's permission model. At minimum, gate the route behind `requireAuth` + `requireGuildMember(guildId)` (or a signed/expiring URL scheme if anonymous CDN-style serving is intentional). This needs an explicit decision before shipping.

3. **No upload size limit, no per-message file count limit.**
   The multipart branch reads each file fully into memory with `await file.arrayBuffer()` and pushes every `files[N]` field into `attachmentList`. There is no `MAX_FILE_SIZE`, no `MAX_FILES_PER_MESSAGE`, no cumulative-size cap, and no `Content-Length` short-circuit. An authenticated client can OOM the server with a single 5 GB POST or fan out hundreds of files per message. Discord's reference numbers are 25 MB / 10 files per non-Nitro message — pick comparable bounds, enforce them server-side before the `arrayBuffer()` read, and reject with `413 Payload Too Large` / a 400 with a useful code.

4. **No server-side MIME / extension validation.**
   The client filters by `file.type.startsWith('image/')`, but the server accepts any file and trusts `file.type` (browser-supplied) for `content_type`. This means a malicious client can upload `evil.html`, `evil.svg`, `evil.exe` and have it stored, indexed in `messages.attachments`, and served back via the static route. The current static route only sets `Content-Type` for `.jpg/.jpeg/.png/.gif/.webp` (everything else falls back to `application/octet-stream`, which mitigates direct script execution for most cases) but:
   - There is **no** allowlist on upload — arbitrary types persist on disk and in DB.
   - **SVG is not handled**, so an `.svg` upload is served as `application/octet-stream` *today* — but the moment someone "fixes" that to render SVGs, you inherit `<script>`-in-SVG XSS in the same origin as the chat client.
   - Storing the client-claimed `content_type` verbatim in the DB ties the row to an unverified value.
   Recommendation: server-side allowlist of `image/png|jpeg|gif|webp` (extension *and* magic-byte sniff), reject SVG by default, and recompute `content_type` from sniffed bytes rather than `file.type`.

5. **Static route's content-type detection is `endsWith` on the URL filename.**
   The path param has already been sanitized at write time, but `MessageItem` renders any image attachment whose stored `content_type` starts with `image/`. Combined with #4, an attacker who got *any* file stored can craft a URL that the server happily content-sniffs by suffix. Move the content-type decision to the stored attachment row (sniffed at upload), not to URL string matching.

## Product Impact

- **What users get:** paste an image (Ctrl+V), drag-drop, multi-file batches, per-thumbnail × remove, inline lazy-loaded preview capped at 400×300 with click-to-open. Empty-text + image-only sends now work. This matches the Discord mental model well.
- **What users will hit:**
  - No upload progress, no error toast on failure (the `fetch` in `sendMessageWithAttachments` calls `.json()` unconditionally; a non-JSON 4xx/5xx will reject in a way that surfaces only via `markFailed`).
  - `pendingFiles` is not cleared on send error, but the optimistic message is marked failed — the user sees a failed message and the previews still hanging in the composer with no obvious way to retry.
  - `URL.createObjectURL(file)` is created on every render and never revoked → small but real memory leak while previews are visible.
  - No HEIC / mobile-camera format handling (likely fine for v1, worth noting).
  - Orphan-file risk: files are written to disk *before* the DB insert. If `repos.messages.create` throws, the bytes leak onto disk forever. Either insert first then fsync the file, or write to a temp dir and rename atomically after the row commits.

## Suggestions (non-blocking)

- **Use the shared `api()` helper** in `sendMessageWithAttachments` (or factor a `apiRaw` that handles auth + base URL + `r.ok` + JSON parsing). The current direct `fetch` duplicates auth-token retrieval, omits `r.ok` checks, and will throw a confusing parse error on 5xx HTML responses.
- **Drop `(a: any)` in `MessageItem.tsx`** — `Message.attachments` is now `Attachment[]`, so the cast hides type errors. Same logic block is duplicated for the two render branches; extract an `<AttachmentImages />` component.
- **Remove the empty-string whitespace edits** to the two `<div>` lines in `MessageItem.tsx`; they're noise in the diff.
- **`messages.ts` route** mixes single quotes (new code) with double quotes (existing code). Pick one for diff readability — the existing file convention is double quotes.
- **`Attachment.url` is a relative path** (`/attachments/...`). For embeds in webhooks / federation / future CDN, consider returning an absolute URL or at least a `proxy_url` distinct from `url` like Discord does.
- **Migration v17 default `'[]'`**: cheap and fine, but when reading old rows the `toMessage` parse path also handles `null` gracefully — consider dropping the default to keep null vs `[]` semantically distinct, or keep the default and remove the null branch in `toMessage`. Right now both exist.
- **Tests**: this is a security-sensitive surface and there are zero new server tests. Please add: oversize rejection, count-limit rejection, MIME-allowlist rejection, path-traversal attempt on the GET route, unauthenticated GET behavior (whatever the chosen policy), and a happy-path multipart round-trip that asserts the row's `attachments` JSON shape.
- **Width/height** are typed on `Attachment` but never populated; either populate via a lightweight image probe (`probe-image-size` or `sharp`) or remove the optional fields until they're computed — clients that rely on them for layout (avoiding CLS) can't do so today.
- **Nonce validation regression risk**: in the multipart branch, `nonce` is taken from `payload.nonce` but is not type-checked until *after* the file writes have already happened. Move all validation (content length, nonce shape, message_reference shape) above the file I/O so a bad request never produces orphan bytes.
- **Migration test description** still says "fresh DB gets user_version = 10" but checks `17` — pre-existing drift, but worth fixing while you're in there.

## Positive Notes

- Clean Discord-compatible shape on `Attachment` (`id`, `filename`, `size`, `url`, `proxy_url`, `content_type`, `width`, `height`) — future federation / API consumers will appreciate the parity.
- Migration is properly idempotent (`tableExists` + column existence check) and follows the established v1–v16 pattern.
- `MessagesRepo.create` keeps a sensible default (`attachments || []`) so existing callers are unaffected.
- Client UX details are good: image-only sends supported, per-file remove `×`, drag-over and paste both wired, lazy loading on `<img>`, click-to-open opens raw URL in new tab.
- Multipart vs JSON branch in the route handler is clearly separated and the legacy JSON path is preserved bit-for-bit semantically.
- Type tightening from `attachments: unknown[]` → `Attachment[]` on `Message` is a real improvement; it'll catch downstream misuse at the type level.

---

**Recommended next step:** address Critical 1–4 before merge (path traversal, auth on GET, size/count caps, server-side MIME allowlist). After that, the rest is polish and can land iteratively.

`~/.openclaw/workspace/code-review/reviews/cove-374-nova.md`
