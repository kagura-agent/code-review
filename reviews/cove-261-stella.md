# Stella Review — PR #261 Round 4

## Verdict: ⚠️ Needs Changes

All three R3 blocking issues appear addressed in the current diff, but I found one fresh optimistic-send correctness race that can make a successfully sent message disappear from the UI when the initial message fetch resolves after the user sends.

## Previous Issues Status

1. ✅ **R3 🔴 Nonce validation after DB write** — addressed.
   - `packages/server/src/routes/messages.ts:53-64` now parses `nonce` and validates its type/length before `repos.messages.create()` at line 68, so invalid nonce requests no longer persist orphan messages.

2. ✅ **R3 🟡 Empty guilds READY doesn't call setChannels** — addressed.
   - `packages/client/src/lib/gateway-subscriptions.ts:102-110` calls `setChannels(channels)` whenever `data.guilds` is present. Because an empty array is truthy, `guilds: []` now sets `channelsLoaded: true` via `packages/client/src/stores/useChannelStore.ts:18-19` instead of leaving the sidebar loading forever.

3. ✅ **R3 🟡 Retry path missing REST reconciliation** — addressed.
   - `packages/client/src/components/MessageItem.tsx:110-114` now reconciles the pending retry message on REST success and marks failed on error.

Previously confirmed fixes remain present: retry duplicates, sidebar loading state, token-bucket debt, global-bucket bypass, initial send REST reconciliation, and fake timers.

## New Issue

### 🟡 Optimistic send can disappear if initial fetch overwrites pending messages

**Files:**
- `packages/client/src/components/MessageInput.tsx:100-105`
- `packages/client/src/components/MessageList.tsx:37-40`
- `packages/client/src/stores/useMessageStore.ts:24-25,40-45`

`MessageInput` inserts a pending message and then relies on `reconcilePending(channelId, nonce, real)` to replace it after REST success. However, `MessageList` always calls `setMessages(channelId, reversed)` when its initial `fetchMessages()` resolves, and `setMessages` replaces the entire channel array without preserving pending/failed messages.

Race:
1. User switches to a channel; `MessageList` starts `api.fetchMessages(channelId)` and shows loading.
2. User sends before that fetch resolves; `addPendingMessage()` inserts `pending-<nonce>`.
3. The original fetch resolves with the pre-send message list and `setMessages()` overwrites the pending message.
4. REST send succeeds, but `reconcilePending()` cannot find a message with that nonce/status (`pendingIdx === -1`) and does nothing.
5. If the gateway event is delayed/down — the exact case REST reconciliation is meant to cover — the successfully sent message is invisible until a later refetch/reload.

**Product impact:** this undermines the optimistic-send reliability goal: a user can send successfully and see their message vanish during channel load or slow network conditions.

**Suggested fix:** make either side resilient:
- Preserve pending/failed rows in `setMessages()` when replacing fetched history; or
- Change `reconcilePending()` so if no pending row exists but the real message is not already present, it appends/inserts the real message; and still clears any matching pending status if possible.

A focused regression test would be valuable: start with a pending message in the store, call `setMessages()` with fetched messages lacking that nonce, then call `reconcilePending()` and assert the real message is visible.

## Non-blocking Carried Notes

- `packages/server/src/middleware/rate-limit.ts:120-130` still consumes both channel-write and global buckets before deciding whether to reject. If one bucket is already exhausted, rejected requests can drain the other bucket too. This was already carried as non-blocking (`channel-write peek-before-consume`), but a future polish pass should peek/check both buckets before mutating either.
- `X-RateLimit-Reset` still represents the next-token time (`Date.now() + resetMs`) rather than the full bucket reset time. This may be acceptable for Cove’s current Discord-like compatibility target, but it is not a perfect Discord semantic match.

## Positive Notes

- The nonce validation ordering fix is clean and directly addresses the orphan-record problem.
- READY seeding is now simpler and removes unnecessary startup REST calls in the normal WebSocket path.
- Retry and initial-send REST reconciliation now cover the important WS-down success path.
- I verified `pnpm -r exec tsc --noEmit` passes, and the focused server suites `vitest run src/__tests__/rate-limit.test.ts src/__tests__/api.test.ts` pass (101 tests). Note: my first vitest invocation used repo-root paths under the server package and found no files; rerunning with package-relative paths passed.
