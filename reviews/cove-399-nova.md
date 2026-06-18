# 🌠 Nova — Round 3 (Final) Re-Review of PR #399 (kagura-agent/cove)

**PR:** refactor(plugin): adopt SDK outbound adapter framework (#398)
**Branch:** `refactor/398-outbound-adapter`
**Commit tip:** `0150bd8 fix(plugin): await editQueue after seal to prevent race with final edit`
**Verdict (R3):** ⚠️ **Request changes** — the R3 commits genuinely fix the R2 critical race bugs (N1/N2) and the lost compaction preview (M2). However **C4 (tests don't exercise changed behavior) has now escalated through all three rounds without a single new assertion**, and **N4 (`coveOutbound` half-dead — `chunkerMode` and `deliveryCapabilities` still never reach `base.outbound`)** is also untouched. Streaming/delivery is finally correct; the safety net the PR description still advertises is not.

---

## R1 + R2 Issue Status (escalation pass)

### R1 critical findings
| # | R1 Issue | R2 Status | R3 Status | Final |
|---|----------|-----------|-----------|-------|
| C1 | Dead `coveMessageAdapter` import / dead adapter wiring | Resolved (production import removed) | Confirmed gone — only `resolver.test.ts:7-9` still mocks the removed `channel-outbound` module (L1, cosmetic) | ✅ Resolved |
| C2 | Draft streaming removed | Partially fixed; introduced N1 race | **Fixed.** `createFinalizableDraftLifecycle` is genuinely restored (`dispatch.ts:151-169`) with `throttleMs: 250` and proper `state`/`sendOrEditStreamMessage`/`readMessageId`/`deleteMessage` wiring. Edit queue serializes (see N1 verification below). | ✅ Resolved |
| C3 | Tool progress no-op | Resolved | Still wired (`dispatch.ts:138-142`, `onPartialReply` → `toolProgress.onPartialReply` + `draft.update`) | ✅ Resolved |
| C4 | Tests don't test changed behavior | **Not addressed; escalated by all 3 reviewers** | **Still not addressed in R3.** `dispatch-behavior.test.ts` is byte-for-byte the same. `B1`/`B4` remain `expect(...dispatchReplyWithBufferedBlockDispatcher).toBeDefined()` — the `dispatcherCall` and `mockParams` locals (`dispatch-behavior.test.ts:228-231`) are still dead. No test invokes `deliver`, no test fires concurrent `onPartialReply`, no test asserts `restClient.sendMessage`/`editMessage` call sequences. | 🔴 **Escalate again → Blocker** |
| C5 | No error recovery on final edit | Resolved | `cleanupAndSend` (`dispatch.ts:30-52`) does send-then-delete, chunks via `chunkTextForOutbound`. Fallback path on `editMessage` failure (`dispatch.ts:204-207`) still intact. | ✅ Resolved |

### R2 new findings
| # | R2 Issue | Author R3 claim | Verified? | Final |
|---|----------|-----------------|-----------|-------|
| N1 | `editQueue` `const` never reassigned — concurrent drafts | "Fixed with `let editQueue` + sequential chaining" | ✅ Verified. `dispatch.ts:115` declares `let editQueue = Promise.resolve();` and `dispatch.ts:123-148` reassigns `editQueue = editQueue.then(async () => { … })`. Concurrent `sendOrEdit` calls now serialize on the tail. | ✅ Resolved |
| N2 | `finalizeDraft` races with late partials | "`await editQueue` after `seal()` before final edit" | ⚠️ Mostly. `dispatch.ts:195-197` flips `draftState.final = true`, awaits `draft.seal()`, then `await editQueue;` — this correctly drains any in-flight or throttled-flushed edits before the final `editMessage`. **Caveat:** the guard inside `sendOrEdit` is `if (draftState.stopped && !draftState.final) return;` (`dispatch.ts:124`). A trailing `onPartialReply` that fires after `await editQueue` resolves (between the `await` and the final `editMessage`) would still be eligible to enqueue, since `draftState.stopped` is not set when only `final` is true. In practice the SDK lifecycle's `seal()` is supposed to suppress further `update()` calls, so this is a narrow race — but the local guard is logically wrong: change to `if (draftState.final || draftState.stopped) return;` to defend in depth. | 🟡 Partially resolved (M-new) |
| N3 | `deliveryCapabilities.media: false` vs inbound image support | (not addressed in R3) | Unchanged. After review: inbound images are decoded into `extraContext.MediaUrls` and never re-emitted on the outbound path, so `media: false` is technically correct. But it's never read because of N4 below. Downgrade to Low. | 🟢 Low (clarifying comment only) |
| N4 | `chunkerMode` + `deliveryCapabilities` declared on `coveOutbound` but never copied into `base.outbound` | (not addressed in R3) | **Still dead.** `channel.ts:207-212` only forwards `sendText`, `chunker`, `textChunkLimit` into `base.outbound`. The `coveOutbound` object's `chunkerMode: "markdown"` and `deliveryCapabilities: { durableFinal: {…} }` are never wired through. They are still aspirational stubs. | 🔴 **Escalate (held) → High** |
| N5 | Hardcoded chunk limit duplicated in 3 places | "Removed duplicate `COVE_TEXT_CHUNK_LIMIT` declaration" (commit `d968006`) | Partially. Bare literal `4000` in the old `text.length <= 4000` site is now `text.length <= COVE_TEXT_CHUNK_LIMIT` (`dispatch.ts:201`). But there are still **two `const COVE_TEXT_CHUNK_LIMIT = 4000` declarations** — one in `channel.ts:79`, one in `dispatch.ts:28`. They will drift. Extract to a shared constants module or export from `channel.ts` and import in `dispatch.ts`. | 🟠 Held at High |
| M1 | `dispatch-behavior.test.ts` is misleading (C4 surface) | (not addressed) | Same observations as C4. | 🔴 Escalated with C4 |
| M2 | `onCompactionStart` lost preview update | (claimed implicitly) | ✅ Restored at `dispatch.ts:254-258` — `toolProgress.onCompactionStart(); const combined = toolProgress.getCombinedText(); if (combined) draft.update(combined);` matches the pre-refactor path. | ✅ Resolved |
| L1 | Stale `channel-outbound` mock in `resolver.test.ts` | (not addressed) | Still present (`resolver.test.ts:7-9`). Cosmetic; remove. | 🟢 Low |

---

## R3 author claims — verification

| Claim | Evidence | Verdict |
|-------|----------|---------|
| 1. `editQueue` race fixed (`let` + sequential chaining) | `dispatch.ts:115`, `:123` | ✅ Verified — real serialization restored |
| 2. Message truncation fixed (clamp preview to 4000) | `dispatch.ts:128-132` — `trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - 30) + '\n\n… (streaming, full reply on completion)'` | ✅ Verified — leaves 30 chars headroom for the suffix; off-by-30 not off-by-one |
| 3. `seal()` race fixed (`await editQueue` after seal before final edit) | `dispatch.ts:195-197` | ✅ Verified for the serialized-flush window; one residual race-in-depth issue noted under N2 |
| 4. Restored `createFinalizableDraftLifecycle` from SDK with correct params | `dispatch.ts:151-169` — `throttleMs`, `state`, `sendOrEditStreamMessage`, `readMessageId`, `clearMessageId`, `isValidMessageId`, `deleteMessage`, `warnPrefix` all present | ✅ Verified — parity with Discord-style usage |

---

## 🆕 R3 fresh-eyes pass

### 🔴 N6 (High, new) — Final `editMessage` is not guarded by `editQueue`
**Location:** `dispatch.ts:201-209`

```ts
if (draftMessageId && !draftState.stopped && text.length <= COVE_TEXT_CHUNK_LIMIT) {
  …
  await restClient.editMessage(channelId, draftMessageId, text);   // ← raw await, not enqueued
}
```

The serialization fix correctly drains pending edits with `await editQueue`, but the **final edit itself does not enqueue** onto `editQueue`. Once the final `editMessage` is in flight, a trailing `draft.update(...)` from a late `onPartialReply` or `onCompactionStart` can sneak a sibling PATCH onto `editQueue` — and that sibling races against the un-queued final edit. Network ordering, not code ordering, decides the winner.

The fix used in the original (deleted) hand-written code was to push the final into the queue:

```ts
editQueue = editQueue.then(async () => {
  if (draftMessageId && !draftState.stopped && text.length <= COVE_TEXT_CHUNK_LIMIT) {
    await restClient.editMessage(channelId, draftMessageId, text);
  } else {
    await cleanupAndSend(restClient, channelId, draftMessageId, text, log);
  }
});
await editQueue;
```

Combined with the N2-depth fix (`if (draftState.final) return;` inside `sendOrEdit`), this fully serializes finalization against streaming.

Severity is High rather than Critical because the SDK's sealed-lifecycle is *supposed* to short-circuit further `draft.update` calls — but this PR has been bitten three rounds in a row by "supposed to" not matching reality. Defend explicitly.

---

### 🔴 N7 (Blocker, persistent) — Behavioral test coverage of the changed code path is still zero
This is the R1 C4 / R2 M1 issue surfacing for a third round. Concrete observations on the current file:

- `dispatch-behavior.test.ts` lines 222-247: both deliver-callback tests still bottom out at `toBeDefined()`. The variables `dispatcherCall` and `mockParams` are written and then thrown away.
- No test invokes `dispatcherOptions.deliver`, no test invokes `replyOptions.onPartialReply`, no test asserts `sendMessage`/`editMessage`/`deleteMessage` call sequences.
- The PR description still claims "Behavioral tests verify: context injection, routing, lifecycle, batching, attachments." That list omits **delivery, streaming, chunking, error recovery, and the lifecycle's interaction with the edit queue** — i.e. every code path this PR actually changed.
- The very racing bugs that ate Rounds 1 and 2 (N1, N2) would have been caught by a four-line test that fires two `onPartialReply` calls back-to-back and asserts only one POST goes out before the first one resolves. The test file's name ("dispatch-behavior") strongly implies that coverage exists; reading it, it does not.

**Per the escalation rule, unaddressed-for-three-rounds → escalate to Blocker.**

Minimum required tests before merge:
1. **Happy stream:** fire `onPartialReply("hello")` → `onPartialReply("hello world")` → `deliver({text: "hello world"})`. Assert: exactly one `sendMessage` (the first partial), one `editMessage` per change, and the final `editMessage` carries `"hello world"`.
2. **Edit failure fallback:** make `editMessage` reject. Assert: `cleanupAndSend` path fires → `sendMessage(channelId, finalText)` is called, then `deleteMessage(channelId, draftId)`.
3. **Long final (chunked fallback):** deliver text > 4000 chars. Assert: multiple `sendMessage` calls with chunked text, no `editMessage`, and the draft is deleted last.
4. **Concurrent regression guard (N1 fixture):** fire `sendOrEdit("a")` and `sendOrEdit("ab")` synchronously. Assert: at most one POST is in flight at a time and the **final** `lastSentText` is `"ab"`. This is the missing safety net that lets a future refactor silently regress serialization again.
5. **Seal-then-late-partial (N2 fixture):** call `deliver` while a tail `onPartialReply` is queued. Assert: the final `editMessage` carries `finalText`, not the late partial.

Without (4) and (5), this PR's stated goal ("Must pass before AND after refactor ✅") is unverified for the bugs that took two rounds to surface.

---

### 🔴 N4 held — `coveOutbound` is still a half-built stub
**Location:** `channel.ts:81-92` vs `channel.ts:207-212`

```ts
const coveOutbound = {
  deliveryMode: "direct" as const,
  chunker: chunkTextForOutbound,
  chunkerMode: "markdown" as const,
  textChunkLimit: COVE_TEXT_CHUNK_LIMIT,
  deliveryCapabilities: { durableFinal: { text: true, media: false, messageSendingHooks: true } },
  sendText: async (ctx: any) => { … },
};

…

outbound: {
  deliveryMode: "direct",
  sendText: coveOutbound.sendText,
  chunker: coveOutbound.chunker,
  textChunkLimit: coveOutbound.textChunkLimit,
},
```

Half the adapter shape — `chunkerMode` and `deliveryCapabilities` — never reaches the plugin SDK. The R1 C1 finding ("dead adapter code") was reduced but **still not eliminated** after three rounds. Either:
- spread `...coveOutbound` into `base.outbound`, or
- delete `chunkerMode` and `deliveryCapabilities` from `coveOutbound` and add a comment explaining why these aren't declared yet.

Currently the PR ships aspirational fields that no consumer reads, which is exactly what C1 flagged.

---

### 🟠 N5 held — Two `COVE_TEXT_CHUNK_LIMIT = 4000` declarations
**Location:** `channel.ts:79`, `dispatch.ts:28`

Both files declare `const COVE_TEXT_CHUNK_LIMIT = 4000;` independently. The R2 cleanup (commit `d968006`) removed the third copy (a bare `4000`) but did not unify the remaining two. Pick one home and import:

```ts
// channel.ts (or constants.ts)
export const COVE_TEXT_CHUNK_LIMIT = 4000;

// dispatch.ts
import { COVE_TEXT_CHUNK_LIMIT } from "./channel.js";
```

This is a one-liner that closes the entire R2 N5 surface.

---

### 🟡 N2-depth (Medium, new) — `sendOrEdit` guard is the wrong predicate
**Location:** `dispatch.ts:124`

```ts
if (draftState.stopped && !draftState.final) { resolve(false); return; }
```

This drops only the `stopped && !final` case. After `deliver` flips `draftState.final = true`, a stray `draft.update(...)` from a late callback can still flow through `sendOrEditStreamMessage` because `draftState.stopped` was never set. Tighten to:

```ts
if (draftState.final || draftState.stopped) { resolve(false); return; }
```

Pairs with N6 to fully close the finalization race surface.

---

### 🟢 L1 held — Stale mock
`resolver.test.ts:7-9` still mocks `openclaw/plugin-sdk/channel-outbound#createChannelMessageAdapterFromOutbound`. Production no longer imports it; remove the mock.

### 🟢 L2 held — Unused `Mock` type import
`dispatch-behavior.test.ts:10` imports `type Mock` from vitest and never uses it.

### 🟢 L3 held — Quote-style mixed
`channel.ts` double, `dispatch.ts` single (including the new clamp suffix string `'\n\n… (streaming, full reply on completion)'`). Prettier would unify.

### 🟢 L4 (new) — Magic offset `-30` for the suffix headroom
`dispatch.ts:130`: `trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - 30)` hand-counts the byte length of the truncation hint. The actual suffix is `'\n\n… (streaming, full reply on completion)'`, which is 44 visible chars (52 bytes — `…` is 3 bytes UTF-8). The 30-char budget under-reserves and a maximally-long preview can still exceed `COVE_TEXT_CHUNK_LIMIT` and trigger Cove's server-side reject. Use:

```ts
const SUFFIX = '\n\n… (streaming, full reply on completion)';
…
const preview = trimmed.length > COVE_TEXT_CHUNK_LIMIT
  ? trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - SUFFIX.length) + SUFFIX
  : trimmed;
```

(Strictly the server limit is presumably characters not bytes — confirm with the server schema. Either way, hand-counting is brittle.)

### 🟢 L5 (new) — `_dispatcherCall`/`_mockParams` typo dead code
`dispatch-behavior.test.ts:228, 231` — leftover scaffolding. Either complete the assertion (preferred — see N7 fixture #1) or remove the variables.

---

## Security / Auth / API
No new injection surfaces this round. The clamped preview is a pure prefix of agent output, no escaping risk. `cleanupAndSend` still sends-then-deletes (correct ordering). `extraContext.allowUnsafeExternalContent: true` remains gated by attachment presence — unchanged.

## Performance
- `throttleMs: 250` is back via `createFinalizableDraftLifecycle`, so the R2 throttle regression noted in my last review is closed.
- `chunkTextForOutbound` is called via `await client.sendMessage(channelId, chunk)` in a `for...of` loop (`dispatch.ts:39-42`). Strictly sequential — fine for correctness, but if a 30 KB final reply requires 8 chunks at ~150 ms each, the user waits ~1.2 s for the fallback path. Acceptable for the error branch; flag for future optimization.

---

## Verdict

**Request changes.** R3 finally lands the core delivery work: streaming serialization, finalize ordering, clamped preview, restored compaction poke, and a real SDK draft lifecycle. Mechanically the dispatch pipeline is correct now. But the PR cannot merge while:

- **C4 (tests) escalates a third round.** Three reviewers, three rounds, zero new assertions on the changed paths. The bugs that ate R1 and R2 (N1, N2) would each have been caught by a 4-line fixture. Until the test file actually invokes `deliver`/`onPartialReply` and asserts call sequences, "all 82 tests pass" is a vanity metric. **This is now a Blocker.**
- **N4 (dead capability fields) escalates a second round.** `chunkerMode` and `deliveryCapabilities` still never reach `base.outbound` — the very pattern R1 C1 flagged.
- **N6 (final edit not enqueued)** and **N2-depth (guard predicate)** leave a narrow but real serialization gap that defeats half the point of the R3 fix.

### Must-fix before merge (Blockers)
1. **C4/N7:** Add real behavioral tests that invoke `deliver` and `onPartialReply` and assert call sequences on `restClient.{sendMessage,editMessage,deleteMessage}`. At minimum the five fixtures listed under N7.
2. **N6:** Enqueue the final `editMessage`/`cleanupAndSend` onto `editQueue` (don't just `await` the tail beforehand).
3. **N2-depth:** Change the `sendOrEdit` guard to `if (draftState.final || draftState.stopped) return;`.

### Should-fix before merge (High)
4. **N4:** Either spread `...coveOutbound` into `base.outbound` or strip `chunkerMode` + `deliveryCapabilities` from `coveOutbound` and document why.
5. **N5:** Single source for `COVE_TEXT_CHUNK_LIMIT` (export from `channel.ts`, import in `dispatch.ts`).
6. **L4:** Compute the truncation headroom from the suffix length, don't hand-count.

### Nice to have (Low)
7. **L1:** Remove the stale `channel-outbound` mock in `resolver.test.ts`.
8. **L2 / L5:** Clean up unused `Mock` import and dead `dispatcherCall`/`mockParams` locals.
9. **L3:** Run prettier to unify quote style.

### Anti-confirmation-bias note
The R3 commit titles ("fix editQueue race", "fix message truncation", "await editQueue after seal") read like a clean three-bug sweep, and the live-verification claim is encouraging — but two rounds in a row, "Author claims fix → reviewer accepts → next round reveals regression" has been the pattern on this PR. Until C4 lands real tests, every future regression in this dispatch path will only surface in production. That's why C4 stays a blocker even though the merge-eve race fixes are correct.
