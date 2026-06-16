# 🌠 Nova — Round 3 Review · cove#374 (image attachments)

**Verdict: ⚠️ Needs Changes (one real issue) — otherwise close to ✅ Ready**

The R2 issues are all genuinely fixed. R3 introduces no regressions, and the
overall shape (multipart upload → snowflake-id directory → authorized GET
endpoint → JSON column on `messages`) is sound. There is one **real bug** I
want fixed before merge, plus a small set of suggestions calibrated for the
personal/small-team scope.

---

## R2 fixes — verification

### 1. Authorization on attachment GET — ✅ Fixed
`app.ts` now mounts the route with `authMw`, then loads the `channel` and
checks `repos.members.get(channel.guild_id, user.id)`. This correctly couples
authentication and guild membership before any disk read. Returning
`Missing Access / 50001` for non-members is consistent with the rest of the
API surface. Good.

Minor: the `guildId` from the path is *not* re-checked against
`channel.guild_id`. So a user who is a member of guild A could request
`/attachments/<guildB>/<channelB>/...` and, since membership is keyed off the
*real* `channel.guild_id`, that request will only succeed if they’re also a
member of guild B — which is the actually-correct check. So there’s no
authorization hole, but the URL `guildId` segment is now decorative. That’s
fine; just noting it’s effectively redundant and the channel-derived guild is
the source of truth.

### 2. Path traversal — ✅ Fixed (belt + suspenders)
Two layers now:
1. `sanitize()` strips everything outside `[a-zA-Z0-9._-]` from each segment.
2. `path.relative()` + `resolve()` round-trip boundary check against
   `ATTACHMENT_ROOT`.

The boundary check is correctly written:
```ts
if (rel.startsWith('..') || resolve(ATTACHMENT_ROOT, rel) !== resolvedPath) { ... }
```
This catches both upward escapes and the rare absolute-path edge case.
Combined with the sanitizer it’s defense-in-depth, which is appropriate for
serving arbitrary filenames from disk. ✅

One nit: `ATTACHMENT_ROOT` is recomputed per request from `process.cwd()`.
Same as in `attachment-storage.ts`. If anything ever calls `chdir`, the two
would silently disagree. Hoist them to a module constant or `import.meta.url`
based path. Low priority.

### 3. Content-Disposition inline vs attachment — ✅ Fixed
`isImage` flag drives `inline` for jpg/jpeg/png/gif/webp/svg, `attachment`
otherwise. The HTML-escape concern from R2 is addressed structurally: the
filename has already passed `sanitize()` (no quotes, no spaces, no semicolons
can survive), so the `filename="..."` header is safe. ✅

Subtle: the route currently only ever serves the five image MIME types
because **uploads are restricted to jpeg/png/gif/webp** (svg is *not* in
`ALLOWED_IMAGE_TYPES`). So `image/svg+xml` is wired in the GET handler but
unreachable via the POST. That’s harmless, just dead-ish code. If you ever
add svg uploads, please remember the XSS surface — `inline` + `image/svg+xml`
served same-origin lets a uploaded SVG run JS in the app origin, and right now
the GET would happily serve it. Document or guard.

### 4. Client memory leak — ✅ Fixed
```ts
const previewUrls = useMemo(() => pendingFiles.map(f => URL.createObjectURL(f)), [pendingFiles]);
useEffect(() => { return () => { previewUrls.forEach(URL.revokeObjectURL); }; }, [previewUrls]);
```
Correct: each new `pendingFiles` array yields a fresh `previewUrls` reference,
the cleanup runs against the **previous** array (closure capture), and a final
unmount cleanup runs on the last array. No leaks across removes/sends/unmounts.
✅

### 5. Client `res.ok` check — ✅ Fixed
`sendMessageWithAttachments` now does `if (!res.ok) throw new Error(...)`,
which propagates into the existing `try/catch` in `handleSubmit` and triggers
`markFailed(tempId)`. The `.json().catch(() => ({}))` for the error body is a
nice touch. ✅

---

## Earlier open items — status in R3

| Item | Status |
|---|---|
| Content-type from URL suffix vs stored metadata | ⚠️ Still suffix-based on GET. Stored `content_type` in DB is not consulted. See **Issue B**. |
| Orphan file risk | ⚠️ Files written to disk **before** message row insert; if insert fails, files leak. See **Issue A** (which is the real bug) and **Suggestion 1**. |
| Validation ordering | ✅ Mostly fixed. Size/count/MIME checks now run before any disk write. |
| MIME trusts `file.type` (no magic bytes) | ⚠️ Still trusted. Acceptable for personal scope. See **Suggestion 2**. |
| Upload limit timing | ✅ All file size/count/type checks run before `storeAttachment`. |
| Duplicate image block in `MessageItem` | ⚠️ Still duplicated (the grouped + non-grouped branches each render the attachments map). Pre-existing pattern, see **Suggestion 3**. |

---

## Issue A — 🔴 Real bug: server-rendered attachment URL won’t resolve in the browser

`packages/server/src/routes/messages.ts`:
```ts
url: '/attachments/' + channel.guild_id + '/' + channelId + '/' + attId + '/' + encodeURIComponent(safeFilename),
```

`packages/server/src/app.ts` mounts the GET handler at:
```ts
app.get("/attachments/:guildId/:channelId/:attachmentId/:filename", authMw, ...)
```

The route is gated by `authMw` (Bearer token / session cookie). The client
renders attachments via:
```jsx
<img src={att.url} ... />
```

Two problems combine into a real failure on prod-like deploys:

