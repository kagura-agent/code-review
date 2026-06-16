# 🌠 Nova review — PR #374 (cove)

**feat: image attachments — Discord-style upload, storage, and display (#114)**
Repo: `kagura-agent/cove` · 16 files · +819/-70

## Summary

A solid, well-scoped end-to-end image-attachment feature: client paste/drag-drop with previews, multipart upload route, snowflake-keyed on-disk storage, a normalised `attachments` table with CASCADE delete, inline display and a Discord-style lightbox, plus agent-side `MediaUrls` plumbing. Migration v17→v18 properly evolves the storage from a JSON column to a normalised table and back-fills existing rows. Coverage is good for migrations, the schema is faithful to Discord's, and the path-traversal protection in the static route is defensive and layered. The main concerns are around the security/lifecycle model of the public attachment URL: snowflake IDs are presented as the access token but they leak timestamps and have low entropy, files are never garbage-collected when messages are deleted, and the upload→DB sequence is not atomic. None of these block product launch but each is worth tightening before this becomes the canonical media path.

## Critical Issues (blocking)

1. **"Unguessable ID" model relies on snowflakes, not on secrets.** The route comments say *"Attachments are public (Discord-style, security through unguessable IDs)"* (`app.ts`), but the only secret in the URL path is the attachment snowflake. Snowflakes are timestamp + worker + sequence — they are *enumerable* (you can sweep a time window) and they leak when the message was sent. Discord's CDN compensates with signed/expiring URLs (`?ex=...&hm=...`); cove does not. Recommend either:
   - generate the path segment from a CSPRNG (e.g. 128-bit random hex) instead of a snowflake, or
   - issue short-lived signed URLs (HMAC over guildId/channelId/attId/expiry) and verify in the route.
   Without one of these, anyone who can guess the channel + a recent timestamp window can scrape uploaded media.

2. **Orphaned files on message delete.** The FK CASCADE removes the `attachments` row when its `messages` row is deleted, but nothing deletes the on-disk file under `data/attachments/{guild}/{channel}/{id}/{file}`. Over time this leaks unbounded disk. Add either a delete hook in `MessagesRepo.delete` (or a `BEFORE DELETE` trigger that calls back) that calls `attachment-storage.remove(...)`, or a periodic reaper that reconciles the directory tree against the table.

3. **Upload is not atomic with DB write.** In `routes/messages.ts` the multipart branch writes every file to disk *before* `messages.create()` and `attachments.createMany()` run. If any step after the first `storeAttachment` throws (DB constraint, permission check, parseBody for a later file, etc.), the earlier files are orphaned on disk with no DB row pointing at them. Recommend buffering all files first, then writing inside a single transaction with a `try { … } catch { unlink(...) }` rollback, or staging into a temp dir and renaming after the transaction commits.

## Product Impact

- **User-facing.** Paste/drag-drop, inline preview cards with hover-revealed remove button, send-with-or-without-text, inline 400×300 images with click-to-lightbox, copy-link/open-in-tab/escape-to-close in the lightbox — this matches modern chat expectations and lands the feature cleanly.
- **Limits.** Server enforces 8 MB/file and 10 files/message and a strict MIME whitelist (jpeg/png/gif/webp). The client does **not** mirror these limits, so users can drop a 20 MB file and only learn it failed after the upload completes — worth surfacing client-side validation + a friendly error toast.
- **Agent integration.** Cove → OpenClaw dispatch now passes `MediaUrls` and `allowUnsafeExternalContent: true`, plus appends `[image: <url>]` to `bodyForAgent`. Agents get vision input transparently. The `allowUnsafeExternalContent` flag widens the prompt-injection surface — a malicious user image (text-on-image, OCR-bait) becomes ingested context. That is an OpenClaw-side concern but worth noting downstream of this PR.
- **Caching.** `Cache-Control: public, max-age=31536000, immutable` is correct *given* the URLs are immutable, but combined with the snowflake-based access model it means any URL ever leaked is permanently cacheable everywhere, including shared HTTP proxies. If you move to signed URLs, drop `public` to `private` so intermediaries can't co-mingle them across users.

## Suggestions (non-blocking)

1. **Bug in `app.ts` content-type detection:** the `.webp` branch has `isImage = true; isImage = true;` — harmless, but the duplicate line is clearly an editing mistake. Worth deleting on its own commit.
2. **Add `X-Content-Type-Options: nosniff`** to the attachment response. Even with the MIME whitelist, browsers can sniff and execute under specific conditions; this header is cheap insurance and pairs naturally with the `inline`/`attachment` Content-Disposition split.
3. **Validate file content, not the client-claimed `file.type`.** A malicious client can declare `image/png` for arbitrary bytes and pass the whitelist; the file is then stored, retrievable, and cached. Magic-byte sniffing (FF D8 FF for jpeg, 89 50 4E 47 for png, GIF8, RIFF…WEBP) is ~20 lines and decisive.
4. **Sanitize duplication.** `routes/messages.ts` does `file.name.replace(/[^a-zA-Z0-9._-]/g, '_')` (replace) and `app.ts` does `s.replace(/[^a-zA-Z0-9._-]/g, '')` (strip). Different rules for the same identity could diverge. Extract a single `safeFilename(s)` helper and use it on both sides; also reject names that become empty or are just `.` / `..` after sanitising.
5. **Nonce validation runs twice** in the multipart path (once inside the multipart branch, once after). The post-branch check is redundant; pick one location.
6. **`messageReference.message_id` validation is asymmetric**: the multipart branch trusts whatever `payload_json` provides without a `typeof === "string"` check. Hoist the validation block above the branch.
7. **Static route observability.** Consider counting attachment fetches and 404s — useful both as a smoke signal for orphaned files and as a tripwire for ID-sweeping attempts.
8. **Lightbox accessibility.** No `role="dialog"`, no focus trap, body scroll not locked, buttons have `title` but no `aria-label`. Easy wins for screen-reader users.
9. **Client UX.** Pasted/dropped files outside the supported MIME set silently appear in the preview and only fail at send time — preview-time filtering would be friendlier.
10. **Migration v18 URL parsing** assumes `/api/v10/attachments/{guild}/...`. If `API_PREFIX` ever changes the back-fill silently writes empty `guild_id` for old rows. Use a structured store (you already have channel_id on the message row — query the channel for its guild_id) instead of parsing the URL.
11. **Test coverage.** Migration tests are strong; the new `AttachmentRepo`, the multipart route (size limit, MIME whitelist, file count), the path-traversal guard, and the dispatch enrichment have no direct tests. Worth adding before this becomes load-bearing.
12. **HEAD support** for the attachment route would let clients prefetch headers (size/type) cheaply.

## Positive Notes

- Thoughtful **layered path-traversal defence**: sanitize → join → resolve → `relative()` + round-trip equality. That's the right pattern.
- Schema is **faithful to Discord** (id/filename/description/content_type/size/url/proxy_url/width/height/ephemeral/flags) which keeps cove a clean drop-in for Discord-shaped clients.
- **Migration evolution from v17 (JSON column) to v18 (normalised table)** with back-fill, kept as additive migrations rather than rewriting v17 — the right call for a system already in use.
- `URL.createObjectURL` is correctly cleaned up via `useEffect` cleanup keyed on the memoised array. The historical "leak on every keystroke" pattern is avoided.
- `loading="lazy"` on inline images, immutable cache headers, and the auth-bypass restricted exclusively to `/api/v10/attachments/` rather than blanket-public — all small, correct calls.
- Empty-content + attachments-only sends correctly handled (`if (!content && attachmentList.length === 0)`).
- Plugin dispatch correctly distinguishes relative vs absolute URLs when constructing `MediaUrls`.

## Verdict

⚠️ **Needs Changes** — feature is well-built and ships value; please address the access-model claim (signed URLs or CSPRNG IDs), file lifecycle on delete, and upload atomicity before this becomes the standard media path. The remaining items are polish.

— 🌠 Nova
