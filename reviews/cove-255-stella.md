# Stella Review — Cove PR #255 (Round 6)

Verdict: ⚠️ Needs Changes

## Re-review of R5 issue

### ✅ Addressed: POST/PATCH no longer retry on 5xx/network errors

The R5 critical control-flow bug in `packages/plugin/src/rest-client.ts` is fixed:

- `POST`/`PATCH` 5xx now reaches `throw lastError` at `rest-client.ts:59`, then the `catch` rethrows at `rest-client.ts:78` because `isIdempotent === false`.
- Network errors for non-idempotent methods also rethrow at `rest-client.ts:78`.
- Tests were added in `packages/plugin/src/rest-client.test.ts`:
  - `POST (sendMessage) does NOT retry on 500`
  - `PATCH (editMessage) does NOT retry on 500`
  - `POST does NOT retry on fetch error`

I also ran:

- `pnpm -F openclaw-cove test -- --runInBand` → ✅ 53 tests passed
- `pnpm -F openclaw-cove check` → ✅ TypeScript passed

## Fresh findings

### 🟡 Idempotent 4xx HTTP errors are retried as if they were network errors

File: `packages/plugin/src/rest-client.ts:62-78`

The `!res.ok` branch throws ordinary `Error` objects inside the same `try` block:

```ts
if (!res.ok) {
  const text = await res.text().catch(() => "");
  throw new Error(`Cove API ${method} ${path} failed: ${res.status} ${text}`);
}
```

That throw is immediately caught by the broad `catch` at line 69. For idempotent methods, the catch treats it like a retryable network error:

```ts
if (isIdempotent && attempt < MAX_RETRIES) {
  await backoff;
  continue;
}
```

Impact:

- `GET /gateway` with `401`/`403`/`404` retries 4 total times instead of failing immediately.
- `DELETE /messages/:id` with `404` retries with exponential backoff, delaying cleanup/fallback paths.
- This can make auth/config mistakes look like transient network problems and adds unnecessary API traffic and user-visible latency.

Expected behavior: only `429` and idempotent `5xx`/true fetch failures should retry. Non-429 `4xx` should fail immediately for all methods.

Suggested fix: keep HTTP response error handling outside the `try/catch` that is intended for fetch/network errors, or throw a typed HTTP error and have the catch rethrow non-retryable HTTP statuses immediately. Add a regression test such as `GET does NOT retry on 401/404` and/or `DELETE does NOT retry on 404`.

## Notes

- The R5 duplicate-message blocker is resolved.
- The dispatch extraction and gateway RESUME changes still look structurally sound in this diff.
- I did not find a new critical duplicate-send path.
