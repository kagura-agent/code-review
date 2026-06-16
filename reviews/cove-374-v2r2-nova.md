# 🌠 Nova — Round 2 (v2r2) Re-review of PR #374

**PR:** feat: image attachments — Discord-style upload, storage, and display (#114)
**Repo:** kagura-agent/cove
**Round:** 2 (re-review of v2 rework)

## Verdict: ✅ Ready (with two cosmetic cleanups noted)

Both Round 1 issues are genuinely resolved. The cleanup logic is correct for the personal/small-team scope. A couple of dead/duplicated lines slipped in and there's one low-risk edge case worth flagging as follow-up — none are blockers.

---

## 1. Round 1 Fix Verification

### Fix #1 — Orphaned files on delete: ✅ Fixed

`cleanupAttachmentFiles()` is added to `packages/server/src/routes/messages.ts` and wired into all three delete paths:

| Path | Order | Behavior |
| --- | --- | --- |
| Single message delete | `getByMessageId(msgId)` → `messages.delete()` → `cleanupAttachmentFiles(...)` | ✅ Correct: collects rows before FK CASCADE wipes them. |
| Bulk delete | Collect attachments for each `msgId` → `db.transaction(... messages.delete ...)` → cleanup if `deleted.length > 0` | ✅ Mostly correct (see edge case below). |
| Clear-all (`DELETE /messages`) | `getByChannelId(channelId)` → `messages.deleteAll()` → cleanup if `count > 0` | ✅ Correct. |

Implementation details look sound:
- URL parsing in `cleanupAttachmentFiles` correctly indexes from the `attachments` segment (resilient to `API_PREFIX` changes).
- `decodeURIComponent` matches the `encodeURIComponent` used at upload time — no filename mismatch on disk.
- Errors are swallowed (`.catch(() => {})`) — acceptable fire-and-forget for personal scale; consider `log.warn` later for ops visibility.
- Empty parent directories (`{guildId}/{channelId}/{attId}/`) are not removed. Cosmetic accumulation only; can be a follow-up sweep.

### Fix #2 — Deleted attachments still accessible: ✅ Fixed

`GET /attachments/:guildId/:channelId/:attachmentId/:filename` now calls `repos.attachments.exists(safeAttachmentId)` before reading from disk. Combined with the FK `ON DELETE CASCADE` on `attachments.message_id`, this means:
1. `messages.delete()` cascades the `attachments` row away.
2. Subsequent GET requests hit the `exists()` check and 404.
3. The async `cleanupAttachmentFiles` then unlinks the file (best-effort).

Even if file unlink lags or fails, the DB-gate ensures no further serving. ✅ Solid.

---

## 2. Issues Found in v2r2

### 🔴 Cosmetic — duplicated lines in `app.ts` (worth fixing before merge)

In the GET attachment handler, the DB existence check is written twice in a row:

```ts
// Verify attachment exists in DB (prevents access to deleted attachments)
if (!repos.attachments.exists(safeAttachmentId)) {
  return c.json({ message: 'Attachment not found', code: 10008 }, 404);
}

// Verify attachment exists in DB (prevents access to deleted attachments)
if (!repos.attachments.exists(safeAttachmentId)) {
  return c.json({ message: 'Attachment not found', code: 10008 }, 404);
}
```

And in the content-type table:

```ts
} else if (safeFilename.endsWith(".webp")) {
  contentType = "image/webp";
  isImage = true;
  isImage = true;   // ← duplicated
}
```

Both are harmless at runtime but reviewers will trip on them. Easy delete.

### 🟡 Edge case — bulk delete may unlink files for not-actually-deleted messages

```ts
const allAttachments: Attachment[] = [];
for (const msgId of body.messages) {
  const attachments = repos.attachments.getByMessageId(msgId);
  allAttachments.push(...attachments);
}
const deleted: string[] = [];
repos.db.transaction(() => {
  for (const msgId of body.messages) {
    if (repos.messages.delete(channelId, msgId)) deleted.push(msgId);
  }
})();
if (deleted.length > 0) {
  cleanupAttachmentFiles(allAttachments).catch(() => {});
}
```

`allAttachments` is gathered for every requested ID up-front. If some `messages.delete()` calls return `false` (race, permission, missing message) but at least one succeeds, files for the *non-deleted* ones get unlinked while their DB rows remain — orphan rows pointing at missing files. In practice it's hard to hit (requested-but-missing IDs return empty attachment lists), but it's not zero.

Recommendation (follow-up): collect attachments inside the transaction, only for successfully deleted messages. Or query `getByMessageIds(deleted)` after the transaction.

### 🟡 Defense-in-depth — `cleanupAttachmentFiles` doesn't re-validate the resolved path

The GET route correctly bounds the resolved path under `ATTACHMENT_ROOT`:

```ts
const ATTACHMENT_ROOT = resolve(process.cwd(), 'data', 'attachments');
const resolvedPath = resolve(filePath);
const rel = relative(ATTACHMENT_ROOT, resolvedPath);
if (rel.startsWith('..') || resolve(ATTACHMENT_ROOT, rel) !== resolvedPath) { ... }
```

`cleanupAttachmentFiles` doesn't. URLs are server-generated so it's unreachable today, but mirroring the same boundary check would be cheap insurance against a future bug that lets user-controlled URLs reach storage.

### 🟢 Nits / non-blocking

- `cleanupAttachmentFiles` failures are silenced; one `console.warn` would help on-call.
- `getByChannelId` loads every attachment row for the channel before clear-all — fine at personal scale, would want pagination later.
- The duplicated `attachment-preview-actions` style block in `MessageInput.tsx` is fine; just noting `display: 'none'` + CSS-hover override in `.css` works but is fragile across themes.

---

## 3. Things I checked and was happy with

- Multipart parsing validates file count (≤10) and file size (≤8MB) and content-type allow-list (`image/{jpeg,png,gif,webp}`) **before** writing any file. ✅
- `safeFilename = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')` is applied to the on-disk name; original filename is preserved in `Attachment.filename` for display. ✅
- Snowflake IDs for attachments — unguessable, matches the "security through unguessable IDs" model called out in the diff comment. ✅
- v17→v18 migration: keeps the v17 JSON column in place (SQLite can't drop), creates `attachments` table, migrates rows, has a test. ✅ Schema includes `ON DELETE CASCADE` on `message_id`. ✅
- Lightbox uses `cursor: 'zoom-out'` + `e.stopPropagation()` on the inner image — won't dismiss when interacting with image. ✅
- Dispatch passes `MediaUrls` + `allowUnsafeExternalContent` to the agent so the bot can see image URLs. ✅

---

## Summary

Round 1 blockers are real-fixed. The two duplicated code fragments in `app.ts` are the only items I'd want squashed before merge — they're cosmetic but obvious. The bulk-delete partial-fail edge case and missing path-boundary check in cleanup are reasonable post-merge follow-ups for the personal/small-team scope.

**Rating: ✅ Ready** (please remove the duplicated `exists()` block and the duplicated `isImage = true;` line in `app.ts`).
