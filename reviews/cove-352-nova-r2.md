# 🌠 Nova — Round 2 Re-Review of PR #352 (kagura-agent/cove)

**feat: channel file space with cove.md convention (closes #344)**
+1248 / −13 across 16 files

---

## 1. R1 Issue Status

### 🔴 Critical (R1)

| ID | Issue | R2 Status | Evidence |
|----|-------|-----------|----------|
| **C1** | Channel-files routes skip `requireBotChannelPermission(VIEW_CHANNEL)` | ✅ **Fixed** | All 4 handlers in `packages/server/src/routes/channel-files.ts` (GET list, GET file, PUT, DELETE) now run `requireGuildMember` *and* `requireBotChannelPermission(repos, channelId, user.id, user.bot)`, returning `{ message: "Missing Permissions", code: 50013 }` with status `403` on denial. `helpers.ts:requireBotChannelPermission` correctly returns `true` for non-bots and otherwise checks the `VIEW_CHANNEL` bit (`1n << 10n`). |
| **C2** | No permission-boundary tests | ✅ **Fixed** | `channel-files.test.ts` adds *two* new describe-blocks: `"Bot with VIEW_CHANNEL denied"` (4 tests: list/get/create/delete all `403`) and `"Bot with VIEW_CHANNEL granted"` (2 tests: list `200`, create+read round-trip `200`). 6 new tests total — matches R2 fix claim. |

Both criticals are properly resolved. C1's fix uses `403 / 50013` rather than 404 mimicry; defensible and consistent with `Missing Permissions` semantics elsewhere.

### 🟡 Suggestions (R1)

| ID | Issue | R2 Status | Notes |
|----|-------|-----------|-------|
| **S1** | `content_type` no length cap / allowlist | ⚠️ **Partially Fixed** | 255-char cap added (`channel-files.ts` PUT). No MIME-shape regex / allowlist. Acceptable hardening; the original concern (unbounded write) is gone. Keep as a future nit. |
| **S2** | Upsert does separate SELECT then INSERT…ON CONFLICT (race + extra round-trip) | ❌ **Not Fixed** → **Escalated to 🟡 hardening (was nit)** | `repos/channel-files.ts:46-58` still runs `SELECT created_at` then `INSERT … ON CONFLICT DO UPDATE`. The cleaner single-statement form (omit `created_at` from the `DO UPDATE SET` clause so the existing row's value is preserved) was not adopted. Not a correctness defect at current scale (concurrent PUTs to the same `(channel_id, filename)` will both serialize through SQLite's write lock and the second `INSERT` will deterministically fall into the `DO UPDATE` branch), but the dead "read-then-write race window" rhetoric in R1 was overstated. Still worth simplifying. |
| **S3** | Oversize check duplicated (route pre-checks, repo also returns null) | ❌ **Not Fixed** | `routes/channel-files.ts:79-82` rejects with `validationError` if `Buffer.byteLength > MAX_CONTENT_SIZE`; `repos/channel-files.ts:42` *also* checks `size > MAX_FILE_SIZE` and returns `null`; the route then has `if (!file) return validationError(c, "File content exceeds 100KB limit")` (`channel-files.ts:88`). The second branch is unreachable. Pick one source of truth. Low impact — purely a tidiness issue — keep at 🟡. |
| **P1** | `getChannelFile` swallows all errors silently | ❌ **Not Fixed** | `packages/plugin/src/rest-client.ts:179-184` still does `try { … } catch { return null; }`; `packages/plugin/src/dispatch.ts:266-272` still wraps with `try { … } catch { /* ignore – cove.md is optional */ }`. A 5xx, a hung TCP connection, or a misconfigured base URL is indistinguishable from "no cove.md" on the message hot path. **Escalating to 🟠 Should-fix-before-merge** per the escalation rule: this was a 🟡 in R1 and was not addressed. Add at least a debug-level log distinguishing "no file" (404) from "error" (5xx/network); a timeout would also be wise since this now runs on every dispatch. |
| **P2** | `content.length` (UTF-16 code units) vs byte measurement | ✅ **Fixed** | `dispatch.ts:638-640` now uses `Buffer.byteLength(coveMd.content, 'utf8') <= 8000`. Matches repo / route's byte semantics. |
| **U1** | Double-fetch on create | ⚠️ **Partially Fixed (lower severity than R1 claimed)** | `FilesSidebar.tsx:handleCreateFile` still calls `saveFile(channelId, name, "")` then `handleFileClick(name)`. But on a *brand new* file, `selectedFile` at the moment of `saveFile` is `null` (we're in list view), so `saveFile`'s conditional `fetchFile` branch (`if (get().selectedFile === filename)`) does **not** fire. Net result: 1× PUT, 1× `fetchFiles` (list refresh — needed), 1× `fetchFile` (via `handleFileClick`). That's correct, not duplicate. R1's "two GETs for the same file" claim was wrong on closer reading. Downgrade to non-issue, but the UX still has a brief flash where the editor opens before content arrives — minor. |
| **U2** | Store state leaks across channel switches | ❌ **Not Fixed** | `useChannelFilesStore.ts:fetchFiles` only `set({ loading: true })` then `set({ files, loading: false })`. `selectedFile` and `fileContent` are untouched. Switching from channel A (with `cove.md` open) to channel B will momentarily render channel A's content while channel B's `fetchFile` is in flight — and if the user *only* switches channels without clicking a file in B, channel A's `fileContent` stays visible permanently in the editor view. **Escalating to 🟠**: this is a real cross-channel data-bleed in the UI. Fix: `fetchFiles` should detect `channelId` change and reset `selectedFile`/`fileContent`, or store state should be keyed by `channelId`. |
| **U3** | Sidebar doesn't refetch on reopen | ❌ **Not Fixed** | `FilesSidebar.tsx:115-118` `useEffect` still depends only on `[channelId, fetchFiles]`. Closing + reopening the sidebar without changing channels reuses stale list. Combined with the absence of WS events (deferred to #354), users have no path to see files added by other clients short of a channel switch or page reload. Keep at 🟡; deferring is reasonable given #354 exists. |

### Stella's R1 items

| Item | R2 Status | Notes |
|------|-----------|-------|
| GET/DELETE filename regex validation | ✅ **Fixed** | `FILENAME_RE.test(filename)` now runs in all four handlers (GET single, PUT, DELETE; list doesn't need a filename). Returns 400 on mismatch. |
| UI error feedback via `antd message.error` | ⚠️ **Partially Fixed** | Added on `handleSave` (line 294) and `handleCreateFile` (line 315). **Missing on `handleDelete`** (lines 300-303): no `try/catch`, no toast. Now that PUT/DELETE can legitimately 403 (post-C1 fix), a denied delete will silently fail with no user feedback. Recommend wrapping `handleDelete` symmetrically. |
| Rate-limit bucket for file writes | Unverified in this diff | Cannot see route-level rate limiting added; if it's handled by a global middleware that already governs `PUT`/`DELETE` it's fine, otherwise still open. |

### Deferred (out of scope, confirmed)

- **#353** (caching layer for `cove.md`) — filed, out of scope. ✅
- **#354** (WS events for channel-file changes) — filed, out of scope. ✅ (but see U3)

---

## 2. New Issues (introduced by R2 changes)

### N1. 🟡 `requireBotChannelPermission` 403 path leaks channel existence
**File:** `packages/server/src/routes/channel-files.ts` (all 4 handlers)

The order is: `requireGuildMember` (→ 404 if non-member or missing channel), then `requireBotChannelPermission` (→ 403 if denied). The 403 is correct for a member-bot that's been overwrite-denied, but a non-member who happens to be a guild member of *some* guild containing this channel will get 404 (good) while a denied bot gets 403 (slight existence leak vs. 404). Consistent with how the other channel routes do it per `helpers.ts`, so I'm flagging as a known design choice rather than a regression. Worth a one-line comment for future contributors.

### N2. 🟡 New tests instantiate `TestDispatcher` but channel-file mutations don't dispatch events
**File:** `packages/server/src/__tests__/channel-files.test.ts:9-13`

The `TestDispatcher` boilerplate is harmless dead infrastructure for now — channel-file routes don't emit WS events (deferred to #354). Either drop the dispatcher and pass `undefined`/a stub through `createApp`, or leave a comment noting it's a placeholder for #354. Cosmetic.

### N3. 🟡 `PermissionFlags.VIEW_CHANNEL` used as a string literal in test bodies
**File:** `packages/server/src/__tests__/channel-files.test.ts` (Bot overwrite blocks)

`body: JSON.stringify({ type: 1, allow: "0", deny: PermissionFlags.VIEW_CHANNEL })` — works because `PermissionFlags.VIEW_CHANNEL` serializes as a string in the shared package, but the inverse (`allow: PermissionFlags.VIEW_CHANNEL, deny: "0"`) silently relies on the same. Fine for now; would be nice if the shared package exposed an explicit helper to format an overwrite payload (out of scope here).

### N4. 🟢 Whitespace-only diff in `rest-client.ts:163-164`
**File:** `packages/plugin/src/rest-client.ts`

The diff collapses the doc comment opener for the prior `executeWebhook` method (`-  /**\n-   * POST …` → `+  /** POST …`). Unrelated stylistic edit in this PR; not blocking but inflates the diff.

---

## 3. Summary

R1's two criticals are properly fixed with both code and tests — C1's 403/50013 plumbing is correct, and C2 adds 6 well-targeted tests covering both deny and allow paths for bot users. P2's byte-vs-char fix is clean. S1 (content_type cap), Stella's filename regex on GET/DELETE, and UI `message.error` on save/create are all in.

What remains unaddressed:

- **🟠 P1 (escalated)**: plugin still swallows all errors silently — every inbound message pays a hidden HTTP cost and an outage of the files endpoint is invisible.
- **🟠 U2 (escalated)**: client store still leaks `fileContent`/`selectedFile` across channel switches — visible cross-channel UI bleed.
- **🟡 S2 / S3**: dead-code / non-race "race window" — purely tidiness now that C1 is fixed.
- **🟡 U3**: no reopen-refetch — partially excused by deferred #354, but a 2-line fix would close the loop.
- **🟡 Stella delete error toast**: missing `try/catch` + `message.error` on `handleDelete`; now relevant because 403 is a real outcome.

None of the remaining items are correctness defects on the auth-critical path. The escalated P1 and U2 are user-visible degradations rather than security bugs.

## 4. Verdict

**⚠️ Needs Changes (minor)**

The critical security gap is closed and covered by tests; this PR is *much* closer to mergeable than R1. Recommend one more small turnaround addressing **P1** (log + timeout), **U2** (reset store on channel change), and **Stella's delete-error toast** — these are 10–20 line fixes that prevent shipping a visible cross-channel UX bug and an invisible-failure dispatch path. S2/S3/U3 can ride along or land as follow-ups.

If the team prefers velocity, P1+U2 alone are the bar to merge; everything else is non-blocking.

**File path:** `/home/kagura/.openclaw/workspace/code-review/reviews/cove-352-nova-r2.md`
