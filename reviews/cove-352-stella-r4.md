# 🌟 Stella R4 Review — PR #352 (`kagura-agent/cove`)

## 1. R3 Issue Status

### Nova P1 — dispatch / `cove.md` fetch path

#### ✅ Fixed — `dispatch.ts` no longer silently re-swallows unexpected `cove.md` fetch errors

Verified in `packages/plugin/src/dispatch.ts:268-275`:

```ts
try {
  const coveMd = await restClient.getChannelFile(channelId, 'cove.md');
  if (coveMd?.content && Buffer.byteLength(coveMd.content, 'utf8') <= 8000) {
    coveMdContent = coveMd.content;
  }
} catch (err) {
  log?.warn?.(`cove: failed to fetch cove.md for [${channelId}]: ${err instanceof Error ? err.message : err}`);
}
```

The outer dispatch catch still preserves graceful fallback, but it now emits a warning for unexpected failures instead of disappearing entirely. This addresses the R3 observability blocker.

#### ✅ Fixed — regex status matching replaced with typed `CoveApiError.status`

Verified in `packages/plugin/src/rest-client.ts:12-17`, `:69-72`, and `:183-189`.

`request()` now throws a typed `CoveApiError` for non-OK API responses:

```ts
throw new CoveApiError(res.status, `Cove API ${method} ${path} failed: ${res.status} ${text}`);
```

`getChannelFile()` now checks structured status directly:

```ts
if (err instanceof CoveApiError && (err.status === 404 || err.status === 403)) return null;
```

This removes the fragile R3 regex/message sniffing issue.

#### ❌ Not Fixed — no dedicated short timeout for optional `cove.md` fetch

`dispatch.ts` still calls:

```ts
await restClient.getChannelFile(channelId, 'cove.md')
```

and `getChannelFile()` still delegates to `request()` without passing a short `AbortSignal`. That means the optional context fetch uses the generic REST client default timeout path (`DEFAULT_TIMEOUT_MS = 30_000` in `rest-client.ts:13`, applied at `:47`).

This remains on the hot dispatch path before the actual agent dispatch starts. A missing or slow files endpoint can still delay every message significantly even though `cove.md` is optional. The R3 ask was a dedicated ≤3s/no-long-retry timeout for this fetch; I do not see that implemented.

Status: **❌ Not Fixed**. Per the R4 escalation rule, this should remain a pre-merge change, not be downgraded.

---

### Other R3 items marked for deferral

#### ⚠️ Partially Fixed / Deferred — files array not cleared or guarded on channel switch

R3 already fixed the more serious selected-file/content leak by clearing detail state in `FilesSidebar` on `channelId` change (`FilesSidebar.tsx:177-182`).

However, the global `files` array in `useChannelFilesStore.fetchFiles()` is still not cleared at fetch start and has no stale-request/channel guard:

```ts
set({ loading: true });
const files = await api.getChannelFiles(channelId);
set({ files, loading: false });
```

So a previous channel’s file list can remain visible during loading/failure, and an out-of-order response can still overwrite the current list. This is now a minor UI flash/race rather than the earlier selected-content leak. I agree this can be deferred if the short timeout is handled.

#### ❌ Not Fixed / Deferred — no unit test for `getChannelFile()` contract

I did not find plugin unit coverage that locks in: 404/403 → `null`, 5xx/network → throw. This should be added eventually, but I agree it is not the main merge gate if the implementation is simple and now typed.

#### ❌ Not Fixed / Deferred — silent 8KB `cove.md` injection cap

The 8KB check is still silent:

```ts
if (coveMd?.content && Buffer.byteLength(coveMd.content, 'utf8') <= 8000) {
  coveMdContent = coveMd.content;
}
```

A `cove.md` over 8KB is saved successfully by the UI/server but not injected. This is UX/documentation polish unless product wants truncation/warning now. I would not block this PR on it.

#### ❌ Not Fixed / Deferred — redundant requests / silent limit over-escalation

`saveFile()` still refreshes via `fetchFiles()` and conditionally `fetchFile()` after PUT. This is inefficient but not a correctness blocker. I continue to treat it as deferred optimization, not a merge blocker.

---

### Previously fixed items still in place

- ✅ Bot permission bypass remains fixed and covered by tests. The channel-files route checks guild membership and `requireBotChannelPermission()`, and tests cover denied/granted bot cases.
- ✅ `content_type` length cap remains in place.
- ✅ Filename regex validation remains in place for file routes.
- ✅ File size uses `Buffer.byteLength()` on server and plugin-side 8KB gate.
- ✅ Delete failure toast remains fixed (`FilesSidebar.tsx:213-220`).
- ✅ Selected file/content channel-switch leak remains fixed (`FilesSidebar.tsx:177-182`).

## 2. New Issues

No new blocking issues found in the R4 changes.

One detail worth noting: because the timeout was not specialized, timeout behavior still inherits the generic REST request behavior. This is the same outstanding R3 issue, not a new one.

## 3. Summary + Verdict

R4 fixes two of Nova’s three P1 sub-issues cleanly:

- ✅ dispatch now logs unexpected `cove.md` fetch failures via `log.warn`.
- ✅ status handling now uses a typed `CoveApiError.status` instead of regex matching.

But the optional `cove.md` fetch still has no dedicated short timeout, so the dispatch hot path can still wait on the generic 30s REST timeout for optional context. Since this was an outstanding R3 P1 item and the protocol says unaddressed issues must not be downgraded, my verdict remains:

**Verdict: ⚠️ Needs Changes**

Recommended minimal fix before merge: add a short timeout path for `getChannelFile()` when used by dispatch, e.g. allow `getChannelFile(channelId, filename, signal?)` or `timeoutMs?`, and call it from `dispatch.ts` with a small timeout such as 2–3 seconds. Everything else listed above can be deferred.

## Verification run

- `gh pr view 352 --repo kagura-agent/cove --json title,body,additions,deletions,changedFiles`
- `gh pr diff 352 --repo kagura-agent/cove`
- `pnpm -F openclaw-cove check` ✅
- `pnpm -F @cove/server exec vitest run src/__tests__/channel-files.test.ts --reporter=dot` ✅ — 29 tests passed
- `pnpm -F @cove/client build` ✅
