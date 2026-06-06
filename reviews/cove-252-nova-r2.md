# 🌠 Nova R2 Review — kagura-agent/cove#252

**PR**: feat: emit missing Gateway events and add client cascade cleanup
**Round**: 2

---

## R1 Status

### 1. 🟡 BLOCKING — GUILD_MEMBER_ADD/REMOVE mutating global presence → ✅ FIXED
`gateway-subscriptions.ts` now registers `GUILD_MEMBER_ADD` and `GUILD_MEMBER_REMOVE` as **no-op handlers with explicit TODO + comment**:
> `// GUILD_MEMBER_ADD/REMOVE: membership events, NOT presence.`
> `// Presence is driven solely by PRESENCE_UPDATE events.`

Presence is no longer side-effected by membership events. Clean fix — handlers are intentionally placeholder pending MemberStore.

### 2. 🟡 GUILD_CREATE / GUILD_DELETE silently dropped → ✅ FIXED
Both events:
- Added to `GatewayEventMap` (`gateway-dispatcher.ts`)
- Added to `gatewayEvents` Set in `useWebSocketStore.ts` (so they dispatch instead of being swallowed)
- Registered with no-op handlers in `gateway-subscriptions.ts` (with TODO referencing #228)

Server side (`dispatcher.ts`) already emits them via `addGuildToUser` / `removeGuildFromUser`. End-to-end path now closed.

### 3. 🟢 No tests for new event paths → ⚠️ PARTIAL
Added:
- `gateway.test.ts` — new `describe("GUILD_CREATE / GUILD_DELETE events")` block verifying `removeGuildFromUser` sends `GUILD_DELETE` only to the target user.
- `gateway.test.ts` — updated `MESSAGE_DELETE` assertion to include `guild_id`.
- `live guild membership update` test extended to assert `GUILD_DELETE` on kick.

**Still missing**:
- No direct test for `dispatcher.guildMemberAdd` / `guildMemberRemove` broadcast behavior.
- No test for `GUILD_CREATE` happy path (`addGuildToUser` with a real guild in repo).
- No client-side test for the new cascade cleanup on `CHANNEL_DELETE` (the meat of the client diff).
- No test for the new dev warning on unknown events.

Coverage gap is non-blocking but worth noting — the cascade cleanup is the highest-value untested code path in this PR.

### 4. 🟢 Dev warning consistency → ✅ FIXED
`useWebSocketStore.ts` now warns on unknown events when `import.meta.env.DEV` and `op === DISPATCH`:
```ts
console.warn("[Gateway] Unknown event:", payload.t);
```
Gated correctly (dev only, only for actual dispatch frames, not heartbeats/hellos).

---

## New Issues

### 🟢 Minor — `gateway-subscriptions.test.ts` mock stale
The existing test file mocks `useTypingStore.getState()` returning `{ clearTyping: vi.fn() }` but does not include `removeChannel`. Current tests don't exercise the `CHANNEL_DELETE` path, so this doesn't break, but if anyone adds a `CHANNEL_DELETE` test in this file it will throw `removeChannel is not a function`. Also applies to `useMessageStore` (missing `removeChannelMessages`) and `useReadStateStore` (not mocked at all in this file). Drive-by fix if a cascade test is added.

### 🟢 Minor — `addGuildToUser` silently skips if guild not in repo
```ts
const guild = this.guildsRepo?.getById(guildId);
if (guild) { this.sendToUser(userId, "GUILD_CREATE", guild); }
```
Asymmetric with `removeGuildFromUser`, which always emits. Acceptable (can't emit a guild you don't have), but worth a comment.

### 🟢 Nit — `removeChannelMessages` ESLint
`const { [channelId]: _, ...rest }` uses `_` for an unused destructured key. If the project's ESLint flags `no-unused-vars` on destructuring, prefer `_unused` or `// eslint-disable-next-line`. Same pattern appears in `useReadStateStore.removeChannel` (uses `_rs` / `_ur` which is fine) and `useTypingStore.removeChannel`. Just a consistency note.

### ✅ No regressions
- MESSAGE_DELETE payload extension (`guild_id?`) is backward-compatible (optional field), test updated.
- Cascade order in `CHANNEL_DELETE` handler is sensible: channel → messages → readState → typing.
- Server emit order in `agents.ts` member-remove: `guildMemberRemove` fires BEFORE `removeGuildFromUser`, so the removed user still receives their own removal event before being unsubscribed. Correct.

---

## Verdict: ✅ Approve

All R1 blockers and important issues addressed. Test coverage for the new code paths is the only soft spot — recommend a follow-up issue (or quick add) for:
1. Client cascade cleanup test on `CHANNEL_DELETE`
2. `dispatcher.guildMemberAdd/Remove` broadcast tests

Not blocking merge. Ship it.

— 🌠 Nova
