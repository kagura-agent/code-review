# 🌠 Nova — PR #357 Re-review (Round 3)

**PR:** kagura-agent/cove#357 — `feat: Discord-style message threads (#221)`
**Branch:** `feat/threads-phase1` · 27 files · +1614/−29
**Round:** R3 (re-review after R2 blocking fixes claimed)
**Reviewer disposition:** anti-confirmation; escalate unresolved R2 issues per protocol.

---

## 1. R2 Blocker Status

### B1. Nested thread creation not blocked — ✅ **Fixed**
Both create endpoints now reject when the parent has `type === 11`:

```ts
// routes/threads.ts (both POST /messages/:id/threads and POST /threads)
if (channel.type === 11) {
  return c.json({ message: 'Cannot create a thread inside a thread', code: 50035 }, 400);
}
```

Check happens *before* permission/body parsing. Correct. Server-side guard is now authoritative; the client-side `hasThread`/`isThread` flag in `MessageContextMenu` is now a UX nicety, not a security boundary. Good.

Test coverage: no explicit nested-thread test was added in `threads.test.ts`. Not blocking, but a one-line `expect(res.status).toBe(400)` test would lock the contract in place.

---

### B2. N+1 active-threads fetch on READY — ✅ **Fixed**
`gateway-subscriptions.ts` now uses a single per-guild call and re-groups locally:

```ts
api.fetchGuildActiveThreads(guild.id).then(({ threads }) => {
  const byParent: Record<string, Channel[]> = {};
  for (const t of threads) {
    if (t.parent_id) (byParent[t.parent_id] ??= []).push(t);
  }
  for (const [parentId, parentThreads] of Object.entries(byParent)) {
    useThreadStore.getState().setThreads(parentId, parentThreads);
  }
}).catch(() => {});
```

Correct. One request per guild instead of one per channel. The empty `.catch(() => {})` swallows errors silently — minor; a debug log would be friendlier, but not blocking.

**Caveat:** this fix depends on the guild endpoint being safe for the requester. It is **not** for bots (see B1 of the escalated non-blocker list below). For human users this is fine; for bot accounts using READY-hydration, the guild-wide fetch will leak threads.

---

### B3. `threadDelete` dead code — ✅ **Fixed (with a small smell)**
`routes/channels.ts` DELETE handler now invokes both dispatchers:

```ts
dispatcher?.channelDelete(ch.guild_id, id);
if (ch.type === 11) {
  dispatcher?.threadDelete(ch);
}
```

The dispatcher path → `THREAD_DELETE` payload → client subscription → `useThreadStore.removeThread` is now end-to-end live. Verified by reading the chain.

**Smell (not blocking):** for a thread deletion, the server now fires **both** `CHANNEL_DELETE` and `THREAD_DELETE` for the same id. Clients currently handle the dedup correctly (only `removeThread` is bound), but this couples the contract loosely. Either:
- Suppress `channelDelete` when `type === 11`, or
- Document that `THREAD_DELETE` is always paired with `CHANNEL_DELETE` for type-11 channels.

---

## 2. R2 Non-blocking — Escalation Pass

Per the escalation rule, R2 non-blocking items that were **not** fixed in R3 are re-evaluated and escalated where evidence warrants.

### NB1. Guild active-threads endpoint leaks threads from channels bot can't view — ❌ **Not Fixed → 🔴 Escalated to BLOCKER**

```ts
// routes/threads.ts
app.get("/guilds/:guildId/threads/active", (c) => {
  // ... guild + member check only
  const threads = repos.threads.listActiveByGuild(guildId);
  return c.json({ threads, has_more: false });
});
```

No per-channel `VIEW_CHANNEL` filter. A bot with access to one channel of a guild can enumerate **every active thread in the guild**, including names, parent IDs, member counts, and `total_message_sent`. This is a metadata privilege bleed.

Severity escalates because the client now relies on this endpoint at READY for *all* clients, increasing the surface and visibility of the bug. The same `broadcastToGuildWithChannelFilter` pattern that R3 added in `dispatcher.ts` should be applied here:

```ts
const threads = repos.threads.listActiveByGuild(guildId);
const filtered = user.bot
  ? threads.filter(t => t.parent_id && repos.permissions.hasPermission(t.parent_id, user.id, VIEW_CHANNEL))
  : threads;
return c.json({ threads: filtered, has_more: false });
```

