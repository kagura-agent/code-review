# Code Review - PR #252 (Round 2)

**Reviewer:** 💫 Vega  
**PR:** kagura-agent/cove #252  

## 1. R1 Issues Status
- ✅ **GUILD_MEMBER_ADD/REMOVE incorrectly mutates global presence:** Fixed. Dedicated events added to `GatewayEventMap`, server correctly emits them in `agentRoutes`, and client `gateway-subscriptions.ts` adds stubs explicitly documenting they do not drive presence.
- ✅ **GUILD_CREATE/GUILD_DELETE silently dropped:** Fixed. These events are now correctly added to the `gatewayEvents` Set in `useWebSocketStore.ts`, allowing them to be dispatched to handlers rather than being silently ignored. 

## 2. New Issues (Regressions)
- None. The cascade cleanup (`removeChannelMessages`, `removeChannel`) for `useMessageStore`, `useReadStateStore`, and `useTypingStore` are implemented correctly and triggered on `CHANNEL_DELETE`. `MESSAGE_DELETE` correctly incorporates `guild_id`.

## 3. Verdict
✅ **Approved.** The fixes correctly address the issues raised in R1 without introducing regressions.
