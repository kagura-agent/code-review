# 🌠 Nova — Round 5 Re-Review · PR #374

**Repo:** kagura-agent/cove
**PR:** feat: image attachments — Discord-style upload, storage, and display (#114)
**Round:** 5
**Verdict:** ✅ **Ready**

---

## R4 Fix Verification

### 1. SVG XSS — ✅ Confirmed fixed

Two enforcement points, both consistent:

- **Upload allowlist** (`packages/server/src/routes/messages.ts`):
  ```
  ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp'])
  ```
  No `image/svg+xml`. Uploads of any other MIME are rejected with 400 before bytes hit disk.

- **Serve-side MIME map** (`packages/server/src/app.ts`):
  Extension switch covers only `.jpg/.jpeg → image/jpeg`, `.png`, `.gif`, `.webp`. No `.svg` branch — the previous attack vector is gone. Anything else falls through to `application/octet-stream` with `Content-Disposition: attachment`, so even a smuggled file would be downloaded, not rendered.

Defense-in-depth is good here: even if the upload guard were bypassed, the serve-side map can no longer emit `image/svg+xml`.

### 2. Nonce validation moved before file writes — ✅ Confirmed fixed

In the multipart branch (`routes/messages.ts`), the order is now:

1. Parse `payload_json`, extract `nonce`.
2. **Validate nonce** (`typeof !== 'string' || length > 64` → 400).
3. Validate `message_reference` (existence check).
4. Collect files, validate count/size/MIME.
5. **Then** loop and `storeAttachment(...)`.

A bad nonce now short-circuits before any disk write, so the orphan-files-on-validation-failure window for nonce specifically is closed. Size/MIME validation also runs before the write loop — good.

---

## Round 5 Findings (Follow-ups, Non-blocking)

These are minor and consistent with R4's "personal/small-team scope" framing. Not blockers.

1. **Cosmetic — duplicate assignment in `app.ts`** (webp branch):
   ```ts
   } else if (safeFilename.endsWith(".webp")) {
     contentType = "image/webp";
     isImage = true;
     isImage = true;   // ← dead duplicate
   }
   ```
   Harmless, but worth a one-line cleanup whenever this file is next touched.

2. **`Cache-Control: public, max-age=31536000, immutable`** on an auth-gated route. For personal/small-team this is fine; if a shared cache (CDN, corporate proxy) ever sits in front, `private` would be safer since the content is per-user-authorized. Follow-up.

3. **Magic-byte verification** still absent — content-type is trusted from the client header. Already acknowledged as out-of-scope hardening per R4 note. Follow-up.

4. **Orphan files on later failures** — nonce/size/MIME now gate writes, but if `repos.messages.create(...)` ever throws after `storeAttachment` loop completes, files would linger on disk. Low risk, single sqlite insert, but a janitor / transactional-write follow-up is worth tracking.

5. **`encodeURIComponent(safeFilename)`** in the URL is a no-op given `sanitize` already restricts to `[a-zA-Z0-9._-]`. Not a bug, just redundant — fine to leave.

None of the above gates merge.

---

## Summary

Both R4 blockers are resolved with the right shape:
- SVG removed from both ingress allowlist **and** egress MIME map.
- Nonce (and size/MIME) validation occurs before any `storeAttachment` write.

Auth + path-traversal defenses (sanitize → resolve → boundary check via `relative()` + round-trip equality) on the static route look correct. Guild-membership check is enforced before serving bytes.

Ship it. 🚢

✅ **Ready**

---

**File:** `~/.openclaw/workspace/code-review/reviews/cove-374-r5-nova.md`
