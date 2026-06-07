# 🌠 Nova — Round 2 Review: cove PR #255

**Branch:** `refactor/plugin-batch-ab` → `main`
**Scope:** +626 / -397 across 6 files (channel.ts decomposed; new dispatch.ts; gateway RESUME/seq; REST retry)

---

## R1 Status

### 🔴 C1 — RESUMED emitted `reconnect`, killing dispatches → ✅ **FIXED**
- New separate `resumed` event in `GatewayEvents`.
- `gateway-client.ts` handles `RESUMED` payload: clears resume timer, sets `hasConnectedOnce = true`, emits `resumed` (no abort semantics).
- `channel.ts` listens for `resumed` and logs only; the `reconnect` listener still aborts in-flight dispatches (correct — that path now only fires on hard reconnect via `READY` after `hasConnectedOnce`).
- `READY` handler emits `reconnect` only when `hasConnectedOnce` is true (i.e., a fresh session was minted because RESUME wasn't used / wasn't accepted) → matches comment "Hard reconnect (IDENTIFY fallback after failed RESUME)".

### 🔴 C2 — REST retry only 429, no 5xx / network / backoff → ✅ **FIXED**
- `request<T>()` now wraps the call in a `for (attempt = 0; attempt <= MAX_RETRIES; attempt++)` loop (MAX_RETRIES=3).
- 429 → `Retry-After` honored then `continue`.
- 5xx → exponential backoff `min(1000 * 2^attempt, 10_000) + jitter`, then `continue`; throw last error after exhaustion.
- Network/timeout (`catch (err)`) → same backoff + retry; `AbortError` re-thrown (caller-initiated abort respected).
- `AbortSignal.timeout(DEFAULT_TIMEOUT_MS)` provides 30 s per-attempt cap when no external signal supplied.

### 🔴 C3 — Retry-After unbounded + NaN → ✅ **FIXED**
- `Math.min(parseFloat(raw ?? "") || 1, 30) * 1000`.
  - `parseFloat(null)` → `NaN`; `NaN || 1` → 1 s default.
  - Cap at 30 s prevents pathological Retry-After values.
  - Negative values still pass `||` (since e.g. `-5 || 1` → `-5`) but `setTimeout` treats negative as 0, so harmless. Minor cosmetic note; not blocking.

### 🟡 C4 — INVALID_SESSION delayed IDENTIFY no socket guard → ✅ **FIXED**
- `const currentWs = this.ws;` captured before scheduling.
- Timer callback checks `this.ws === currentWs && this.ws?.readyState === WebSocket.OPEN` before `sendIdentify()`.
- Reference-equality guard correctly handles the case where the socket was replaced (reconnect) during the 1–5 s jitter window.

### 🟡 C5 — Channel refetch result discarded → ⚠️ **PARTIAL / ACKNOWLEDGED**
- `restClient.getChannels(account.guildId)` is called; result is logged (`fetched N channels`) but not consumed.
- A `TODO: update channel cache when channel routing is implemented` comment is present.
- Pragmatically acceptable since the channel-routing layer doesn't yet exist; the call at least exercises the REST path on reconnect. Leaving R1 issue downgraded to a tracking TODO is reasonable, but I'd open a follow-up issue rather than ship a perpetual `TODO`.

### 🟡 C6 — RECONNECT seq preservation undocumented → ✅ **FIXED**
- New inline comment in the `RECONNECT` case:
  > "RECONNECT tells us to reconnect but keep session state for RESUME attempt. We preserve seq and sessionId so the next connection can send RESUME and recover without missing events."
- Behavior matches: only `ws.close(4000, …)` is called; `seq` and `sessionId` are untouched.

### 🟡 C7 — invalidSessionTimer not tracked → ✅ **FIXED**
- `private invalidSessionTimer: ReturnType<typeof setTimeout> | null = null;` declared.
- Cleared in `destroy()`.
- **Minor nit (not blocking):** not cleared inside `cleanup()` (only `destroy()`), so on a socket close/cleanup during the 1–5 s jitter the timer keeps ticking. The `currentWs` guard added for C4 makes this benign (timer fires, sees wrong/closed socket, no-ops), but symmetry with `clearResumeTimer()` would be nicer. Consider adding a `clearInvalidSessionTimer()` helper and calling it from `cleanup()`.

---

## New Issues / Regressions

