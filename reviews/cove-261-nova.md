# 🌠 Nova — Round 4 Review: PR #261 (kagura-agent/cove)

**Verdict: ✅ Ready**

All three R3 blockers resolved. Diff reviewed fresh; no new regressions found. Two nits below are non-blocking.

---

## R3 Issue Status

### 🔴 → ✅ Nonce validation before DB write
**Status: Fixed.** `packages/server/src/routes/messages.ts` now validates `body.nonce` (type + length ≤64) *before* `repos.messages.create(...)`. Invalid nonce returns 400 with no row inserted → no orphan record, no client retry duplicates. Correct ordering.

```ts
// Validate nonce before DB write to prevent orphan records
if (body.nonce) {
  if (typeof body.nonce !== "string" || body.nonce.length > 64) {
    return validationError(c, "nonce must be a string of at most 64 characters");
  }
}
const message = repos.messages.create(channelId, author, body.content);
```

### 🟡 → ✅ Empty guilds READY doesn't call setChannels
**Status: Fixed.** `gateway-subscriptions.ts` READY handler:

```ts
if (data.guilds) {
  const channels = data.guilds.flatMap((g) => g.channels);
  useChannelStore.getState().setChannels(channels);
  ...
}
```

Server (`session.ts` `identify`) always sends `guilds: guildsWithChannels` (possibly `[]`). On the client, empty array is truthy → `setChannels([])` runs → `channelsLoaded` flips true → no 8s blank wait. ✅

### 🟡 → ✅ Retry path missing REST reconciliation
**Status: Fixed.** `MessageItem.tsx` `handleRetry`:

```ts
api.sendMessage(channelId, content, nonce).then((real) => {
  useMessageStore.getState().reconcilePending(channelId, nonce, real);
}).catch(() => {
  useMessageStore.getState().markFailed(tempId);
});
```

WS-down retry now resolves the optimistic bubble via REST response, matching the initial-send fix from R3. ✅

---

## Fresh Review

### Correctness
- **Nonce reconciliation idempotency** (`gateway-subscriptions.ts` MESSAGE_CREATE): `hasPending` checks both nonce match AND `pendingStatus[m.id]` truthiness. After REST reconcile clears the pending status, a late-arriving WS MESSAGE_CREATE falls through to `addMessage`, which dedupes by `id`. No duplicates. ✅
- **Server nonce echo** (`routes/messages.ts`): `message.nonce = body.nonce` is set on the response object after `create()` but before `channels.updateLastMessageId` / dispatcher broadcast. Assuming the dispatcher reads from `message`, the broadcast carries the nonce → WS reconciliation works for *other* connected tabs of the same user. ✅ (Worth a glance at the dispatcher, but no diff change implies it forwards the object as-is.)
- **Rate limit channel-write + global double consume**: Channel writes consume from both buckets. When `consume` finds tokens < 1 it does *not* deduct, so an exhausted channel-write bucket won't waste a global token on the rejected request — but the **inverse case** does: if channel-write succeeds but global is exhausted, the channel-write token has already been spent for a 429 response. Minor token leakage in a rare race; not worth blocking.

### Security
- Nonce length cap (64) prevents unbounded string storage. ✅
- Rate-limit middleware mounted *after* auth — buckets keyed by `user.id`, no unauth abuse vector. ✅
- `setGuildId` is a client-side cache helper, no auth implications.

### Performance
- READY payload now carries channels per guild; eliminates an extra REST round-trip on cold start. Good win.
- Token-bucket cleanup timer is `unref()`ed — won't block Node exit. ✅
- O(n) `findIndex` in `reconcilePending` is fine for realistic channel buffer sizes.

### Testing
- `rate-limit.test.ts` covers: header shape, global exhaustion, channel-write bucket, per-user isolation, env-flag disable, unauth bypass. Fake timers prevent refill flake. Solid coverage.
- `gateway-subscriptions.test.ts` mocks updated for `setChannels`/`setActiveChannel`/`setUser`/`setGuildId`/`useReadStateStore`. ✅
- `api.test.ts` correctly disables rate limiting via env flag in `beforeEach` and restores in `afterEach`. ✅
- `scripts/verify.sh` mirrors CI (build / tsc / test / bundle check) — addresses the "本地验证必须覆盖 CI" discipline.

### API Design
- `fetchChannels` correctly marked `@deprecated` since channels seed from READY; kept as fallback path in `App.tsx` 8s timer. Clean migration.
- `Message.nonce` typed `optional` in `@cove/shared/types.ts` — backward compatible.

---

## Non-Blocking Nits

1. **Rate-limit global token leak on channel-write+global-exhausted path** (`middleware/rate-limit.ts`): when channel-write succeeds but global is exhausted, the channel-write token is consumed for a rejected request. Cheap fix: check global first, or roll back channel-write deduction on global failure. Low impact (rare race, self-heals on refill).
2. **A11y carryover** (`MessageItem.tsx`): Retry/Dismiss are now `<button>` elements (good upgrade from spans!), but inherit row `opacity: 0.7`. Consider `aria-label` like "Retry sending message" / "Dismiss failed message" for screen readers — current text is OK but contextless when listed.
3. **`X-RateLimit-Reset` semantics** (carried from R3): currently set to `(now + resetMs)` for both success and 429 responses. On success `resetMs=0`, so `Reset = now` — slightly weird (technically means "now"). Discord sends the time when the bucket fully refills. Non-blocking polish.

---

## Summary

PR #261 is in good shape. R3's three blockers are all properly fixed with clean, minimal changes. New code (rate-limit middleware, READY-seeded channels, optimistic send pipeline) is well-tested. Ship it. 🚀

**Verdict: ✅ Ready to merge** (pending Daniyuu's final approval).
