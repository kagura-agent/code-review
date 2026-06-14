# PR #352 Round 6 Review — Stella

## Previous fixes status

Mostly intact, with one important unresolved R5 regression.

- ✅ Bot permission checks still present on all channel file routes (`GET list`, `GET file`, `PUT`, `DELETE`) before file access/mutation.
- ✅ Filename validation is still strict (`/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$/`) and blocks dotfiles/path separators/spaces.
- ✅ File size enforcement still uses byte length via the repo layer; server tests cover 100KB boundary behavior.
- ✅ `content_type` cap remains in the PUT route.
- ✅ Delete toast/error feedback and channel-file store reset on channel switch are still present.
- ✅ `CoveApiError` typed API errors and dispatch warning log for `cove.md` fetch failures are still present.
- ⚠️ **R5 TimeoutError-vs-AbortError finding is still not addressed.** `dispatch.ts` passes `AbortSignal.timeout(2000)` into `getChannelFile()`, but `rest-client.ts` only treats `AbortError` as non-retryable. `AbortSignal.timeout()` rejects fetch with a `TimeoutError` DOMException, not `AbortError`. Because `GET` is idempotent, the client retries it using the same already-aborted signal and exponential backoff. Net effect: a promised 2s hot-path timeout can stretch to roughly 9s (`2s + 1s + 2s + 4s` backoff, plus jitter), delaying bot dispatch even though the code visually looks bounded.

## New code review

### 1. Monaco integration

#### ⚠️ Needs change: Monaco currently depends on jsDelivr at runtime

`FilesSidebar.tsx` lazy-loads `@monaco-editor/react`, which uses `@monaco-editor/loader`. By default that loader fetches Monaco assets from:

```text
https://cdn.jsdelivr.net/npm/monaco-editor@0.55.1/min/vs
```

Evidence: `node_modules/@monaco-editor/loader/lib/es/config/index.js` default config sets `paths.vs` to jsDelivr. The Vite build also produces one app chunk plus a small wrapper chunk; it does not emit local `vs/*` worker/loader assets. So opening a file editor introduces an implicit external network dependency.

Impact:

- Product/offline: the file editor fails in offline/self-hosted/internal deployments if CDN access is unavailable.
- Security/privacy: opening a Cove channel file leaks a client-side request to a third-party CDN.
- CSP/deployment: any strict `script-src`/`worker-src` policy will need to allow jsDelivr unless this is self-hosted.

Recommendation: configure Monaco to use bundled/self-hosted assets, e.g. import/configure `loader` from `@monaco-editor/react` with a local `vs` path, or switch to `monaco-editor` + Vite worker setup (`?worker`) so editor assets are emitted by the app build.

#### Notes

- ✅ The React lazy boundary does split out a small loader wrapper and avoids putting the React wrapper in the initial component graph.
- ⚠️ The actual editor payload is still large. `pnpm -F @cove/client build` succeeds but warns about an 847.87KB minified chunk. This is acceptable-ish for an editor feature if lazy-loaded, but worth watching.
- ✅ `value`/`onChange` handling is safe for read-only and edit modes: read-only changes are ignored, edit changes update `editContent`.
- ✅ `automaticLayout: true`, `minHeight: 0`, and flex wrapper are reasonable for sidebar resizing.
- Minor UX/accessibility: icon-only Save/Edit/Delete/Back buttons still lack explicit `aria-label`/tooltip titles. Existing pattern is similar elsewhere, so not blocking, but Monaco makes this panel more central.

### 2. Guided `cove.md` creation card

- ✅ Correctly appears only when files are loaded and no `cove.md` exists.
- ✅ Uses existing `saveFile()` flow, so server auth, bot permission checks, filename validation, and byte limits still apply.
- ✅ After create, it selects/fetches `cove.md`, clears edit content, and enters edit mode.
- ⚠️ Race/UX nit: the button is not passed `loading={saving}` or disabled while saving, unlike the generic create button. Double-clicks can issue duplicate PUTs. Since PUT is idempotent and content is empty, this is not a correctness blocker, but adding `loading={saving}` would be cleaner.

### 3. Mobile files sidebar/backdrop fix

- ✅ Adds a dedicated files backdrop and `files-open` class; tapping backdrop closes both local `filesOpen` and store `filesOpen`.
- ✅ Mobile CSS now positions `.files-sidebar` fixed to the right and slides it in with `.files-open .files-sidebar`.
- ✅ z-index ordering is consistent with existing overlays: backdrop `z-index: 20`, files sidebar `z-index: 30`.
- ⚠️ Product nit: multiple mobile panels can still technically be open at once if toggles do not mutually close the others. Existing side/member behavior already has this pattern; not a new blocker for this PR.

### 4. `cove.md` injection via `UntrustedStructuredContext`

- ✅ This is the right API direction. `UntrustedStructuredContext` matches OpenClaw templating types and is rendered as untrusted JSON context by the runtime.
- ✅ The payload remains capped to 8000 bytes in dispatch, preventing a 100KB file from being injected into every prompt.
- ✅ The label/source/type provide provenance (`Channel cove.md`, `cove`, `channel-context`).
- ⚠️ Testing gap: I did not see a targeted plugin test asserting that `cove.md` is passed as `UntrustedStructuredContext` rather than the old `ChannelContext` shape. Given this is the key R6 API-change behavior, add a regression test around the dispatch context payload if feasible.

## Verification run

Commands run locally on the PR branch:

- `pnpm -F @cove/client build` — ✅ passed; Vite warned about an 847.87KB chunk.
- `pnpm -F openclaw-cove check` — ✅ passed.
- `pnpm -F @cove/server exec vitest run src/__tests__/channel-files.test.ts --reporter=dot` — ✅ 29 passed.
- `pnpm -F @cove/server exec vitest run src/__tests__/migration.test.ts --reporter=dot` — ✅ 16 passed.
- `pnpm test` — ✅ total matches claim: client 6 + plugin 55 + server 275 = **336 tests passed**.

## Summary + Verdict

**Verdict: ⚠️ Needs Changes**

The feature set is mostly well-integrated and the previous security/correctness fixes remain largely intact, but I would not merge yet because:

1. **R5 hot-path timeout issue remains unresolved**: `TimeoutError` from `AbortSignal.timeout(2000)` is still retried, so dispatch can exceed the intended 2s bound.
2. **Monaco currently pulls editor assets from jsDelivr at runtime**, which is a significant deployment/privacy/CSP regression for a self-hosted app.

Recommended fixes before merge:

- Treat `TimeoutError` like `AbortError` for explicit timeout signals, or otherwise disable retries when an external signal is supplied/already aborted.
- Configure Monaco to self-host/bundle its assets instead of using the default CDN loader path.
- Add a small regression test for `UntrustedStructuredContext` injection shape.