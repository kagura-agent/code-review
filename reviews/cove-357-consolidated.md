# PR #357 Consolidated Review — feat: Discord-style message threads (#221)

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Verdict:** ⚠️ Needs Changes (3/3)

---

## Consensus Critical Issues (2+ reviewers agree)

### 1. Missing `requireBotChannelPermission` on thread-member routes (Stella, Nova)
**Confidence: High**

The four thread-member endpoints only check guild membership, not parent channel permissions:
- `PUT /channels/:threadId/thread-members/@me` (join)
- `DELETE /channels/:threadId/thread-members/@me` (leave)
- `PUT /channels/:threadId/thread-members/:userId` (add)
- `GET /channels/:threadId/thread-members` (list)

A bot without `VIEW_CHANNEL` on the parent channel can join, list members of, and add others to threads under that channel. The permission inheritance helper was correctly added to `helpers.ts` but not wired into these routes. The guild-level `/threads/active` listing also returns all threads without filtering by parent channel permission.

### 2. No tests for new security/auth surface (Stella, Nova, Vega)
**Confidence: High**

7 new server routes with auth/permission behavior, new repo with state mutations, and migration v15 — none have dedicated tests. Per review standard: security/auth paths without tests = Critical.

Minimum coverage needed:
- Bot without VIEW_CHANNEL on parent → 403 on create/join/list
- Duplicate thread-from-message → 400 (code 160004)
- message_count increments on send, decrements on delete
- Auto-add owner as member on create

### 3. Missing input validation on `auto_archive_duration` (Stella, Nova, Vega)
**Confidence: High**

Both create routes accept `auto_archive_duration?: number` but never validate it. A string/object/negative/NaN value can be persisted into `thread_metadata` JSON. Should use `validateFiniteNumber` plus range checks.

### 4. Parent message thread indicator state sync (Stella, Nova)
**Confidence: High**

After creating a thread, the parent message shows no indicator until refetch. The server only enriches `message.thread` on GET — no `MESSAGE_UPDATE` or `THREAD_UPDATE` is dispatched on create or reply count changes. Reply counts and indicators remain stale. `THREAD_MEMBER_UPDATE` also only goes to the joining user, so other clients never see member count changes.

---

## Per-Reviewer Unique Findings

### 🌟 Stella
- Thread creation should validate parent channel type (prevent nested threads or threads under type=11)
- `thread_members.join_timestamp` schema declares INTEGER but repo writes ISO string — inconsistent
- READY handler fetches active threads per-channel in a loop (N+1)

### 🌠 Nova
- `PATCH archived/locked` on thread without metadata silently falls through to regular channel update (should 400/409)
- `MessageContextMenu.handleCreateThread` truncates name to 40 chars while server allows 100
- `ThreadIndicator.tsx` accepts `channelId` prop but never uses it
- Resize drag handler attaches listeners to `document` without React cleanup — potential leak on unmount
- `repos/threads.ts setArchived/setLocked` read-modify-write not wrapped in transaction
- `useThreadStore.setThreads` only called when `threads.length > 0` — stale store after last thread deleted
- `Sidebar.tsx` channel filter runs every render — should memoize
- `dispatcher.ts threadMemberUpdate` accepts unused `guildId` parameter

### 💫 Vega
- `PATCH /channels/:id` for archive/lock/rename: if guarded by global `MANAGE_CHANNELS`, regular users can't manage their own threads
- No `DELETE /channels/:threadId/thread-members/:userId` for moderator removal
- `json_extract(thread_metadata, '$.archived')` in queries forces JSON parse per row — consider indexed column if volume grows

---

## Verdict

**⚠️ Needs Changes** — unanimous across all three reviewers.

**Blocking:**
1. Wire `requireBotChannelPermission` into the four thread-member routes + filter guild-level thread listing
2. Add integration tests for permission boundaries and core thread operations
3. Validate `auto_archive_duration` input

**Strongly recommended:**
4. Fix thread indicator state sync (parent message update on create/reply)

Everything else is polish. The architecture is solid and the scope discipline is excellent.