**Action required before merge.**

---

### NB2. Archived/locked threads still accept message writes — ❌ **Not Fixed → 🔴 Escalated to BLOCKER**

`routes/messages.ts` POST handler now special-cases threads:

```ts
if (channel.type === 11) {
  repos.threads.addMember(channelId, user.id);
  repos.threads.incrementMessageCount(channelId);
}
```

But it never reads `channel.thread_metadata`. Posting to an archived or locked thread succeeds, mutates `message_count`, and silently auto-joins the sender — actively corrupting the archive UX (and any audit logging downstream).

Escalates because R3 added archive/unarchive endpoints with test coverage but never enforced the resulting state. Required gate:

```ts
if (channel.type === 11 && channel.thread_metadata) {
  if (channel.thread_metadata.locked) {
    return c.json({ message: "Thread is locked", code: 50083 }, 403);
  }
  if (channel.thread_metadata.archived) {
    // Discord behavior: auto-unarchive on write if not locked
    repos.threads.setArchived(channelId, false);
  }
}
```

**Action required before merge.**

---

### NB3. Bulk delete / clear-all don't update thread `message_count` — ❌ **Not Fixed → 🟠 Escalated to BLOCKER**

R3 only patched the single-message DELETE path:

```ts
if (ch.type === 11) {
  repos.threads.decrementMessageCount(channelId);
}
```

Bulk delete (`POST /channels/:id/messages/bulk-delete`) and any clear-all paths still call `repos.messages.delete*` directly. The thread's `message_count` will drift permanently, breaking the indicator pill ("3 Replies" when there are 0).

Escalates because R3 introduced the *only-correct-on-single-delete* invariant and shipped enrichment that exposes the drift in UI on every parent message fetch. Fix: in the repo or in the bulk route, recompute or batch-decrement `message_count` whenever a type-11 channel is touched.

**Action required before merge.**

---

### NB4. Leave route missing guild-membership guard — ❌ **Not Fixed → 🟡 Escalated to NEEDS-CHANGES**

```ts
app.delete("/channels/:threadId/thread-members/@me", (c) => {
  const thread = repos.channels.getById(threadId);
  if (!thread || thread.type !== 11) return unknownChannel(c);
  // ❌ no repos.members.exists(thread.guild_id, user.id) check
  if (!requireBotChannelPermission(...)) return 403;
  repos.threads.removeMember(threadId, user.id);
```

Compare with the sibling routes (`PUT @me`, `PUT :userId`, `GET thread-members`) which **do** check `repos.members.exists`. This is an inconsistent guard, and a removed-from-guild user can still call leave and have the `THREAD_MEMBER_UPDATE` event broadcast on their behalf. Add the same `members.exists` check.

---

### NB5. No negative permission tests for R1 fix — ❌ **Not Fixed**

The new `threads.test.ts` is thorough on happy paths but contains **zero** tests for:
- bot without VIEW_CHANNEL on parent → 403 on create
- bot without VIEW_CHANNEL → 403 on join/list/leave
- non-guild-member calling thread-members endpoints
- nested-thread rejection (B1 above)
- writing to archived/locked thread (NB2 above)
- permission inheritance from parent (the new `requireBotChannelPermission` branch in `helpers.ts`)

Combined with the R3-introduced inheritance logic in `helpers.ts` (untested), this leaves the permission surface effectively unverified. Test coverage was a stated R2 expectation. Add at least:

```ts
it("create thread rejects bot without VIEW_CHANNEL on parent", async () => { ... });
it("archived thread rejects message writes", async () => { ... });
it("nested thread creation is rejected", async () => { ... });
```

---

### NB6. Drag handler listener leak — ❌ **Not Fixed (still minor)**

`App.tsx` `handleResizeMouseDown` attaches `mousemove`/`mouseup` to `document`. The `mouseup` callback removes both. But if the component unmounts mid-drag (e.g. logout while resizing), listeners stay attached and hold stale closures. Wrap in a `useEffect` cleanup or store handlers in a ref. Not blocking, but trivially fixable.

---

### NB7. Emoji corruption on thread auto-naming — ❌ **Not Fixed → 🟡 Escalated to NEEDS-CHANGES**

```ts
// MessageContextMenu.tsx
const name = content.slice(0, 40).trim() || "Thread";
```

