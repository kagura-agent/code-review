# 🌠 Nova — R3 Re-Review: cove#272 (feat: emoji reactions)

**Round:** R3 (re-review of R2 findings)
**Verdict:** ✅ All R2 issues addressed. A few new minor concerns worth noting, but no blocker.
**Recommendation:** Approve with optional follow-ups.

---

## R2 Issue Status

### 🔴 R2-1 — Client count drift for other users → ✅ Fixed

Server now computes and broadcasts the absolute count after each mutation
(`packages/server/src/routes/reactions.ts`):

```ts
const added = repos.reactions.add(messageId, userId, emoji);
if (added) {
  const count = repos.reactions.getCount(messageId, emoji);
  dispatcher?.reactionAdd(..., count);
}
```

Client `addReaction` / `removeReaction` in `useMessageStore.ts` now uses the
server-sent absolute `count` instead of incrementing locally:

```ts
reactions[idx] = { ...reactions[idx], count, me: me ? true : reactions[idx].me };
```

The `me` merge logic is also correct — self-event flips `me`, other-user
event preserves existing `me`. No more drift. ✅

**Nit (not blocking):** add→getCount is two statements; another concurrent
reaction could land in between, so the broadcast `count` may briefly disagree
with reality by 1 across listeners. Low impact (the next event re-syncs), but
wrapping both in a `db.transaction(...)` or using a single
`INSERT ... RETURNING (SELECT COUNT(*) ...)` would eliminate it.

---

### 🔴 R2-2 — getUsersForReaction unbounded + N+1 → ✅ Fixed

`packages/server/src/repos/reactions.ts::getUsersForReaction` now:

- Single `JOIN` against `users` (no per-user `getById` loop).
- `limit` parameter, clamped at route layer to `1..100`, default 25.
- `after` cursor implemented with a sub-select on `created_at`.

Looks good. ✅

**Nit:** `after` sub-select runs on every page; an index on
`(message_id, emoji, created_at)` would help if reaction lists get large.
Current `idx_reactions_message_id` is enough for now.

---

### 🟡 R2-3 — LRU re-add eviction bug → ✅ Fixed

`SentMessageTracker.add` in `packages/plugin/src/channel.ts`:

```ts
if (this.ids.has(id)) {
  this.ids.delete(id); // refresh recency
} else if (this.ids.size >= this.maxSize) {
  // evict oldest only when adding a new id
  ...
}
this.ids.add(id);
```

`else if` correctly prevents eviction on re-add. ✅

---

### 🟡 R2-4 — React key collision → ✅ Fixed

`MessageItem.tsx`: `key={r.emoji.id ?? r.emoji.name}` ✅

---

### 🟡 R2-5 — Auto-scroll over-fires → ✅ Fixed (with minor caveat)

`MessageList.tsx`:

```ts
const lastMsg = messages?.[messages.length - 1];
const lastMsgReactionKey = lastMsg
  ? `${lastMsg.id}:${(lastMsg.reactions ?? []).reduce((s, r) => s + r.count, 0)}`
  : "";
useEffect(() => { ... scrollToBottom() ... }, [lastMsgReactionKey, ...]);
```

Only the last message triggers scroll. ✅ Approach is sound.

**Two minor caveats (not blocking):**

1. **Duplicate scroll on new message** — when a new message arrives,
   `lastMsg.id` changes, so both the `lastMessageContent` effect and the
   `lastMsgReactionKey` effect fire. RAF coalesces visually, but it's wasted
   work. Could gate on `lastMsg.id === prevLastMsgIdRef.current`.
2. **Count-stable layout change** — if a user swaps reactions (removes 👍,
   adds ❤️) and the totals net to the same value, the key won't change even
   though pill row layout did. Edge case. Using
   `reactions.length + ":" + sum` would catch the emoji-count delta.

---

## Fresh Findings (new code only)

### 🟡 N1 — `reactionNotifications` config has no schema / type

`packages/plugin/src/channel.ts`:

```ts
const channelSection = cfg?.channels?.["cove"] ?? {};
const reactionNotifications: "off" | "own" | "all" =
  (channelSection as any).reactionNotifications ?? "own";
```

Two issues:
- `as any` defeats config typing — typos in user config will silently fall
  back to `"own"` with no warning.
- No schema/docs entry, so users can't discover the option.

**Fix:** add `reactionNotifications` to the channel plugin's typed config
schema, drop the `as any`, and document the three values in the channel
plugin README.

### 🟡 N2 — `enqueueSystemEvent` dynamically imported per reaction

```ts
const { enqueueSystemEvent } = await import("openclaw/plugin-sdk/system-event-runtime");
```

Hoist this import to module scope. Re-importing on every reaction adds
latency and clutters logs. Cheap fix.

### 🟢 N3 — `restClient.getUser` / `getChannel` called per reaction with no cache

Each reaction triggers two REST round-trips to resolve display names. For
spammy reactions on the same message this is wasteful. A small LRU
(`username` keyed by `userId`, channel name keyed by `channelId`, TTL ~60s)
would cut traffic substantially. Non-blocking — current behavior works.

### 🟢 N4 — REST fallback in `messageReactionAdd` swallows errors silently

```ts
try { const msg = await restClient.getMessage(...); ... } catch { return; }
```

Worth a `log?.debug?.(...)` to aid debugging when reactions silently fail
to notify. Trivial.

### 🟢 N5 — No client-side test for absolute-count semantics

Server-side tests for `ReactionsRepo` and routes are solid. There's no
client test confirming that `useMessageStore.addReaction` correctly applies
the server's absolute count for other users (the very thing R2-1 fixed).
A small store unit test would lock in the behavior.

### 🟢 N6 — Emoji length cap of 64 chars

Generous enough for current Unicode emoji (longest ZWJ family ~28 bytes
UTF-8), so OK. Just flagging that the limit is per-character not byte;
multi-codepoint emoji are fine.

---

## Summary Table

| ID    | Severity (R2) | Status | New Severity |
|-------|---------------|--------|--------------|
| R2-1  | 🔴 Must Fix   | ✅ Fixed | — |
| R2-2  | 🔴 Must Fix   | ✅ Fixed | — |
| R2-3  | 🟡 Should     | ✅ Fixed | — |
| R2-4  | 🟡 Should     | ✅ Fixed | — |
| R2-5  | 🟡 Should     | ✅ Fixed | — |
| N1    | new           | open   | 🟡 Should fix (type safety / discoverability) |
| N2    | new           | open   | 🟡 Should fix (perf, trivial) |
| N3    | new           | open   | 🟢 Nice-to-have |
| N4    | new           | open   | 🟢 Nice-to-have |
| N5    | new           | open   | 🟢 Nice-to-have |

**Bottom line:** R2's blockers are genuinely resolved. The remaining items
are polish — none warrant blocking the merge. Ship it, file the N1/N2
follow-ups.
