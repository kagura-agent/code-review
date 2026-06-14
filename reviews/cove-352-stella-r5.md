# PR #352 Round 5 Review — Stella

## 1. R4 Issue Status: ❌ Not Fixed

The hot-path timeout fix is only partially implemented.

Verified:
- `CoveRestClient.getChannelFile(channelId, filename, signal?)` now accepts an optional `AbortSignal` and forwards it to `request()`.
  - `packages/plugin/src/rest-client.ts:183-185`
- Dispatch now calls `restClient.getChannelFile(channelId, 'cove.md', AbortSignal.timeout(2000))`.
  - `packages/plugin/src/dispatch.ts:269`

However, the “no retries on hot path” part is **not satisfied**. `request()` still treats all idempotent requests, including `GET /files/cove.md`, as retryable on caught errors:

- `packages/plugin/src/rest-client.ts:76-84`

It only skips retry when `err.name === "AbortError"`:

```ts
if (err instanceof Error && err.name === "AbortError") throw err;
```

But in Node, `AbortSignal.timeout()` causes fetch to reject with a `DOMException` named **`TimeoutError`**, not `AbortError`. I verified this locally with Node fetch + `AbortSignal.timeout(10)`, which printed:

```text
DOMException TimeoutError The operation was aborted due to timeout
```

So the cove.md fetch can still do:

1. wait up to 2s for the first timeout,
2. then retry because the method is GET,
3. then back off between retries,
4. then retry again with the already-aborted signal.

That means dispatch can still be delayed by retry/backoff time on the hot path. The exact network call is capped by the signal, but the overall hot-path operation is not capped to 2s and is not “no retries.”

Recommended fix: allow `request()` to disable retries for this call, or skip retries whenever a caller-supplied signal is aborted / `err.name === "TimeoutError"`. For example, `getChannelFile(..., { signal, retries: 0 })` or `request(..., signal, { retries: false })` would make the intent explicit.

## 2. New Issues

No new R5 regressions found beyond the remaining timeout/retry blocker.

Previous fixes still appear intact:

- ✅ Bot permissions enforced for channel file routes via `requireBotChannelPermission`, with denied/granted bot tests.
- ✅ `content_type` is capped at 255 chars.
- ✅ Filename validation uses `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$`.
- ✅ File size uses `Buffer.byteLength(..., "utf8")` in both route validation and repo storage.
- ✅ `CoveApiError` typed class exists and is used for non-OK HTTP responses; `getChannelFile` handles 403/404 as optional context misses.
- ✅ Dispatch logs unexpected cove.md fetch failures instead of silently swallowing all errors.
- ✅ Delete flow clears selected file/content and surfaces failure toast through the component catch path.
- ✅ Files sidebar clears stale selected file/content on channel switch.

Deferred/non-blocking items are unchanged and should remain deferred:

- Unit tests for plugin `getChannelFile` behavior are still nice-to-have, not blocking.
- 5xx typed `CoveApiError` consistency is still deferred.
- Files array flash, 8KB silent cap, and redundant UI requests are not regressed.

Validation run:

```text
pnpm -F openclaw-cove check                         ✅ passed
pnpm -F @cove/server exec vitest run src/__tests__/channel-files.test.ts --reporter=dot  ✅ 29 passed
pnpm -F @cove/client build                          ✅ passed
```

## 3. Summary + Verdict: ⚠️ Needs Changes

The signal plumb-through and 2s timeout call are present, but the hot path still retries/backoffs after `AbortSignal.timeout()` because `TimeoutError` is not treated as non-retryable. This leaves the only remaining R4 blocker unresolved.

Verdict: **⚠️ Needs Changes** — make the cove.md hot-path fetch truly no-retry / bounded before final approval.
