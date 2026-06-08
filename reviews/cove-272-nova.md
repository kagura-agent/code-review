# 🌠 Nova — Review of cove#272: Emoji Reactions

**Verdict:** **Needs Changes** (a couple of correctness/UX bugs + missing tests; nothing catastrophic but real if merged).

Scope reviewed: full PR diff (23 files, +530/-20), plus context reads of `routes/helpers.ts`, `routes/messages.ts`, `ws/dispatcher.ts`, `app.ts`, prior migrations.

---

## Blocking issues

### B1. Self-echo double-counts reactions in the client (correctness)
**File:** `packages/client/src/lib/gateway-subscriptions.ts` + `stores/useMessageStore.ts`

There is no optimistic update — the UI mutation only happens when the `MESSAGE_REACTION_ADD` event echoes back from the server. The reducer is **not idempotent**:

```ts
reactions[idx] = { ...reactions[idx], count: reactions[idx].count + 1, ... }
```

Two real ways this breaks:

1. **Reconnect / duplicate dispatch.** If the gateway redelivers the same event (currently the server has no dedup or seq), count goes to 2 with only 1 user reacting. Once it diverges, only a hard refetch fixes it.
2. **REST + WS both increment.** Today only WS increments. The moment any future optimistic-update PR lands (very likely — clicking the pill currently has ~RTT latency before UI changes), this reducer is the wrong shape: it cannot tell whether it has already counted a given (user, emoji) tuple.

Fix: model the reducer as a set-membership change, not an increment. Either track `users: string[]` on the reaction (preferred — Discord does this in `MESSAGE_REACTION_ADD` consumers), or guard with a per-(messageId,user,emoji) seen set, or have the server-emitted event carry a `count` instead of "+1".

Same problem mirrored in `removeReaction`.

### B2. No input validation on `:emoji` path param (security / DoS)
**File:** `packages/server/src/routes/reactions.ts`

`emoji` is `decodeURIComponent(c.req.param("emoji"))` and goes straight into the DB as the PK. No length cap, no shape check. A client can:

- Insert multi-megabyte rows (`emoji` is `TEXT` with no `CHECK`) — fills disk, bloats the per-message reaction index.
- Insert arbitrary control chars / NULs / newlines — leaks back to every other client through the gateway.
- Create unbounded distinct "emoji" values per message → the `GROUP BY emoji` aggregation grows linearly.

Add a server-side limit before the DB call. Suggested: max ~64 bytes, must be either a Unicode emoji sequence or a `name:id` ref (current schema only supports the former; see N3). At minimum:

```ts
if (!emoji || emoji.length > 64) return c.json({ message: "Invalid emoji" }, 400);
```

The route-level rate limit helps but doesn't address payload shape.

### B3. Double URL-decoding on the server (correctness, latent)
**File:** `packages/server/src/routes/reactions.ts`

Hono's `c.req.param()` already URL-decodes path params. Calling `decodeURIComponent(c.req.param("emoji"))` decodes a second time. For pure emoji codepoints this is a no-op (no `%` survives), but the moment anyone sends an emoji whose representation contains `%` (custom names, future custom emoji `name:id`, or a literal `%` accidentally encoded as `%25`), the server gets a different string than the client signed up for, and silently mis-stores it.

Fix: drop the `decodeURIComponent` wrapper. Match the client's `encodeURIComponent` on the wire and trust Hono's decode.

### B4. Missing tests (testing standard)
The whole feature ships with **zero** tests for:
- `ReactionsRepo` (add/remove idempotency, getForMessage/getForMessages aggregation, `me` flag correctness, empty-list short-circuit).
- `routes/reactions.ts` (auth/membership enforcement, 404 paths, dispatcher fire-on-success-only).
- `dispatcher.reactionAdd/Remove` (guild scoping).

The only test diff is updating `LATEST_VERSION` constants from 6→7 in `migration.test.ts`. That's a migration smoke change, not coverage of the new code. Given this PR touches auth-sensitive routes and a new repo, at least repo + route happy/error paths are needed before merge.

---

## High-signal issues (should fix before or right after merge)

### H1. `r.emoji.name` as a React `key` is fragile
**File:** `MessageItem.tsx`

The PR enforces uniqueness only via DB `GROUP BY emoji` on read. If two reactions race into the local store with the same `emoji.name` (e.g. before B1 is fixed, or if a future custom-emoji code path stores `id` alongside `name`), React will warn and may diff incorrectly. Compose the key as `${r.emoji.id ?? "u"}-${r.emoji.name}`.

### H2. Plugin `SentMessageTracker` is process-local and lost on restart
**File:** `packages/plugin/src/channel.ts`

With `reactionNotifications: "own"` (the default), reactions to any bot message older than the current process get silently dropped — no system event. After a Cove or plugin restart, the bot stops being notified about reactions to its own historical messages with no log/warning beyond "tracked=false mode=own". Either:

- Persist sent-message IDs (small SQLite/file), or
- Resolve "own message" by fetching the message author via REST when the tracker misses, and cache the result.

Document the limitation in the channel section docs at minimum.

### H3. `SentMessageTracker` LRU eviction has a subtle bug
**File:** `packages/plugin/src/channel.ts`

```ts
if (this.ids.size >= this.maxSize) {
  const first = this.ids.values().next().value;
  if (first) this.ids.delete(first);
}
this.ids.add(id);
```

