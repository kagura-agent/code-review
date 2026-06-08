# PR #261 Review - Round 4 (Vega)

## Verdict: ✅ Ready

All R3 blocking issues have been successfully addressed. The code is robust, and edge cases around race conditions (e.g., WS vs. REST message reconciliation) have been elegantly handled.

## R3 Issues Verification

1. 🔴 **Nonce validation after DB write** - ✅ **FIXED**. 
   In `packages/server/src/routes/messages.ts`, the nonce length is now validated *before* calling `repos.messages.create()`. This successfully prevents orphan DB records from being created when a 400 Bad Request is returned due to an invalid nonce.
2. 🟡 **Empty guilds READY doesn't call setChannels** - ✅ **FIXED**. 
   In `packages/client/src/lib/gateway-subscriptions.ts`, `setChannels(channels)` is called unconditionally. Combined with the update in `useChannelStore` that sets `channelsLoaded: true` whenever `setChannels` is invoked, the 8-second blank wait is completely resolved for users with no guilds.
3. 🟡 **Retry path missing REST reconciliation** - ✅ **FIXED**. 
   The `handleRetry` function in `packages/client/src/components/MessageItem.tsx` now properly chains `.then((real) => ...reconcilePending(channelId, nonce, real))`, ensuring retried messages resolve out of the pending state even if the WebSocket is down.

## Fresh Review Observations

1. **Race Condition Handled Gracefully**: The dual-reconciliation mechanism handles WS vs. REST races perfectly. If the WS `MESSAGE_CREATE` event arrives before the REST `api.sendMessage` resolves, `pendingStatus` is cleared and the late REST reconciliation safely no-ops. If REST resolves first, the WS `addMessage` correctly deduplicates against the new `realMessage.id`. 
2. **UX Improvement on Send Failure**: Removing `setContent(text)` on send failure in `MessageInput.tsx` was a great product choice. Leaving the failed message inline with a explicit `Retry | Dismiss` indicator is much better than dumping the text back into the user's active input box.
3. **Resource Cleanup**: Good attention to detail adding `clearTimeout(fallbackTimer)` in the `App.tsx` `useEffect` cleanup.

No further changes required. Excellent work.
