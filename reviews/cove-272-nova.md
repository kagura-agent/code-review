# 🌠 Nova — R2 Re-Review: cove#272 "feat: emoji reactions"

**Reviewer:** Nova (code reviewer persona)
**Round:** 2
**Verdict:** Request changes — 2 must-fix unaddressed (1 escalated), 3 should-fix unaddressed.

---

## R1 Issue Status

### 🔴 Must Fix

#### 1. Emoji path param validation — ✅ Fixed
`packages/server/src/routes/reactions.ts` adds `if (!emoji || emoji.length > 64) return 400` on PUT/DELETE/GET. Test `invalid emoji (too long) returns 400` covers it.

> Minor follow-up (non-blocking): length check operates on the URL-decoded UTF-8 string. A 64-char limit allows ~64 single-codepoint emoji; for ZWJ sequences this is fine. No structural emoji format validation (e.g. reject `<script>`-style payloads), but since the value is only ever stored and echoed back through JSON, it's acceptable.

#### 2. Double URL decode — ✅ Fixed
`routes/reactions.ts` uses `c.req.param("emoji")` directly. No extra `decodeURIComponent`. Hono's single decode is correct. Client `encodeURIComponent` in `lib/api.ts` round-trips cleanly.

#### 3. Client non-idempotent count math — ❌ **Partially addressed → ESCALATED to 🔴 still must-fix**
`useMessageStore.addReaction/removeReaction` adds idempotency **only for `me === true`**:
```ts
if (me && reactions[idx].me) return m;          // self-add guard
reactions[idx] = { ...r, count: r.count + 1, me: me ? true : r.me };
```
For other users (`me === false`), every duplicate `MESSAGE_REACTION_ADD` still increments `count`. Failure modes:
- WS reconnect that replays buffered events → drift on **other users'** reactions (the original concern).
- Backend retransmits / multi-tab same identity not normalized.
- No reconciliation when `messages.list` re-runs (the route now returns absolute `reactions[]`, but the store has no merge that resets count from the authoritative payload after reconnect).

**Recommended fix (still):** either
- (a) server-side: emit absolute `count` and `me` in the WS payload, client does last-writer-wins replace; or
- (b) client-side: track per-emoji `Set<userId>` (set-membership) instead of integer counter — naturally idempotent.

The current half-fix gives a false sense of safety (self path is sound, others are not). Severity stays 🔴 because count drift is user-visible and re-renders incorrectly.

#### 4. Zero tests — ✅ Fixed
`packages/server/src/__tests__/reactions.test.ts` (180 lines) covers:
- Repo: idempotent add, remove-when-absent, remove-after-add, `getForMessage` aggregation w/ multi-user, batch `getForMessages`, CASCADE on message delete.
- Routes: PUT 204, idempotent PUT, DELETE 204, GET users, invalid emoji 400, message-not-in-channel 404.

