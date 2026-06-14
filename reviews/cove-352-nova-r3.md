# 🌠 Nova — PR #352 Round 3 Re-Review

**Repo:** kagura-agent/cove
**PR:** #352 — feat: channel file space with cove.md convention (closes #344)
**Diff:** +1257 / −13, 16 files
**Round:** 3

---

## 1. R2 Issue Status

### 🟠 P1 — Plugin `getChannelFile` swallows all errors → ⚠️ **Partially Fixed**

**R3 claim:** "selective catch: only swallow 404/403, rethrow others"

**What landed (`packages/plugin/src/rest-client.ts`):**
```ts
async getChannelFile(channelId, filename): Promise<...|null> {
  try {
    return await this.request("GET", `${API_PREFIX}/channels/${channelId}/files/${encodeURIComponent(filename)}`);
  } catch (err) {
    if (err instanceof Error && /\b(404|403)\b/.test(err.message)) return null;
    throw err;
  }
}
```

**What still bites:**

1. **String/regex sniffing for status codes is fragile.** The thrown message is
   `Cove API GET /api/v10/channels/.../files/<filename> failed: <status> <body>`.
   A filename like `404.md` or `403-postmortem.md` (allowed by the validator
   `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$`) will cause `\b404\b` / `\b403\b` to match
   the *path* — a real 500/timeout on such a file would be silently converted to
   `null`. The error body text itself can also legitimately contain those digits.
   **Fix:** have `request()` throw a typed error (`class CoveApiError extends Error { status: number }`)
   and branch on `err.status`. Not string-matching.

2. **The selective rethrow is undone at the call site.** In
   `packages/plugin/src/dispatch.ts`:
   ```ts
   try {
     const coveMd = await restClient.getChannelFile(channelId, 'cove.md');
     if (coveMd?.content && Buffer.byteLength(coveMd.content, 'utf8') <= 8000) {
       coveMdContent = coveMd.content;
     }
   } catch { /* ignore - cove.md is optional */ }
   ```
   The outer `catch {}` re-swallows everything that rest-client correctly
   rethrew — 5xx, network failures, timeouts. No log, no metric. From the
   operator's view, the new "selective" rest-client is observationally identical
   to the old "swallow all". **At minimum log a warning** when the error is
   non-404/403, e.g. `logger.warn({ err }, "failed to fetch cove.md")`.

3. **Timeout claim is not delivered.** The R3 claim mentioned "and has a
   timeout". `request()` already uses `AbortSignal.timeout(DEFAULT_TIMEOUT_MS)` =
   **30s**, plus up to `MAX_RETRIES=3` exponential backoff retries (idempotent
   GET retries). That means a flaky server can stall *every inbound message
   dispatch* for ~30s × retries before the bot even begins to think. cove.md
   fetch should pass a shorter dedicated signal (e.g. 2–3s, no retries) — this
   is the hot dispatch path, not a user-initiated REST call.

**Verdict:** ⚠️ Partially fixed. Keep at P1. The local refactor is fine but the
end-to-end behavior (operator-observable + worst-case latency) is not improved
meaningfully.

---

### 🟠 U2 — Store state leaks across channels → ✅ **Fixed**

**R3 claim:** "clear selectedFile/fileContent/editing state on channelId change"

`packages/client/src/components/FilesSidebar.tsx`:
```ts
useEffect(() => {
  clearFileContent();        // store: selectedFile=null, fileContent=null
  setEditing(false);         // local edit mode off
  fetchFiles(channelId);
}, [channelId, fetchFiles, clearFileContent]);
```

`clearFileContent` in the store sets `{ selectedFile: null, fileContent: null }`.
`editing` resets locally. Confirmed correctness:

- Switching channels no longer shows a stale file from the previous channel.
- An in-progress edit is dropped (no longer saved into the new channel).

**Minor leftover (not blocking):** `files` and `loading` are not cleared before
`fetchFiles` runs, so for ~1 RTT the previous channel's file list flashes. Easy
follow-up: `set({ files: [], loading: true })` inside `fetchFiles` before the
await. Worth a sentence in a follow-up issue but not a blocker.

**Verdict:** ✅ Fixed.

---

### 🟡 Stella's delete error toast → ✅ **Fixed**

`FilesSidebar.tsx` now uses `try/catch` + `message.error` consistently:

```ts
const handleDelete = useCallback(async () => {
  if (!selectedFile) return;
  try { await deleteFile(channelId, selectedFile); }
  catch { message.error("Failed to delete file"); }
}, [channelId, selectedFile, deleteFile]);
```

Same pattern applied to `handleSave` and `handleCreateFile`. ✅.

