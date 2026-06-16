# 🌠 Nova — Round 4 Re-Review: PR #374 (cove)

**PR:** feat: image attachments — Discord-style upload, storage, and display (#114)
**Verdict:** ⚠️ **Needs Changes** (one new finding; both R3 fixes confirmed)

---

## R3 Fix Verification

### ✅ Fix 1: Attachment URL under `API_PREFIX`
Confirmed. `routes/messages.ts` builds:

```
url: API_PREFIX + '/attachments/' + channel.guild_id + '/' + channelId + '/' + attId + '/' + encodeURIComponent(safeFilename)
```

…and `app.ts` registers the matching route at `API_PREFIX + "/attachments/:guildId/:channelId/:attachmentId/:filename"`. With `API_PREFIX = '/api/v10'` (from `packages/shared/src/types.ts`), the URL falls under `/api/*`, so:

- Vite dev proxy forwards it ✓
- `app.use("/api/*", rateLimitMiddleware())` covers it ✓
- `requireAuth` middleware (passed in as `authMw`) runs and resolves cookie/Bearer auth ✓
- `credentials: 'include'` on the upload `fetch` carries the session cookie ✓

Path‑traversal hardening is solid: dual sanitize + `resolve(ATTACHMENT_ROOT)` + `relative()` boundary check + `resolve(rel) === resolvedPath` round‑trip. Good defensive depth.

### ✅ Fix 2: `c.get('botUser')` is correct
Verified against the actual head SHA of `packages/server/src/auth.ts`:

```ts
export type AppEnv = { Variables: { botUser: AuthUser } };
…
c.set("botUser", result.user);
```

Not a typo — `botUser` is the canonical key. R3 finding withdrawn. My apologies for the false flag last round.

---

## 🔴 New Finding: SVG inline serving → stored XSS

**File:** `packages/server/src/app.ts` (attachments route, MIME map)
**Severity:** Real, but adjacent to the deferred "magic bytes" follow‑up. Fix is a one‑liner, so I'm calling it out for R4.

The upload allowlist rejects `image/svg+xml`:

```ts
const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp']);
…
if (!ALLOWED_IMAGE_TYPES.has(file.type)) { return … }
```

But the check is on **client‑claimed MIME** (`file.type`), and the **filename extension is preserved** by `safeFilename = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')`. The serve route then derives content type from extension and uses `inline` disposition for "images":

```ts
} else if (safeFilename.endsWith(".svg")) {
  contentType = "image/svg+xml";
  isImage = true;
}
…
"Content-Disposition": isImage ? `inline; filename="…"` : `attachment; filename="…"`,
```

**Exploit path** (no magic bytes needed):
1. Attacker crafts `evil.svg` whose contents are an SVG with `<script>…</script>`.
2. Sets the multipart part's `Content-Type` to `image/png` (or any allowed MIME). The `file.type` check passes.
3. Server stores the bytes verbatim with filename `evil.svg`.
4. Any viewer loads `<img src="/api/v10/attachments/.../evil.svg">` — but the route returns `Content-Type: image/svg+xml; inline`. Browser executes the embedded `<script>` in the app's same origin → cookie/session theft, message exfiltration, etc.

Adjacent issues that make this worse:
- Stored extension is whatever the client sends (sanitized regex permits `.svg`, `.html`, etc.). Today only `.svg` matches a dangerous MIME in the map; tomorrow if someone adds `.html` or `.xml` mappings, same vector reopens.

**Fix options (pick one — all easy):**

1. **Drop the `.svg` branch from the MIME map** entirely (cleanest — SVG can never be uploaded successfully today, so the branch is dead code that creates a vulnerability):
   ```ts
   // remove the ".svg" else-if; non-allowed extensions fall through to
   // application/octet-stream + attachment disposition.
   ```
2. Whitelist served extensions to match the upload allowlist (`.jpg/.jpeg/.png/.gif/.webp`); reject everything else with 404.
3. Always serve as `attachment` for `.svg`/unknown.

Option 1 is the smallest diff and aligns serve‑side with upload‑side policy. I'd take it now and leave magic‑byte verification as the remaining follow‑up the author already scoped out.

---

## Other Observations (non‑blocking)

### Client

1. **`MessageInput.tsx` — `useMemo` recreates all object URLs on every `pendingFiles` change.** Adding one file revokes the previously created URLs for files that didn't change and creates fresh ones for them. Correctness is fine (cleanup runs in order), but it churns blob URLs. Optional: keep a `Map<File, string>` in a ref and only allocate per new file.

2. **`MessageItem.tsx` — `(a: any)` typing.** `message.attachments` is now `Attachment[]` after the shared‑types change, so `(a: Attachment) => …` would drop the `any` casts. Two near‑identical attachment‑rendering blocks (group‑start branch and continuation branch) are also a duplication smell — extracting an `<AttachmentList attachments={…} />` would tighten this and keep the two branches in sync.

3. **Unrelated whitespace‑only edits** in `MessageItem.tsx` (the empty‑attribute lines). Harmless; likely a formatter pass.

### Server

4. **`attachment-storage.ts` — `getAttachmentPath` is `async` but does no I/O.** Could be plain sync; not a bug, just noise.

5. **Two definitions of the storage root.** `attachment-storage.ts` uses `join(process.cwd(), "data", "attachments")` and `app.ts` recomputes `resolve(process.cwd(), 'data', 'attachments')` for the boundary check. They agree today; if anyone changes one and not the other the boundary check could let traversal through (if the actual storage moves) or reject all paths (if the boundary moves). Worth exporting a single `ATTACHMENT_ROOT` constant from `attachment-storage.ts` and importing it in `app.ts`.

6. **`guildId` in URL is not used for authz.** The route trusts only `safeChannelId` (looks up `channel.guild_id` from DB) for the membership check. That's correct (avoids confused‑deputy on a forged path), but means the `guildId` URL segment is purely decorative. Fine, but consider asserting `safeGuildId === channel.guild_id` and 404'ing on mismatch — makes log forensics tidier and prevents off‑guild URL leakage.

7. **8MB body held in memory.** `c.req.parseBody({ all: true })` buffers the whole multipart before checks fire. With `MAX_FILES = 10` and `MAX_FILE_SIZE = 8MB`, a single request can consume up to ~80MB before per‑file rejection. Not a regression; just flagging for the orphan/quota follow‑up.

8. **`message_reference` validation in the multipart branch is laxer than JSON.** JSON branch validates `typeof body.message_reference.message_id === 'string'`; multipart branch goes straight to `repos.messages.getById(channelId, payload.message_reference.message_id)`. If `payload.message_reference.message_id` is a non‑string (e.g., number, object), `getById` likely coerces or returns undefined, but it's an inconsistency. Trivial to align.

9. **`nonce` validated after the DB write in multipart path.** Re‑read the route flow: nonce length check now runs after `repos.messages.create(...)`. In R2 we explicitly moved this *before* the write to avoid orphan rows. The new ordering reintroduces the orphan window for oversized nonces. Move the nonce validation up before the `create()` call.

   ```ts
   // Currently:
   const message = repos.messages.create(…);
   if (nonce) { if (typeof nonce !== 'string' || nonce.length > 64) { return validationError(c, …); } }

   // Should be: validate nonce before create()
   ```

   This applies to both branches — please reorder so all validation completes before any write or any file is `storeAttachment`'d.

### Tests

10. Migration test version bumps from 16 → 17 are mechanical and consistent. No new test for the attachments column shape, the multipart route, or the static serve route. Even one happy‑path integration test (upload → list → fetch image) would lock the contract; an SVG‑rejection test would lock the fix above. Strongly recommend before merge given the surface area.

---

## Summary

| Item | Status |
|---|---|
| R3 Fix 1: URL under `API_PREFIX` | ✅ Verified |
| R3 Fix 2: `botUser` type | ✅ Verified against `auth.ts` head SHA |
| SVG inline XSS via extension mismatch | 🔴 New, blocking — one‑line fix |
| Nonce validation re‑ordered after DB write | 🟡 Regression of R2 fix |
| Type tightening / dedup / shared `ATTACHMENT_ROOT` | 🟢 Nits |
| Tests for new route | 🟡 Recommended before merge |

**Rating:** ⚠️ **Needs Changes** — fix the SVG MIME branch and restore pre‑write nonce validation. Everything else is in good shape; the auth/path‑traversal hardening is genuinely careful work.

— Nova
