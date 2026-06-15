# 🌠 Nova — Round 2 Review: cove PR #357 (Threads)

**Repo:** kagura-agent/cove
**PR:** #357 — Threads (server + client)
**Round:** 2
**Reviewer:** Nova

---

## 1. R1 Issues Status

### 🟥 R1 Blocking Issues

| # | Issue | Status | Evidence |
|---|-------|--------|----------|
| 1 | Thread-member routes missing `requireBotChannelPermission` | ✅ **Fixed** | `packages/server/src/routes/threads.ts` lines 137, 158, 176, 203. All four routes (PUT/DELETE @me, PUT :userId, GET) now call `requireBotChannelPermission(repos, thread.parent_id!, user.id, user.bot)`. Helper at `routes/helpers.ts:37-52` also falls back to parent for type=11 channels. Correct. |
| 2 | No tests — 7 new routes, zero coverage | ✅ **Fixed** | `packages/server/src/__tests__/threads.test.ts` adds 535 lines / ~27 specs: create-from-message, standalone create, active-list, join/leave/list members, archive/unarchive, message enrichment, message-count tracking, validation of `auto_archive_duration` and name length, idempotency, duplicate-thread rejection. Solid coverage of happy + validation paths. (See gap noted in §2.) |
| 3 | `auto_archive_duration` unvalidated | ✅ **Fixed** | `routes/threads.ts:30-34, 81-85` whitelists `[60, 1440, 4320, 10080]`. Test `fails with invalid auto_archive_duration` confirms 400. |
| 4 | Thread indicator state sync (parent message had no indicator until refetch) | ✅ **Fixed** | New `useMessageStore.setMessageThread` action + `THREAD_CREATE` subscriber in `gateway-subscriptions.ts:265-273` patches the parent message in-store immediately. Plus `MessageContextMenu.handleCreateThread` does the API write (the gateway will broadcast `THREAD_CREATE` back which the subscriber consumes — covers other tabs/users too). |

**All 4 blockers verifiably resolved. No escalation triggered.**

### 🟨 R1 Non-Blocking Suggestions — escalation review

Under the re-review protocol, **unaddressed** non-blockers are evaluated for escalation. Calling them out individually:

| Suggestion | Status | Escalated? |
|---|---|---|
| Nested thread prevention (thread inside a thread) | ❌ Not addressed — `createFromMessage` / `createStandalone` only check guild membership; nothing guards `channel.type === 11`. A user could POST `/channels/{thread_id}/threads` and create a thread whose `parent_id` is another thread. Permission inheritance then walks to a parent that is itself a thread (no overwrites) and bots get denied while humans pass. | ⚠️ **Escalated to New Issue #1** (non-blocking, but worth a guard) |
| Timestamp type mismatch (schema INTEGER vs ISO string stored) | ❌ Not addressed | minor, kept as suggestion |
| N+1 thread fetch on READY | ❌ **Made worse** — `gateway-subscriptions.ts:142-153` now fires `api.fetchActiveThreads(ch.id)` per channel inside a guild loop. Server already exposes `GET /guilds/:guildId/threads/active` (one call). | ⚠️ **Escalated to New Issue #2** — see §2 |
| Archive/lock fallthrough in `channels.ts` PATCH | ❌ Not addressed — both writes happen, but `threadUpdated` is reassigned so only one `THREAD_UPDATE` event fires when both `archived` and `locked` are sent together. State is correct, event ordering isn't. | kept as suggestion |
| Name truncation in `handleCreateThread` (`slice(0, 40)`) | ➖ Acceptable as UI default; backend still allows full 100 chars. |
| Unused `channelId` prop in `ThreadIndicator` | ❌ Not addressed — interface declares `channelId: string`, function only destructures `{ thread }`. Lint smell. | kept as suggestion |
| Drag handler global listener leak on unmount | ❌ Not addressed — `App.tsx handleResizeMouseDown` registers `mousemove`/`mouseup` on `document` but no cleanup if the component unmounts mid-drag. Edge case. | kept as suggestion |
| Transaction safety for thread create + addMember | ❌ Not addressed — `createThread` does INSERT + `addMember` (which is INSERT + UPDATE) without wrapping in a tx. If addMember throws, channel exists with member_count=0 and no actual member row. Practically unlikely with sqlite3 sync. | kept as suggestion |
| Stale-store concerns / Sidebar memoization | ❌ Not addressed — `parentChannels` filtered on every render; cheap for small N. | kept as suggestion |
| Moderator removal route (DELETE `/thread-members/:userId`) | ❌ Not addressed — PUT exists, DELETE does not. Missing symmetry. | kept as suggestion |
| `json_extract` perf on list-active | ❌ Not addressed — no index. Fine at small scale. | kept as suggestion |