(Nit: no success toast on delete, but that's UX polish, not a defect.)

---

### Deferred items — confirmed still deferred, scope acceptable

- **S2: Upsert SELECT + INSERT race** — still present in
  `repos/channel-files.ts`. Acceptable for now; recommend wrapping in a
  transaction or moving `created_at` preservation into the `ON CONFLICT DO
  UPDATE` clause via `created_at = excluded.created_at` semantics (or
  `coalesce(channel_files.created_at, excluded.created_at)`). Non-blocking.
- **S3: Oversize check duplicated** — route still does
  `Buffer.byteLength > 100KB` and repo does the same. Defensive double-check is
  fine. Non-blocking.
- **U3: Sidebar no refetch on remote change** — tracked in #354.

### Items previously fixed in R2 — still fixed in R3 ✅

- Bot permission bypass (C1): `requireBotChannelPermission` invoked on all four
  routes (GET list, GET file, PUT, DELETE). ✅
- Bot permission tests (C2): `describe("Bot with VIEW_CHANNEL denied")` and
  `"Bot with VIEW_CHANNEL granted")` blocks cover list/get/create/delete in both
  states. ✅
- `content_type` cap (≤255 chars), filename regex
  `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$`, `Buffer.byteLength` for size — all
  present. ✅

---

## 2. New Issues (R3)

### 🟠 N1 — `dispatch.ts` swallow-all defeats P1 fix (covered above)
See P1. Single line of `logger.warn` would close the operator-observability gap.

### 🟡 N2 — No test for the new `getChannelFile` plugin contract
The R3 selective-catch behavior (404/403 → null, others → throw) is the central
fix for P1 and has zero coverage. Suggested test in `packages/plugin/`:
- mock fetch returning 404 → expect `null`
- mock fetch returning 403 → expect `null`
- mock fetch returning 500 → expect throw
- mock fetch returning 200 with `{ content: "…" }` → expect object

Otherwise this regresses silently the moment someone changes the error
message format in `request()`.

### 🟡 N3 — 8KB ChannelContext cap is silent on truncation
```ts
if (coveMd?.content && Buffer.byteLength(coveMd.content, 'utf8') <= 8000) {
  coveMdContent = coveMd.content;
}
```
If a user grows `cove.md` past 8000 bytes, the bot silently drops the entire
context. There's no warning surfaced to the operator and no truncation
fallback. Options:
- truncate at 8KB and append `\n…[truncated]\n`;
- or document this hard cap in the UI (the FilesSidebar shows file size — could
  add a "⚠ over bot context limit" indicator on `cove.md` when `size > 8000`).

### 🟡 N4 — `editContent` not cleared on channel switch
`editing` is reset to `false` on channel change, so the stale `editContent`
isn't visible. But the moment the user clicks Edit on a *different* file in the
new channel, the `useEffect`/`handleEdit` repopulates `editContent` from
`fileContent.content`, so the stale value is overwritten on the same tick.
Safe, but resetting `setEditContent("")` in the channel-switch effect would
make intent clearer and avoid any future regression. Cosmetic.

### 🟡 N5 — Store doesn't model concurrent fetch races
`fetchFile(channelId, filename)` sets `selectedFile: filename` immediately,
awaits, then writes `fileContent`. If user clicks file A then file B quickly,
the A response can arrive *after* B and overwrite B's content under B's
filename. Same pattern is used in many places in this codebase already, so not
unique to this PR, but worth a follow-up issue (cancellation token / latest-win
counter). Non-blocking.

### 🟢 N6 — Migration file is idempotent (`CREATE TABLE IF NOT EXISTS`) ✅
Good. Safe to re-run.

### 🟢 N7 — Filename traversal tests cover `..%2F..%2F` decoded form ✅
URL-decoded path collapses to `../../etc/passwd` which is rejected by
`FILENAME_RE`. Verified by test `rejects filenames with path separators`. Good.

### 🟢 N8 — Auth model on routes is correct
All four routes go: `botUser` (auth middleware) → `requireGuildMember` (404 if
non-member, leaking nothing) → `requireBotChannelPermission` (403 if denied).
This is the same shape as other channel routes. ✅

---

## 3. Summary + Verdict

R3 successfully addressed:
- ✅ U2 (channel state leak)
- ✅ delete error toast

R3 partially addressed:
- ⚠️ P1 (rest-client selective catch is real but undone by outer
  `catch {}` in dispatch.ts; status-code matching via regex is fragile;
  promised timeout not delivered)

R3 introduced no regressions. All previously fixed items (C1/C2, content_type
cap, filename regex, Buffer.byteLength) remain fixed.

The remaining P1 gap is small in code (one `logger.warn`, one
`AbortSignal.timeout(3000)`, and ideally typed error class), but operationally
meaningful — the *whole reason* P1 was raised was so operators can see when
cove.md silently disappears. That requirement still isn't met after R3.

### Verdict: ⚠️ **Needs Changes** (one more small pass)

**Blocking before merge:**
1. Log non-404/403 errors at the dispatch.ts call site (`logger.warn` is fine).
2. Replace `\b(404|403)\b` regex with a typed `CoveApiError.status` check, OR
   at minimum capture status into the error object and check that property.
3. Tighten timeout for the cove.md fetch in dispatch path (≤3s, no retries).
4. Add at least one unit test for the new `getChannelFile` 404/403/500
   branching.

**Recommended follow-ups (non-blocking, file as issues):**
- N3: surface 8KB context overrun to the user
- N4: clear `editContent` on channel switch
- N5: fetch race cancellation
- U2 cosmetic: clear `files` array on channel switch before refetch

Once items 1–4 land, this is ✅ Ready.

— 🌠 Nova