If `id` is **already** present, the `Set.add` is a no-op, but we still evicted the oldest unnecessarily. Reorder:

```ts
if (this.ids.has(id)) { /* refresh: delete + re-add for true LRU */ this.ids.delete(id); }
else if (this.ids.size >= this.maxSize) { ... evict ... }
this.ids.add(id);
```

Minor, but the comment claims "LRU-style" and this isn't even FIFO when collisions happen.

### H4. CSS positioning assumes `.discord-msg-row` is positioned
**File:** `packages/client/src/index.css`

`.message-actions` uses `position: absolute; top: -16px; right: 16px;` but the diff doesn't show `.discord-msg-row` having `position: relative` (and the previous file isn't in the patch). If it's `static`, the toolbar anchors to the wrong ancestor. Either verify the parent has `position: relative`, or add it defensively in the same block.

Also: `top: -16px` will collide with the previous message's content during fast scroll / dense channels. Worth a quick visual smoke check on grouped messages.

### H5. `getUsersForReaction` returns unbounded list (API design)
**File:** `routes/reactions.ts` + `repos/reactions.ts`

`GET /channels/:c/messages/:m/reactions/:emoji` returns every user who reacted, no `limit`/`after` query. Discord's real endpoint takes `?limit=&after=` and caps at 100. A message with 1k reactions returns a 1k-user JSON response and N user lookups (`repos.users.getById` in a loop — that's an N-query inside the route, not the repo). Add a `limit` param (default 25, max 100) and an `after` cursor; also collapse the per-user lookup into a single `IN (?,?,...)` query in `UsersRepo`.

### H6. `reactionNotifications` cast as `any`
**File:** `packages/plugin/src/channel.ts`

```ts
const reactionNotifications: "off" | "own" | "all" =
  (channelSection as any).reactionNotifications ?? "own";
```

This silently accepts any string from config. Validate (`if (!["off","own","all"].includes(x)) warn+default`) — otherwise a typo like `"on"` becomes the "off" branch only by accident.

---

## Nits / suggestions

- **N1.** `repos/reactions.ts` — `getForMessage` aggregates with `GROUP BY emoji` but `getForMessages` does `GROUP BY message_id, emoji ORDER BY message_id, MIN(created_at)`. Reactions inside one message are ordered by oldest-first, but across messages SQLite is free to interleave; the eventual per-message arrays should still be `MIN(created_at)` ordered — they are, fine. Just confirm with a test.
- **N2.** `ReactionsRepo` doesn't expose a `clearForMessage` — relies on FK CASCADE. That's fine, but `messages` delete tests should assert reactions are gone.
- **N3.** Schema stores only `emoji TEXT`. Custom emoji (`{id, name}`) is plumbed through the `Reaction` type as `{ id: string | null }` but `id` is always `null` end-to-end. Either drop `id` from the type for now to avoid implying support, or write a "custom emoji not yet supported" comment on the schema.
- **N4.** `useMessageStore.removeReaction`: when `count <= 1` you `splice(idx, 1)` — good. But you never check whether `me` was actually that one user; subsequent state shows `me: false` correctly only because the row vanished. Fine, just brittle once B1 is addressed.
- **N5.** `gateway-client.ts` — emitted shape uses `as` cast directly on `payload.d`. Add a tiny runtime check (`if (!payload.d?.emoji?.name) return;`) so a malformed server frame can't crash the listener chain.
- **N6.** `routes/reactions.ts` — when `repos.reactions.add` returns `false` (duplicate), you return `204` with no dispatch. That matches Discord semantics. Good — keep it that way. Worth a comment explaining intent.
- **N7.** `MessageActions` renders for every message every render — fine at current message counts, but it'd be nice to memoize once the hover toolbar grows beyond 4 quick emojis.
- **N8.** Migration file doesn't add `ON CONFLICT` behavior to the PK (relies on `INSERT OR IGNORE` at the repo). That's consistent with the rest of the codebase, no change needed.
- **N9.** Consider logging the failure path in `plugin/channel.ts` when `getUser` / `getChannel` fall back to IDs — the silent `catch {}` swallows real auth/network issues.

---

## What's done well 👍
- N+1 avoided cleanly via `getForMessages(ids, currentUserId)` — single grouped query.
- Auth path reuses `requireGuildMember` consistently across PUT/DELETE/GET — no new auth surface to audit.
- Dispatcher emits only on actual state change (`if (added)` / `if (removed)`), avoiding redundant fanout.
- `INSERT OR IGNORE` makes concurrent identical adds safe at the DB layer.
- `FOREIGN KEY ... ON DELETE CASCADE` correctly cleans reactions when message/user is deleted.
- `enqueueSystemEvent` import is dynamic but cached after first call — no per-event hot path penalty.
- Light, minimal client store changes; the WS subscription wiring is consistent with existing patterns.

---

## Summary
The architecture is sound and the schema is right. Blocking items are: (B1) non-idempotent count math will visibly drift on any reconnect or future optimistic update, (B2) unvalidated emoji path-param is a real DoS/integrity hole, (B3) double URL-decoding is a latent bug, and (B4) no tests for a new auth-sensitive route + repo + dispatcher path. Fix those four, address H1–H6 in the same or a follow-up PR, and this is ready.

— 🌠 Nova
