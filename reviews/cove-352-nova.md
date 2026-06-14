# 🌠 Nova — Review of PR #352 (kagura-agent/cove)

**feat: channel file space with cove.md convention (closes #344)**
+1121 / −13 across 16 files

---

## 1. Summary

Solid, well-scoped first cut of channel-level file storage. The V14 schema, repo, REST routes, sidebar UI, and `cove.md` plugin injection all hang together cleanly, and the test suite is unusually thorough for a new feature (CRUD, auth, non-member, filename regex, exact-boundary size, content_type). The main substantive concerns are (a) the routes use `requireGuildMember` only and skip the channel-level `requireBotChannelPermission(VIEW_CHANNEL)` check that every other channel route applies — this can leak channel files to bots that have been denied the channel via permission overwrites; (b) `cove.md` is fetched over HTTP on every dispatch with no cache, doubling per-message hot-path latency; (c) a handful of tighter input/UX caps would harden the surface. Nothing blocking once the permission gap is fixed.

**Rating: ⚠️ Needs Changes** (one auth-class issue; the rest are non-blocking)

---

## 2. Critical Issues

### C1. Channel-files routes skip `requireBotChannelPermission(VIEW_CHANNEL)` — bots bypass channel overwrites
**File:** `packages/server/src/routes/channel-files.ts` (all 4 handlers)

All other channel-scoped routes (e.g. `packages/server/src/routes/channels.ts`) gate access with the pair:

```ts
const channel = requireGuildMember(repos, id, user.id);
if (!channel) return unknownChannel(c);
if (!requireBotChannelPermission(repos, id, user.id, user.bot)) {
  return unknownChannel(c); // or 403
}
```

`channel-files.ts` only calls `requireGuildMember`. That means a bot user that is a guild member but has been denied `VIEW_CHANNEL` for a particular channel via `channel_permission_overwrites` can still:
- list every file in that channel,
- read `cove.md` (which is supposed to be the bot-context file for that channel, and may carry private channel instructions),
- create / overwrite / delete arbitrary files in that channel.

Given that `cove.md` is explicitly designed to be **auto-injected into the LLM prompt**, this is the file most worth gating; a denied-channel bot reading or overwriting another channel's `cove.md` is a meaningful information-leak / prompt-injection surface. Recommend mirroring the pattern in `channels.ts` for all four handlers and adding a regression test (bot member of guild, overwrite denies `VIEW_CHANNEL`, expect 404/403 on every files endpoint).

### C2. No test coverage for the permission boundary above
**File:** `packages/server/src/__tests__/channel-files.test.ts`

Tests cover unauth, non-member, and human-admin paths but never the `bot: 1` + overwrite-deny case. Per the review checklist, "Security/auth paths without tests = Critical." Add at minimum:
- bot member with `VIEW_CHANNEL` deny overwrite → GET list / GET file / PUT / DELETE all blocked.
- (Once C1 fixed) bot member with `VIEW_CHANNEL` allow → succeeds.

---

## 3. Product Impact

- **Every dispatched message now performs an extra HTTP request** (`getChannelFile(channelId, 'cove.md')`) before the bot runtime starts — `packages/plugin/src/dispatch.ts:266-272`. Even on 404 / network error this adds a full round-trip to every inbound message, on the hot path, before typing-indicator-driven UX kicks in. For a busy channel this is a measurable regression. Two easy mitigations:
  1. Cache `cove.md` per `channelId` with a short TTL (e.g. 30s) and bust on PUT/DELETE via a WS event (see P1 below).
  2. Or piggyback on an existing channel-fetch the dispatcher already performs.
- **No realtime updates.** Editing or deleting `cove.md` (or any file) in one client won't reflect in other open clients — they'll only see changes after re-opening the sidebar. The store already refetches after local mutations but there is no dispatcher emission. Consider a `CHANNEL_FILE_UPDATE` / `CHANNEL_FILE_DELETE` event so other clients and *currently-running bot dispatchers* see new `cove.md` content immediately. Lack of this is also why C1 + a "bot resets its own cove.md" oversight could go unnoticed.
- **Asymmetric size cap between server and plugin injection.** Server caps `cove.md` at 100 KB (`MAX_CONTENT_SIZE`), but plugin only injects if `coveMd.content.length <= 8000` (chars, not bytes). Anything between ~8 KB and 100 KB is silently *stored but never injected* — users will edit `cove.md`, see it saved, and wonder why the bot ignores it. Either document the 8 KB cap in the UI (badge / inline warning when content > 8000 chars), or — preferable — surface a server-side `INJECTION_LIMIT` constant shared by both sides so the UI can render an authoritative warning.
- **`cove.md` as a magic filename is implicit, not surfaced in the UI** beyond the pin icon's tooltip ("Auto-injected into bot context"). A first-time user pinning a file named `cove.md` won't realise it ends up in every bot prompt. Consider an inline help blurb at the top of the sidebar or a dedicated "Create cove.md" call-to-action when absent.

---

## 4. Suggestions (non-blocking)

### Server

- **S1.** `packages/server/src/routes/channel-files.ts:55-58` — `body.content_type` accepted as any string, no length cap and no allowlist. It's stored verbatim and returned to clients. Cap to e.g. 100 chars and consider validating against a small whitelist (`text/plain`, `text/markdown`, `application/json`, …) or matching `^[\w.+-]+/[\w.+-]+$`. Otherwise a malicious member can stuff arbitrary payloads into the `content_type` column.
- **S2.** `packages/server/src/repos/channel-files.ts:38-66` — the upsert does a separate `SELECT created_at` and then an `INSERT … ON CONFLICT DO UPDATE`. The conflict branch uses `excluded.*` for everything except `created_at`, which is already preserved by `INSERT`'s value of `createdAt` derived from the prior SELECT. Cleaner and race-free single-statement form:
  ```sql
  INSERT INTO channel_files (...) VALUES (?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(channel_id, filename) DO UPDATE SET
    content = excluded.content,
    content_type = excluded.content_type,
    size = excluded.size,
    updated_at = excluded.updated_at
  -- created_at is preserved by ON CONFLICT
  ```
  i.e. drop the prior SELECT entirely; pass `now` for `created_at` on insert and the existing value is kept on update because no `created_at` clause is in the SET. Saves one round-trip and removes the read-then-write race window.
- **S3.** `packages/server/src/routes/channel-files.ts:53-54` — `upsert` returning `null` for oversize is now unreachable (route pre-checks size). Either remove the secondary check in the repo or remove the pre-check in the route. Pick one source of truth.
- **S4.** Migration `v14-channel-files.ts` defines the FK with `ON DELETE CASCADE` but the test in `migration.test.ts` doesn't verify it. Worth a quick test that creates files, deletes the parent channel, and asserts rows are gone — both to confirm cascade fires (depends on `PRAGMA foreign_keys=ON` being set in `initDb`) and to lock in the contract.
- **S5.** No `updated_at` index — fine at current scale, but if a future feature needs "recently edited" lists you'll want `CREATE INDEX channel_files_updated_at ON channel_files(channel_id, updated_at DESC)`.
- **S6.** Filename regex `/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$/` rejects leading underscore (`_template.md`) and any Unicode. Probably intentional, but worth documenting in the route comment so future contributors don't loosen it accidentally; "must start with `[a-zA-Z0-9]`" also subtly excludes dotfiles, which the tests assert.

### Plugin

- **P1.** `packages/plugin/src/rest-client.ts:179-184` — `getChannelFile` catches *all* errors (including 5xx and network failures) and returns `null`. Combined with the `try { … } catch {}` in dispatch, an outage of the files endpoint is silent and indistinguishable from "no cove.md." Log at debug level so operators can tell the difference; also consider a 1–2s timeout so a hung server doesn't stall dispatch.
- **P2.** `packages/plugin/src/dispatch.ts:265-272` — `coveMd.content.length <= 8000` checks UTF-16 code units, not bytes. For ASCII this is fine, but a CJK-heavy `cove.md` of 8000 chars is ~24 KB, which may overflow downstream model context budgets that count tokens against an assumed byte budget. Prefer `Buffer.byteLength(coveMd.content, 'utf8') <= 8000` (or measure in tokens).

### Client

- **U1.** `packages/client/src/components/FilesSidebar.tsx:189-197` — `handleCreateFile` calls `handleFileClick(name)` immediately after `saveFile`. `saveFile` already refreshes both `files` and (conditionally) `fileContent`, then `handleFileClick` triggers another `fetchFile`. That's two GETs for the same file on every create. Either drop the post-create `handleFileClick` (and just call `selectFile(name)`), or have `saveFile` not auto-refetch when the next action is going to fetch anyway.
- **U2.** `useChannelFilesStore.ts:60-75` — the store keeps `selectedFile`/`fileContent` across `channelId` switches. `fetchFiles` reloads the list, but if the user had `cove.md` open in channel A and switches to channel B (also containing `cove.md`), they'll briefly see channel A's contents until the new fetch resolves. Reset `selectedFile`/`fileContent` whenever `fetchFiles` is called with a new `channelId`, or scope state by channel.
- **U3.** `FilesSidebar.tsx:115-118` — `useEffect` only depends on `channelId`/`fetchFiles`. Re-opening the sidebar without a channel change does *not* refetch, so a file added by another client won't appear until the user switches channels. Consider refetching on `filesOpen` transition to `true`, or — better — driving the list via the WS event proposed in §3.
- **U4.** Inline editor uses `autoSize={{ minRows: 8, maxRows: 24 }}` with a 100 KB cap. Very large files will paginate the entire app awkwardly. Either swap to a fixed-height textarea with internal scroll, or render the editor in a modal for files over some threshold.
- **U5.** `FilesSidebar.tsx:184-187` — after `handleDelete` succeeds the store nulls `selectedFile`, which causes the sidebar to flip back to the list. Good. But the `Popconfirm` triggers `handleDelete` which is async and not awaited inside `onConfirm`; ant-d will close the popover immediately and any thrown error is swallowed in the catch-less `await`. Wrap in try/catch and surface a `message.error` toast on failure (especially relevant once C1 is fixed and PUT/DELETE can legitimately return 403).
- **U6.** `App.tsx:277-291` — the "open one sidebar at a time" toggling is correct but duplicated across two handlers. A reducer (`setActiveRightPane('members' | 'files' | null)`) would prevent future toggles drifting out of sync.

### Tests

- **T1.** Add the bot+overwrite test described in C2.
- **T2.** Add a test that PUT preserves `created_at` *and* the `content_type` column is updated when re-PUT with a different `content_type` (current "updates a file with PUT" only checks `content`).
- **T3.** Confirm `DELETE FROM channels WHERE id = ?` cascades to `channel_files` (S4 above).
- **T4.** Negative content-type test once S1 is in.

---

## 5. Positive Notes

- **Test suite is genuinely good** — 347 lines covering CRUD, listing semantics, auth (Bearer + Bot), non-member, exact-boundary size, edge-case filenames including URL-encoded path traversal. This is the right level of paranoia for a new user-input surface.
- **`cove.md`-first ordering at the SQL level** (`CASE WHEN filename = 'cove.md' THEN 0 ELSE 1 END, filename ASC`) is the right place to enforce the convention — no client/server drift possible.
- **Composite PK + CASCADE FK** on `(channel_id, filename)` is exactly the schema this needs; no separate id column or surrogate join required.
- **Plugin integration is appropriately defensive** — `extraContext` only includes `ChannelContext` when `coveMd` is present (`...(coveMdContent ? { ChannelContext: coveMdContent } : {})`), so existing dispatch payload shape is unchanged for channels without a `cove.md`.
- **Filename regex pinned in code + reflected in the error message** — debuggable.
- **UI clearly distinguishes list vs detail view** and pins `cove.md` with a tooltip explaining the auto-injection. Discoverability of the magic filename is partly addressed.
- **Migration is minimal and idempotent** (`CREATE TABLE IF NOT EXISTS`), and the migration version test was updated everywhere it asserts `user_version`.

---

**Bottom line:** Fix C1 (+ regression test C2), and this is mergeable. S1/S2 are easy hardening wins worth doing in the same PR. The performance / freshness items (P1, U3, §3 caching) can land as a follow-up but are worth filing issues for before merge.

**File path:** `~/.openclaw/workspace/code-review/reviews/cove-352-nova.md`