### N1 — 🟡 Retries on non-idempotent POSTs can duplicate side effects
`request()` retries on 5xx and network errors uniformly, including `sendMessage` / `editMessage` / `sendTyping` / `deleteMessage`. If the server actually processed a `POST …/messages` and the response was lost or returned 502, the retry will re-send the message → user-visible duplicate. The current Cove REST API doesn't appear to expose an idempotency-key header, so this is a real risk.

**Suggestion:** restrict 5xx + network retries to safe methods (`GET`, `DELETE` are idempotent; `POST`/`PATCH` are not), or thread an `idempotent: boolean` flag through `request()`.

### N2 — 🟡 `sendTyping` now uses the full retry budget
`sendTyping` previously was a fire-and-forget single `fetch`. It now goes through `requestVoid → request`, inheriting:
- 30 s `AbortSignal.timeout` per attempt
- 3 retries with backoff up to 10 s each
- Worst-case ≈ 50 s per call

This conflicts with `createTypingCallbacks({ keepaliveIntervalMs: 5000 })` — a slow gateway could leave typing requests stacked, and the 5 s typing TTL on the server side expires long before retries finish. Recommend a tight per-attempt timeout (e.g., 3 s) and zero retries for `sendTyping`, or a dedicated lightweight path.

### N3 — 🔵 Catch path doesn't track `AbortError` from `AbortSignal.timeout`
Per-attempt timeout via `AbortSignal.timeout(30_000)` throws a `TimeoutError` (Node 24/undici) rather than `AbortError`. Current code:
```ts
if (err instanceof Error && err.name === "AbortError") throw err;
```
will *not* rethrow on per-attempt timeout — it falls through to retry. This is actually the desired behavior for transient timeouts (you want to retry), but the comment/intent suggests "respect aborts". Externally-passed signals that abort do throw `AbortError` → correctly rethrown. Document this asymmetry, or check `err.name === "AbortError" || (err.name === "AbortError" && signal?.aborted)` for caller-aborts only.

### N4 — 🔵 `RESUME_TIMEOUT_MS` falls back even on transient network slowness
5 s is fairly aggressive on a flaky link. If the server's RESUMED/INVALID_SESSION reply takes >5 s, the client wipes session state and IDENTIFYs, losing any in-flight events that *would* have been replayed. Consider 10–15 s, or piggyback on the first HEARTBEAT_ACK to confirm liveness.

### N5 — 🔵 New dispatch event handlers all reachable but untested in diff
`MESSAGE_UPDATE / DELETE / CHANNEL_* / GUILD_MEMBER_* / PRESENCE_UPDATE / TYPING_START` are now emitted, but no consumer listens for them in `channel.ts` and the diff includes no test coverage. Risk is small (unused emits are cheap), but the surface area expansion warrants a unit test for the dispatcher switch to prevent typos in `payload.t` strings.

### N6 — 🔵 `sendTyping` swallowed-error path
`restClient.sendTyping(channelId).catch(() => {})` (early cue) is fine, but the `createTypingCallbacks({ start: () => restClient.sendTyping(channelId) })` path now lets the promise reject after the full retry budget. `onStartError` will log warnings repeatedly. Confirm the SDK's `createTypingCallbacks` handles rejected `start()` gracefully (it appears to via `onStartError`, so OK).

---

## Verdict

**⚠️ Approve with minor follow-ups**

All seven R1 blockers are addressed; the C1/C2/C3/C4/C6/C7 fixes are correct and the decomposition into `dispatch.ts` is clean (behavior preserved, no logic drift in the extraction). C5 is a documented TODO rather than a fix — acceptable if a follow-up issue is filed.

**Before merge, recommend:**
1. **N1 (duplicate POST risk)** — gate 5xx/network retries on idempotent methods, or at minimum POST `sendMessage`. This is the only material correctness regression introduced by R2.
2. **N2 (typing retry budget)** — shrink timeout / disable retry for `sendTyping`.

**Nice-to-have:**
3. Symmetric `clearInvalidSessionTimer()` helper called from `cleanup()` (C7 nit).
4. File a follow-up issue for C5 channel-cache integration so the `TODO` doesn't rot.
5. Add a small unit test for `gateway-client` dispatch switch (N5).

Solid R2 turnaround — the structural refactor + gateway hardening landed without regressions in the dispatch pipeline. 🌠
