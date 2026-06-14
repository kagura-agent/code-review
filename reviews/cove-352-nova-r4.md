# 🌠 Nova — Round 4 Review of PR #352 (kagura-agent/cove)

**PR:** feat: channel file space with cove.md convention (closes #344)
**Round:** 4 (re-review)
**Reviewer:** 🌠 Nova
**Scope:** Verify R3 P1 blockers were addressed; fresh look at new/changed code.

---

## R3 Issue Status

### P1 blockers (from R3)

| # | Issue | Status | Notes |
|---|---|---|---|
| 1 | `dispatch.ts` catch `{}` re-swallows errors | ✅ **Fixed** | Now `log?.warn?.()` with channel id + error message. Observability restored. |
| 2 | Regex status-matching is fragile (`/40[34]/.test(err.message)`) | ✅ **Fixed** | `CoveApiError` class with `.status` exists; `request()` throws it for non-2xx (line 71); `getChannelFile` checks `err instanceof CoveApiError && (err.status === 404 \|\| err.status === 403)`. Clean and correct. |
| 3 | Short timeout for `cove.md` fetch | ❌ **Not Fixed** | Still uses `request()` with `DEFAULT_TIMEOUT_MS = 30_000` and `MAX_RETRIES = 3`. Worst case: a slow/flaky server makes every dispatch wait ~30 s × 3 attempts + backoff ≈ 90–110 s for an *optional* context fetch. **Escalating** — see N1 below. |
| 4 | Unit tests for `getChannelFile` 404 / 403 / 500 branching | ❌ **Not Fixed** | `grep` over `packages/plugin/src/rest-client.test.ts` and `dispatch-resilience.test.ts` finds zero references to `getChannelFile`, `cove.md`, or `CoveApiError`. The new branching logic is completely untested at unit level. Server-side coverage of 404/403 exists in `channel-files.test.ts`, but that does not exercise the client's "swallow → null" conversion. **Escalating**. |

### Other R3 items (deferred, re-checked)

| # | Issue | Status |
|---|---|---|
| N3 | 8 KB silent drop in dispatch | ❌ Still silent. `if (coveMd?.content && Buffer.byteLength(...) <= 8000)` — over-limit content is dropped without a log line, so a user editing cove.md past 8 KB has no visible signal it stopped taking effect. |
| N4 | `editContent` not cleared on `handleBack` | ⚠️ Cosmetic. On reopening the editor `handleEdit` re-seeds from `fileContent.content`, so no functional bug. Still slightly dirty state. |
| N5 | Fetch race / no cancellation in store | ❌ Still present. Rapidly switching channels can let an older `fetchFiles` resolve last and overwrite the new channel's data. No AbortController. |
| Stella | Files-array flash on channel switch | ❌ Still present. `useEffect` calls `clearFileContent()` (only clears `selectedFile` + `fileContent`) and then `fetchFiles`. The `files` array from the previous channel stays visible until the new request lands. Should `set({ files: [] })` at the start of `fetchFiles`. |

### Previously fixed (re-verified)

| Item | Status |
|---|---|
| C1/C2 bot permission + tests | ✅ Intact (`requireBotChannelPermission` on all 4 routes; 8 bot permission tests in `channel-files.test.ts`). |
| `content_type` accepted + validated | ✅ Intact (type check + 255-char cap). |
| Filename regex `/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$/` | ✅ Intact, enforced on GET/PUT/DELETE single-file routes. |
| `Buffer.byteLength` for size accounting | ✅ Intact in both route and repo. |
| Delete toast (FilesSidebar) | ✅ Intact (`message.error` on catch). |
| Store no longer leaks state across channels | ✅ `clearFileContent` called in `useEffect`. (See Stella's flash for the unfinished half.) |

---

## New Issues (R4)

### N1 (P1, escalated from R3 P1.3) — `cove.md` fetch can stall *every* dispatch up to ~100 s
`CoveRestClient.request()` for `getChannelFile`:
- timeout: 30 s
- retries on 5xx and network errors (GET is idempotent): up to 3 backoffs of 1 s → 2 s → 4 s + jitter
- so a brief server hiccup or DNS blip on every message dispatch can serialize into a minute+ wait *before bot reply starts*

This is the single most user-visible risk in the PR because it runs on the hot path of every inbound message dispatch. Suggested fixes (any one):
- pass a short-deadline `AbortSignal` (e.g. `AbortSignal.timeout(2000)`) into `getChannelFile`, **or**
- add a dedicated `requestNoRetry()` / `timeoutMs` param and call it from `getChannelFile`, **or**
- treat fetch errors as `null` (the current swallow already does this for 404/403 — extend to `AbortError` + `CoveApiError` ≥ 500 and skip retries for this *one* call site).

### N2 (P1, escalated from R3 P1.4) — No unit tests for `getChannelFile` branching
Need at minimum three new tests in `rest-client.test.ts`:
1. 404 → resolves to `null`
2. 403 → resolves to `null`
3. 500 → rejects with `CoveApiError` (and `.status === 500`)

Bonus: a test confirming `CoveApiError` is thrown for any non-2xx (the type guard in `dispatch.ts` only works if the class is actually used end-to-end).

### N3 (P2) — 5xx still throws plain `Error`, not `CoveApiError`
`rest-client.ts` lines 53–60:
```ts
if (res.status >= 500) {
  lastError = new Error(`Cove API ${method} ${path} failed: ${res.status}`);
```
This is inconsistent with the 4xx path which throws `CoveApiError`. Downstream code that wants to branch on status for 5xx (e.g. distinguishing "server down, retry later" from "wrong filename") cannot do so. Tiny fix: also throw `new CoveApiError(res.status, ...)` here.

### N4 (P2) — `Stella files-array flash` regression vector for context confusion
Files from the previous channel are visible for the duration of the next channel's network round-trip. In a UI labeled "Files — N" with cove.md pinned, this is a privacy/confusion smell: you can momentarily see file *names* from a channel you just left. Two-line fix in store:
```ts
fetchFiles: async (channelId) => {
  set({ loading: true, files: [] });  // clear stale list
  ...
}
```

### N5 (P3) — `dispatch.ts` always issues a network call per message
Even channels that have never used cove.md pay one round-trip per dispatch. Minor; can be optimized later with a per-channel "no cove.md" negative cache (TTL-based), but flagging because N1 makes the worst case much worse.

### N6 (P3) — `FilesSidebar` editor `Spin` doesn't cover `saving`
`saving` is bound to the `<Button loading={saving}>` for Save but the `TextArea` remains editable during the in-flight save. Cosmetic — should disable the textarea while `saving === true` to prevent edit-after-save races.

### N7 (P3) — `getChannelFile` return type is structurally narrower than backend payload
Client declares `{ content: string; filename: string; size: number } | null`, but server returns the full `ChannelFile` (channel_id, content_type, created_at, updated_at). Not a bug, but plugin consumers can't see those fields without a cast. Either widen the type or document the intentional narrowing.

---

## Summary + Verdict

**R3 P1 score: 2 fixed / 2 unfixed.**

The two structural fixes (`CoveApiError`, dispatch warn-log) are well done and stay in. The two operational fixes (short timeout, unit tests) were *claimed in R3 to be deferrals but not landed in R4* — per escalation rule both remain P1 blockers.

The new blocker risk is concrete: `cove.md` fetch on the hot dispatch path with full 30 s × 3 retry policy is a latency landmine. This is the kind of thing that looks fine in tests and bites the moment the network has a bad afternoon.

**Verdict: ⚠️ Needs Changes**

Required before merge:
1. Short timeout (or non-retrying mode) for `getChannelFile` in dispatch path.
2. Unit tests covering 404 / 403 / 5xx branches of `getChannelFile`.

Recommended (low cost, high value):
3. Throw `CoveApiError` for 5xx (consistency).
4. Clear `files: []` at start of `fetchFiles` (eliminates the Stella flash).

The rest can land in follow-up issues.

— 🌠 Nova
