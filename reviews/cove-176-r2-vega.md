## 💫 Vega's Review (Round 2) - PR #176

### 1. Summary
This PR successfully decouples the WebSocket payload parsing from the domain stores by introducing `gateway-dispatcher` and `gateway-subscriptions`. Several critical issues from Round 1 were properly addressed, including the prototype pollution vulnerability and the event emitter mutation bug. However, **multiple issues from the previous round were ignored**. As per our escalation rules, these unaddressed issues are now elevated to **Critical** severity.

### 2. Previous Issues Status
- ✅ **Channel dedup needed in addChannel** (Consensus) — Addressed. `useChannelStore.ts` now properly checks if the channel already exists before adding.
- ✅ **Prototype pollution in event allowlist** (Vega) — Addressed. Safely migrated to `const gatewayEvents = new Set([...])`.
- ✅ **Mutation during iteration in emit()** (Nova) — Addressed. Iteration in `gateway-dispatcher.ts` now safely spreads `[...list]`.
- ❌ **No unit tests for gateway-dispatcher** (Nova) — **Not Addressed**. No test files were included in this PR.
- ❌ **useEffect deps stability in App.tsx** (Nova) — **Not Addressed**. The dependency array `[needsSetup, authLoading, setChannels, setActiveChannel, connect]` remains unchanged.
- ❌ **Typing state still in WS store** (Vega) — **Not Addressed**. `TYPING_START` in `gateway-subscriptions.ts` still directly mutates `typingUsers` inside `useWebSocketStore`. The state hasn't been decoupled into a dedicated `useTypingStore` or similar.
- ❌ **Silent message drop for non-active channels** (Nova) — **Not Addressed**. The `MESSAGE_CREATE` subscription still ignores messages unless `msg.channel_id === activeId`.

### 3. Critical Issues (Escalated)
*Note: These issues were reported in Round 1 and ignored. They are now blockers.*

- **Critical: Silent Message Drop (Unaddressed)**
  - *Location*: `packages/client/src/lib/gateway-subscriptions.ts` (Lines 22-26)
  - *Details*: `MESSAGE_CREATE` still only adds the message to the store if `msg.channel_id === activeId`. Background messages are silently dropped. A user switching to a channel after a message was received will not see it without a hard refresh.
- **Critical: Typing State still coupled to WS Store (Unaddressed)**
  - *Location*: `packages/client/src/lib/gateway-subscriptions.ts` (Lines 46-56)
  - *Details*: The stated goal of this PR is to decouple the WS store from domain stores. Yet, `typingUsers` and `clearTyping` still live in `useWebSocketStore`.
- **Critical: Missing Unit Tests (Unaddressed)**
  - *Location*: `packages/client/src/lib/gateway-dispatcher.ts`
  - *Details*: A core infrastructure piece like the gateway dispatcher must have tests validating listener registration, removal, and emission (especially given the mutation bug found in Round 1).
- **Critical: React useEffect Dependency Instability (Unaddressed)**
  - *Location*: `packages/client/src/App.tsx` (Line 187)
  - *Details*: While a teardown function was added, the dependency array was not fixed. If any of those dependencies are unstable, the app will constantly disconnect and reconnect the websocket and event bus.

### 4. Product Impact
The unaddressed silent message drop issue creates a severe UX bug: users will miss messages sent in channels they aren't currently viewing. The app will appear fundamentally broken for multi-channel usage.

### 5. Suggestions
- **Global Handlers Array**: In `gateway-subscriptions.ts`, `handlers` is tracked as a module-level variable. While functional for a single-page app, this pattern makes unit testing difficult and will leak state if SSR is ever introduced. Consider returning an unsubscribe function from `setupGatewaySubscriptions` instead of relying on a global teardown function.

### 6. Positive Notes
- The fix for prototype pollution using a `Set` is clean and secure.
- Spreading the listener array in `emit()` completely mitigates the iteration mutation bug during handler unregistration. The event emitter is now fundamentally stable.

**Rate: ❌ Major Issues**