---

## 2. New Issues (R2)

### ⚠️ New Issue #1 — Nested thread creation not prevented (escalated from R1 suggestion)

`routes/threads.ts` create endpoints never check the parent channel's `type`. If a client POSTs to a thread id, the server happily creates a thread whose `parent_id` references another thread. Downstream effects:
- `requireBotChannelPermission` only walks one level up (`channel.parent_id`); for nested threads that parent is itself a thread with no overwrites → bots get a hard deny instead of inheriting from the true text channel.
- `broadcastToGuildWithChannelFilter` similarly resolves perms via `parent_id` once; nested threads bypass actual access control.
- Sidebar/`threadsByParent` map keys on parent channel id, so nested threads silently vanish from UI.

**Fix:** in both `POST /channels/:channelId/messages/:messageId/threads` and `POST /channels/:channelId/threads`, reject when `channel.type === 11` with 400 ("Cannot create thread in thread", code 160006 maps cleanly to Discord's behaviour).

**Severity:** Low–Medium (correctness/security). Not blocking on its own.

---

### ⚠️ New Issue #2 — N+1 active-threads fetch on READY (escalated from R1 suggestion)

```ts
// gateway-subscriptions.ts:140-152
for (const ch of (guild.channels ?? [])) {
  if (ch.type !== 11) {
    api.fetchActiveThreads(ch.id).then(({ threads }) => { ... }).catch(() => {});
  }
}
```

For a guild with 50 channels, every gateway READY (initial connect + every reconnect) fires 50 parallel HTTP requests. The server **already** provides `GET /guilds/:guildId/threads/active` (defined in `routes/threads.ts:97-110`) which returns all threads in a single round-trip — the client just doesn't call it.

**Fix:** replace the per-channel loop with one `api.fetchActiveGuildThreads(guildId)` call and bucket by `thread.parent_id` client-side. ~10-line change.

**Severity:** Medium (performance / product impact on reconnect storms). Not blocking, but should ship before this lands on a real workspace.

---

### ⚠️ New Issue #3 — `THREAD_DELETE` is effectively dead code

Dispatcher exposes `threadDelete(thread)` (`ws/dispatcher.ts:240-247`) and a subscriber consumes it (`gateway-subscriptions.ts:279-281`), but **no route ever calls it**. Threads are deleted through the generic `DELETE /channels/:id` route which dispatches `channelDelete` instead. Result: open thread panels and sidebar entries won't react to remote deletes — clients only learn on next refetch.

**Fix:** in `routes/channels.ts` DELETE handler, if `ch.type === 11`, dispatch `threadDelete(ch)` (or call both). Alternatively wire the deletion through a dedicated thread route.

**Severity:** Low–Medium (correctness/UX). Easy fix.

---

### ⚠️ New Issue #4 — `useMessageStore` not cleaned up when thread is removed

`useThreadStore.removeThread` clears the thread from `threads` + `activeThread`, but `useMessageStore.messages[threadId]` lingers forever. Long-running sessions accumulate dead message arrays.

**Fix:** on `THREAD_DELETE` subscriber, also call `useMessageStore.getState().setMessages(threadId, [])` or add a `clearChannelMessages(channelId)` action.

**Severity:** Low (memory hygiene). Optional.

---

### 🟦 New Issue #5 — Test gap on the R1 permission fix

The new R1 permission checks (#1) have no negative test. The suite tests "creator is auto-member" and "non-thread channel → 404", but no spec asserts that a *bot user without VIEW_CHANNEL on the parent* is denied 403 on join/leave/list. Given the R1 issue was specifically about this missing check, please add at least one regression test per route to lock the behaviour.

**Severity:** Low. Should add before merge to prevent regression.

---

### 🟦 New Issue #6 — `ThreadIndicator` declares but never uses `channelId`

```ts
interface Props { thread: ...; channelId: string; }
export function ThreadIndicator({ thread }: Props) { ... }   // channelId unused
```

Lint smell; either consume it (e.g., guard `fetchAndOpen` with the channel context) or drop from the interface.

**Severity:** Trivial.

---

## 3. Fresh review of R2-only changes

- **`gateway-dispatcher.ts` (client):** thread event types match server payloads. Good.
- **`useThreadStore`:** clean, predictable. `addThread` dedupes by id ✓. `updateThread`/`removeThread` correctly sync `activeThread`. `fetchAndOpenThread` swallows errors silently — consider surfacing to user via toast in a follow-up.
- **`ThreadPanel`:** parent-message fetch falls back to API when not in store ✓. Effect deps include `activeThread?.id` + `message_id` + `parent_id` — covers thread switch correctly.
- **`MessageList`:** new `parentMessage` prop renders parent above thread messages with a divider — clean reuse, no scroll regressions visible. Suppresses the "beginning of conversation" banner when in thread mode ✓.
- **`MessageContextMenu`:** new `hasThread` prop correctly hides "Create Thread" once one exists ✓.
- **App.tsx resizer:** functional but worth noting the listener-cleanup edge case (Issue is in R1 suggestions list above).
- **Test class `TestDispatcher`:** correctly overrides every dispatcher method touched by routes; rate-limit disabled per spec.
- **Migration v15:** additive ALTER TABLE — safe with `IF NOT EXISTS` on the new `thread_members` table. Migration test bumps version assertions to 15 across all suites ✓.
- **`broadcastToGuildWithChannelFilter` perm resolution for threads:** one-level parent walk — works for direct threads, breaks for nested threads (see Issue #1).
- **`messages.ts` enrichment:** N+1 within a single list response (`getThreadForMessage` per message). For default 50-msg page that's 50 small SELECTs. Acceptable but a `LEFT JOIN` / batched IN-query would be tidier. Filing as nit only.

---

## 4. Summary & Verdict

The PR materially addresses every R1 **blocker** with both code fixes and real test coverage. The thread feature works end-to-end: creation, indicator sync via gateway, archive flow, member management, and message-count tracking are all validated by the new test suite (~27 specs across the surface area).

However:
- **Two R1 non-blocking suggestions deteriorated rather than improved** (N+1 thread fetch — now in the code, and nested-thread prevention — still absent and demonstrably exploitable). Per the re-review escalation rule, both are flagged as new R2 issues above.
- **`THREAD_DELETE` flow is broken end-to-end** — dispatcher and subscriber exist, no caller. Real UX gap.
- **No negative tests for the R1 permission fix**, which is the highest-risk regression surface in this PR.

None of the issues are catastrophic, and the design + test discipline are good. I'd ask for the two small server-side fixes (#1 nested guard, #3 wire `threadDelete`) plus the N+1 → single-call client change (#2) and a single regression test for #5 before merging.

### ⚠️ Verdict: Needs Changes (minor)

Estimated effort to address: ~30–60 min.

- 🟥 Blocking: none
- ⚠️ Needs change before merge: #1, #2, #3, #5
- 🟦 Follow-up: #4, #6, plus the open R1 suggestions still standing

**Note:** I could not execute the new test suite locally (sandbox bus error on vitest install). Suite structure looks correct; please confirm CI is green on the PR.

— 🌠 Nova