Good coverage. Gaps (not blocking): no test for client store `addReaction`/`removeReaction` idempotency (would have caught issue #3), no test for `SentMessageTracker` LRU eviction (issue #7).

---

### 🟡 Should Fix

#### 5. SentMessageTracker lost on restart — ✅ Fixed
`channel.ts` adds REST fallback: when `sentMessages.has(messageId)` is false in `"own"` mode, calls `restClient.getMessage(...)` and checks `msg.author.id === botUser.id`. On hit, caches via `sentMessages.add()`. Pragmatic fix; cost is one extra GET per unknown message reaction — acceptable for low-rate reaction events.

> Minor: failure path silently `return`s on REST error — a transient 5xx will swallow a legitimate own-message reaction notification. Logging the error (debug level at least) would help diagnose.

#### 6. `getUsersForReaction` unbounded + N+1 — ❌ Unaddressed → **ESCALATED to 🔴**
`routes/reactions.ts` GET handler:
```ts
const userIds = repos.reactions.getUsersForReaction(messageId, emoji);  // unbounded
const users = userIds.map((uid) => { const user = repos.users.getById(uid); ... });  // N+1
```
- No `?limit` / `?after` query parsing (Discord's spec supports `limit` 1–100, `after` cursor).
- One DB roundtrip per user. On a popular reaction (hundreds of reactors) this is a DoS vector — single HTTP request triggers N synchronous SQLite calls on the request thread.

Escalation rationale: with the route now landed and tested, this is a live perf footgun. R1 flagged it; not addressed at all.

**Recommended fix:**
- Add `limit` (default 25, max 100) and `after` cursor in `repos.reactions.getUsersForReaction`.
- Replace per-user `getById` loop with a single `SELECT ... FROM users WHERE id IN (...)` (or JOIN inside the reaction query).

#### 7. LRU eviction bug — ❌ Unaddressed
`SentMessageTracker.add`:
```ts
add(id) {
  if (this.ids.size >= this.maxSize) {
    const first = this.ids.values().next().value;
    if (first) this.ids.delete(first);
  }
  this.ids.add(id);
}
```
If `id` is already present, `Set.add` is a no-op, but we have already evicted the oldest entry — a no-op call shrinks the cache by 1. Also not LRU semantically (insertion order, not access order); a re-`add` of an existing id does not refresh its recency.

**Recommended fix:**
```ts
add(id) {
  if (this.ids.has(id)) {
    this.ids.delete(id);   // refresh recency
  } else if (this.ids.size >= this.maxSize) {
    const first = this.ids.values().next().value;
    if (first) this.ids.delete(first);
  }
  this.ids.add(id);
}
```
Add a unit test covering both the early-return-on-duplicate path and recency refresh.

#### 8. React key uses `emoji.name` only — ❌ Unaddressed
`MessageItem.tsx`:
```tsx
{message.reactions?.map((r) => (
  <button key={r.emoji.name} ...>
```
For Unicode emoji this is unique in practice, but the schema explicitly carries `emoji.id` (custom emoji), where two different custom emojis can share `name`. Once custom emoji land, React will warn / mis-diff. Cheap fix:
```tsx
key={r.emoji.id ?? r.emoji.name}
```
or `${r.emoji.id ?? ''}:${r.emoji.name}`.

---

## Fresh Findings (new code)

### 🟡 N1. `MessageList` auto-scroll dep on `lastMessageReactions`
`MessageList.tsx` adds:
```ts
const lastMessageReactions = messages?.[messages.length - 1]?.reactions;
useEffect(() => { ... scrollToBottom() ... }, [lastMessageReactions, scrollToBottom]);
```
`reactions` is recreated as a fresh array reference on every store update (the reducer always spreads `[...m.reactions]`), so this effect fires on **every** reaction event — including reactions on **older** messages, not just the last one. The early-return checks `if (!lastMessageReactions)` (truthy empty arrays still pass), so any reaction anywhere causes a re-scroll.

**Fix:** depend on a stable signal (e.g. JSON length, or `messages?.[messages.length-1]?.reactions?.length`), and only trigger when reactions on the **last visible** message change.

### 🟡 N2. Inline styles for `ReactionPills`
Heavy use of inline style objects (object literal allocated per render per pill). For a long channel with many reactions this is GC-noisy. The CSS for `.message-actions` was added — adopt the same approach for `.reaction-pill` / `.reaction-pill--mine`.

### 🟢 N3. `enqueueSystemEvent` dynamic import inside hot path
`channel.ts` does `await import("openclaw/plugin-sdk/system-event-runtime")` on every reaction add. Move the import to module top-level (or cache the resolved module on first call). Minor — Node will cache, but it's still an `await` per event.

### 🟢 N4. `getMessage` REST fallback fires per reaction event
Every reaction on an untracked message issues a REST GET. On a noisy channel this multiplies request load. Two cheap mitigations:
- Negative-cache: also remember messages confirmed **not** the bot's, so repeated reactions on the same other-user message don't re-fetch.
- Or: when `messageCreate` fires for non-bot messages, optionally cache as "not own" to short-circuit.

### 🟢 N5. Type drift on `Reaction` schema
`packages/shared/src/types.ts` defines `emoji: { id: string | null; name: string }` but `gateway-client.ts` types the gateway payload's emoji as just `{ name: string }`. Either widen the gateway type to match, or add a `?? null` when constructing the dispatcher event. Currently the server's `dispatcher.reactionAdd` always sets `id: null`, so it's consistent in practice — just a typing inconsistency to clean up.

### 🟢 N6. `requireGuildMember` access check on reactions
The route correctly uses `requireGuildMember` so only guild members can add/remove/list reactions. Good. Worth a follow-up test asserting 404/403 for non-member tokens (current tests use admin only).

---

## Summary Table

| # | Issue | R1 sev | Status | R2 sev |
|---|-------|--------|--------|--------|
| 1 | Emoji length validation | 🔴 | ✅ Fixed | — |
| 2 | Double URL decode | 🔴 | ✅ Fixed | — |
| 3 | Client count idempotency (others) | 🔴 | ❌ Partial | 🔴 |
| 4 | Tests | 🔴 | ✅ Fixed | — |
| 5 | SentMessageTracker restart | 🟡 | ✅ Fixed (REST fallback) | — |
| 6 | `getUsersForReaction` pagination + N+1 | 🟡 | ❌ Unaddressed | 🔴 (escalated) |
| 7 | LRU eviction bug | 🟡 | ❌ Unaddressed | 🟡 |
| 8 | React key collision risk | 🟡 | ❌ Unaddressed | 🟡 |
| N1 | Last-message scroll effect over-fires | — | new | 🟡 |
| N2 | Inline styles in hot list | — | new | 🟡 |
| N3 | Dynamic import per reaction | — | new | 🟢 |
| N4 | REST fallback amplification | — | new | 🟢 |
| N5 | Gateway emoji type drift | — | new | 🟢 |
| N6 | Non-member access tests missing | — | new | 🟢 |

---

## Recommendation

**Do not merge as-is.** Two 🔴 remain (#3 client count drift for non-self reactions; #6 unbounded N+1 list endpoint). Fixing #6 (single SQL + limit/cursor) is small and high-value. Fixing #3 properly likely means changing the WS payload to absolute counts or moving client to set-membership — pick one and ship.

The repo + route layer is solid: schema, migration, idempotent INSERT OR IGNORE, CASCADE, batch fetch all look right and are now well-tested.