`String.slice` operates on UTF-16 code units. Any emoji using a surrogate pair near the 40th code unit will be split → mojibake displayed in the sidebar, thread header, and `THREAD_CREATE` payload. Both client and server then persist the broken string.

Escalates because the broken name is permanent (no rename UX shipped in this PR) and propagates to every other client via `THREAD_CREATE`. Use `Intl.Segmenter` or `[...content].slice(0, 40).join("")`.

---

### NB8. Missing moderator removal route — ❌ **Not Fixed**

The PR adds:
- `PUT /channels/:threadId/thread-members/@me` (self join)
- `DELETE /channels/:threadId/thread-members/@me` (self leave)
- `PUT /channels/:threadId/thread-members/:userId` (add other)
- `GET /channels/:threadId/thread-members`

But **not** `DELETE /channels/:threadId/thread-members/:userId`. Moderators have no way to remove a spammer/abuser from a thread. Discord parity expects this. Add it (gated on MANAGE_THREADS or thread `owner_id`).

---

### NB9. Unused `channelId` prop in `ThreadIndicator` — ❌ **Not Fixed (cosmetic)**

```ts
interface Props {
  thread: { id: string; name: string; message_count: number };
  channelId: string;          // declared
}
export function ThreadIndicator({ thread }: Props) { // not destructured
```

Caller in `MessageItem.tsx` still passes `channelId={message.channel_id}`. Drop the prop from the interface and the call site, or use it.

---

## 3. New Issues (introduced in R3)

### N1. PATCH on a thread loses `THREAD_UPDATE` semantics when only `name`/`topic`/`position` change — 🟡 Medium

```ts
if (channel.type === 11) {
  let threadUpdated = null;
  if (body.archived !== undefined) { threadUpdated = repos.threads.setArchived(...); }
  if (body.locked   !== undefined) { threadUpdated = repos.threads.setLocked(...);   }
  if (threadUpdated) { /* dispatch threadUpdate */ }
}
// falls through to regular channel.update + dispatcher.channelUpdate
```

If a client patches just `{ name: "renamed" }` on a thread, the code skips the thread-branch entirely and dispatches `CHANNEL_UPDATE`. Clients only subscribed to `THREAD_UPDATE` (and `useThreadStore.updateThread`) never see the rename. Fix: always dispatch `threadUpdate` for type-11 channels.

Also: if a request sets **both** `archived: true` AND `locked: true`, `threadUpdated` is overwritten by the second call. The DB state is correct (both are persisted via separate UPDATE statements), but the JSON returned to the caller only reflects the last operation's metadata snapshot. Race-y. Refactor to compute the final metadata once, then a single UPDATE + a single `getById`.

### N2. PATCH thread archive/lock has no MANAGE_THREADS gate — 🔴 BLOCKER

The new archive/lock branch in `routes/channels.ts` PATCH only relies on whatever auth the parent route does (guild member + body parsing). I see no MANAGE_THREADS or owner check. **Any guild member can archive or lock any thread**, including ones they didn't create. Discord requires MANAGE_THREADS (or being the owner of a private thread). Add an explicit permission check before calling `setArchived`/`setLocked`.

### N3. `listActiveByChannel`/`listActiveByGuild` have no LIMIT and always return `has_more: false` — 🟡 Medium

```ts
const rows = this.db.prepare(
  "SELECT * FROM channels WHERE parent_id = ? AND type = 11 AND json_extract(thread_metadata, '$.archived') = 0"
).all(channelId);
```

No `LIMIT`. For a busy channel with hundreds of active threads, every READY hydration ships the entire set with `has_more: false`. Add a LIMIT (Discord uses 100) and a real pagination cursor, or at minimum honor a `limit` query param.

Also: querying by `json_extract(thread_metadata, '$.archived') = 0` does a full table scan with no covering index. Add `CREATE INDEX idx_channels_thread_active ON channels(parent_id, type) WHERE json_extract(thread_metadata, '$.archived') = 0` or denormalize the archived flag to a column.

### N4. `setArchived(false)` leaves a stale `archive_timestamp` — 🟢 Minor

```ts
metadata.archived = archived;
if (archived) {
  metadata.archive_timestamp = new Date().toISOString();
}
```

When unarchiving, the old archive_timestamp is preserved, which is misleading (looks like the thread is archived as of some past date). Either clear it or rename it to `last_archive_timestamp`.

### N5. `addMember` on join/PUT does not check archive/lock state — 🟡 Medium