1. **No token on `<img>` requests.** Browsers don’t attach `Authorization`
   headers to `<img src>`. Auth must therefore come from the session cookie.
   That works *if* the cookie is `SameSite=Lax/None` and the image origin
   matches the API origin.

2. **Origin mismatch in dev.** `vite.config.ts` only proxies `/api` and
   `/gateway`. `/attachments/*` is **not** proxied, so the `<img>` request
   goes to the dev server origin (5173) which has no such route → 404.
   Even in prod, the `url` is origin-relative — fine when API and client are
   served from the same origin, broken when `VITE_COVE_API_URL` is set (the
   client would request the attachment from its own origin, not the API).

   `sendMessageWithAttachments` already shows the right pattern:
   `API_BASE + API_PREFIX + ...`. Attachment URLs need to use `API_BASE` too,
   either by (a) returning an absolute URL from the server using a configured
   public base, or (b) returning a relative path under `/api/...` and adding
   the `/api` prefix-aware proxy rule, or (c) having the client prepend
   `API_BASE` when it’s set.

   The simplest fix that matches the rest of the codebase: mount the GET
   handler under `${API_PREFIX}` (i.e. `/api/attachments/...`) so the
   existing Vite `/api` proxy and existing `API_BASE` plumbing both Just
   Work, and the existing `app.use("/api/*", authMw)` covers it (you can
   drop the explicit `authMw` on the route).

Please pick one of the three options and update the URL we store in the DB to
match. Otherwise images send fine but render broken on every deploy that
isn’t same-origin and on `vite dev`.

---

## Issue B — 🟡 Content-Type derived from filename suffix on GET

The GET handler picks Content-Type by inspecting `safeFilename.endsWith(...)`
and ignores the stored `content_type` from the message’s `attachments` JSON.
Two consequences:

- `image/svg+xml` is reachable purely from a `.svg` extension, which can
  never happen via uploads today, so it’s currently dormant. (Already noted
  above.)
- If you ever add stricter server-side detection (e.g. magic-bytes), the
  authoritative value won’t be used at serve time.

Cheap fix: pass the `attachmentId` through to a small lookup
(`messages.findAttachment(attId)` or similar) and serve `content_type` from
the row. Or, since the message id isn’t in the URL, just drop `.svg` from the
suffix table and call it good. Low severity in personal scope.

---

## Suggestions (small-team severity)

1. **Atomic upload semantics.** Disk writes happen, then the SQLite insert
   runs. If `repos.messages.create` throws (FK conflict, db locked, etc.),
   the files become orphans. Cheap mitigation: write to a temp dir, do the
   DB insert, then `rename` into place — or just add a periodic sweep that
   deletes attachment dirs whose IDs aren’t referenced by any message row.
   Either is fine for personal scope, but right now there is *no* cleanup
   path at all, including for normal message deletes (`messages.delete`
   doesn’t touch the filesystem). Worth at least a TODO/issue.

2. **Magic-byte verification.** `file.type` is client-supplied. A user can
   POST any bytes labeled `image/png`. For personal/small-team this is
   acceptable; if you want to harden later, run a 10-byte sniff
   (`file-type` package) before `storeAttachment` and reject mismatches.

3. **Duplicate attachment render block in `MessageItem.tsx`.** The grouped
   and non-grouped branches each contain the same `message.attachments
   ?.filter(...).map(...)` block. Lift it into a small `AttachmentList`
   component (or just a local `const attachments = ...` JSX). Same pattern
   the rest of the file already follows for the body div, so it’s a small
   tidy. Not a blocker.

4. **Concurrent file writes use `Promise` serially.** `for (const file of
   files) { await storeAttachment(...) }` — fine semantically, but with
   `MAX_FILES = 10` and 8MB each you could parallelize with
   `Promise.all(files.map(...))` if upload latency ever matters. Optional.

5. **Client `<img>` `key={att.id}` is duplicated across the two branches**
   — fine since they don’t coexist, but if the `AttachmentList` extraction
   happens (suggestion 3), that lands for free.

6. **No WS broadcast verification.** I didn’t see test coverage for the
   `dispatcher?.messageCreate(message)` path including attachments — just
   make sure the Message object that gets dispatched still carries the
   `attachments` array so other connected clients see images live. Looks
   correct from reading the code (the same `message` object is used), but a
   test or manual check before merge is worth a minute.

7. **Migration test version bumps.** `migration.test.ts` was updated to
   `17` everywhere it asserts. The describe block on line 391 still says
   `"V2→V3 migration (UUID→Snowflake)"` and the comment claims
   `"Version should be 3"`. Pre-existing drift, but you’re editing the test
   anyway — fix the comment while you’re there.

8. **`messages.ts` `parseBody({ all: true })` returns `string | File |
   (string|File)[]` for repeated keys.** The current code expects each
   `files[i]` to be a single `File`. With `all: true`, if the client ever
   sends `files[0]` twice, the value becomes an array and the
   `instanceof File` check skips both entries silently. Either set
   `all: false` (since you’re using indexed keys anyway), or handle the
   array branch. Edge-y, but worth a one-liner.

9. **`fileLoader` / cache-control.** `Cache-Control: public, max-age=...,
   immutable` is correct for content-addressed-style URLs. Just make sure
   `attId` is never reused (snowflake ids are time-monotonic, so this is
   fine).

---

## Verdict

**⚠️ Needs Changes — one blocker (Issue A: attachment URL won’t resolve via
Vite dev / cross-origin prod).** Everything else can ship as suggestions /
follow-ups for personal scope.

R2 fixes all hold up under inspection — clean work on auth + path-traversal
+ memory leak. Once Issue A is addressed (mount under `/api` is the lowest-
friction option), this is ✅ Ready.

— 🌠 Nova
