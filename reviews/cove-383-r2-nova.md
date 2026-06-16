# 🌠 Nova Re-Review — PR #383 (R2)

**PR:** `fix(plugin): thread inherits parent channel's cove.md (#382)`
**Repo:** kagura-agent/cove
**Scope:** 1 file, +9/-1 (`packages/plugin/src/dispatch.ts`)
**Verdict:** ⚠️ **Needs Changes** (blocking: no test coverage for behavior change)

---

## Summary

The fix is logically correct and minimal: before reading `cove.md`, look up the channel; if it's a thread (`type === 11`) with a `parent_id`, redirect the cove.md lookup to the parent channel. The try/catch fallback to the original `channelId` is a reasonable safety net.

However — under the stricter R2 test-coverage rule — **this PR changes runtime behavior on every dispatched message and adds zero tests**. That is a blocking issue, not a nit.

---

## Blocking Issues

### 1. ❌ No test coverage for the new branch

This PR introduces three distinct behavioral paths through `dispatchMessage`:

1. Non-thread channel → unchanged behavior (still reads its own cove.md).
2. Thread (`type === 11`) with `parent_id` → reads **parent's** cove.md (new behavior).
3. `getChannel` throws → falls back to original `channelId` (new behavior, silently swallowed).

None of these are exercised by a test. The existing `packages/plugin/src/` test suite (`dispatch-resilience.test.ts`, `edit-queue.test.ts`, `resolver.test.ts`, `rest-client.test.ts`, `tool-progress.test.ts`) does not cover `getCoveMd` channel resolution at all.

The closing of #382 is verified only by the author manually saying "tests passed" — but the 64 existing tests can't pass-or-fail this fix because they don't touch this path. A regression here (e.g., someone later refactors and drops the `parent_id` branch) would ship silently.

**Required:** add at least two unit tests (Vitest, similar style to `dispatch-resilience.test.ts`):

- Thread case: stub `restClient.getChannel` to return `{ type: 11, parent_id: 'parent-123' }`, assert `getCoveMd` is called with `'parent-123'`.
- Non-thread case: stub to return `{ type: 0 }`, assert `getCoveMd` is called with the original `channelId`.
- (Bonus) Fallback case: stub `getChannel` to throw, assert `getCoveMd` is still called with original `channelId` and no error propagates.

These are pure-mock tests; no network or real client needed. ~30 LOC.

---

## Non-Blocking Concerns

### 2. ⚠️ Magic number `11` for thread type

`channel.type === 11` is unexplained at the call site. The codebase likely has (or should have) a `ChannelType` constant/enum. Inline magic numbers will rot — when someone adds forum-post threads or another threadlike type, this `=== 11` silently misses them. Suggest `ChannelType.PUBLIC_THREAD` or at minimum a local `const THREAD_TYPE = 11;` with a comment linking to the Discord/Cove type table.

### 3. ⚠️ Extra REST call on every dispatched message

`getCoveMd` is cached (per `cove-md-cache.ts`), but `restClient.getChannel(channelId)` is **not** cached here. Every inbound message now triggers an additional `GET /channels/{id}` round-trip before dispatch can proceed. For a busy channel this doubles the pre-dispatch latency and load.

Cheap mitigations:
- Cache channel metadata (type + parent_id) with the same TTL strategy as cove.md.
- Or: pass `parent_id` through from the gateway event payload (the message event likely already includes channel context — worth checking before adding a network call).
- Or: short-circuit when `channel.type` is already known from the message envelope.

This is a perf concern, not correctness — but it's the kind of thing that should at least be acknowledged with a TODO.

### 4. ℹ️ Silent catch swallows real errors

`} catch { /* fall back to channelId */ }` will also swallow auth failures, 5xx, network errors — anything that might indicate a deeper problem. At minimum, `log.warn(...)` on the caught error so ops can see when thread-detection is failing in the wild. The fallback behavior is fine; the silence isn't.

### 5. ℹ️ No guard against thread-of-thread / missing parent

If `channel.type === 11` but `parent_id` is falsy (shouldn't happen, but APIs lie), we silently use the thread's own id, which is exactly the bug being fixed. Current code handles this correctly via the `&& channel.parent_id` guard — but it deserves a one-line log.warn so we notice if the invariant breaks.

---

## What's Good

- Minimal, surgical change — touches only the cove.md lookup, doesn't refactor surrounding dispatch flow.
- Try/catch fallback preserves prior behavior on any error, so worst case is "same as before the fix."
- PR description is clear and links the issue.
- The fix is conceptually right: threads inheriting parent cove.md matches user expectation.

---

## Recommendation

**⚠️ Needs Changes** — block on (1). Add the three unit tests; then this is a clean merge. Concerns (2)–(5) can be follow-ups but (2) and (4) are cheap enough to fold into the same PR.

Once tests land, I'd flip to ✅ Ready.