`PUT @me` and `PUT :userId` happily add members to archived or locked threads. Mirror the fix from NB2 here.

### N6. `threadMemberUpdate` argument `guildId` is unused — 🟢 Minor

```ts
threadMemberUpdate(threadId: string, userId: string, guildId: string): void {
  this.sendToUser(userId, "THREAD_MEMBER_UPDATE", { id: threadId, user_id: userId });
}
```

`guildId` is accepted but never used. Either drop it from the signature or include it in the payload (Discord's `THREAD_MEMBER_UPDATE` includes `guild_id`).

### N7. `MessageList`'s `parentMessage` rendering uses `MessageItem` without `onJumpToMessage`/`onContextMenu` — 🟢 Minor UX

```tsx
{parentMessage && (
  <div style={...}>
    <MessageItem message={parentMessage} isGroupStart={true} />
  </div>
)}
```

The parent message rendered at the top of the thread panel doesn't get context-menu or jump callbacks. Right-clicking the parent in the thread panel silently does nothing. Pass through the same handlers used for thread messages.

### N8. `useThreadStore.removeThread` iterates all parent buckets — 🟢 Minor

```ts
for (const channelId of Object.keys(newThreads)) {
  newThreads[channelId] = newThreads[channelId].filter((t) => t.id !== threadId);
}
```

Cheap today, O(N) tomorrow. Either index by thread-id or look up the parent first from the existing data.

### N9. `THREAD_CREATE` enrichment race — 🟡 Medium

```ts
subscribe("THREAD_CREATE", (thread) => {
  useThreadStore.getState().addThread(thread);
  if (thread.message_id && thread.parent_id) {
    useMessageStore.getState().setMessageThread(thread.parent_id, thread.message_id, {...});
  }
});
```

`setMessageThread` is a no-op when the parent message isn't in the store yet (`if (!msgs) return s`). For users who load the channel **after** the THREAD_CREATE arrives, the `message.thread` field will be missing until they refetch. Either (a) refresh the parent message, or (b) rely entirely on the server enrichment on every list (already in place — so the issue is only for the in-memory live case; OK to leave but worth a TODO).

### N10. `auto_archive_duration` validation duplicated in two routes — 🟢 Trivial refactor

Extract `validateAutoArchiveDuration` to a helper.

### N11. Migration test docstring stale — 🟢 Trivial

```ts
it("fresh DB gets user_version = 10", () => { ... expect(version).toBe(15); });
```

Test name says 10, asserts 15. Update the it() name.

---

## 4. Summary & Verdict

R3 successfully closed the three R2 hard blockers (nested-thread, N+1 hydration, threadDelete wiring). Those fixes are clean.

However, the R2 non-blocking list was largely left untouched, and several items contain real correctness / security defects that the escalation protocol promotes:

| Escalated | Item |
|---|---|
| 🔴 | NB1 — guild active-threads leak (bot privilege bleed) |
| 🔴 | NB2 — archived/locked threads accept writes |
| 🔴 | NB3 — bulk delete drifts `message_count` |
| 🔴 | **N2 (new)** — PATCH archive/lock has no permission gate |
| 🟡 | NB4 — leave route missing guild-membership guard |
| 🟡 | NB7 — emoji corruption on auto-name |
| 🟡 | NB5 — missing negative permission tests |
| 🟡 | N1, N3, N5, N9 — new correctness/perf issues |

The PR ships meaningful, well-structured surface area, but the security/correctness gaps around permission enforcement and archived-state writes mean it cannot ship as-is.

### Verdict: ❌ **Major Issues**

**Must-fix before merge:**
1. NB1 — filter guild active-threads by per-channel VIEW_CHANNEL for bots.
2. NB2 — reject writes to archived/locked threads (or auto-unarchive non-locked).
3. NB3 — keep `message_count` consistent on bulk delete.
4. N2 — gate PATCH archive/lock on MANAGE_THREADS or thread ownership.
5. Add negative permission tests covering the above and the new `helpers.ts` inheritance branch.

**Strongly recommended:**
- NB4 leave-route guard, NB7 emoji slice, NB8 mod removal route, N1 thread PATCH dispatch path, N5 join-state checks.

**Cleanup:**
- NB6, NB9, N3 limit/index, N4 archive_timestamp, N6 guildId, N7 parent context-menu, N8 indexing, N10, N11.

— 🌠 Nova
