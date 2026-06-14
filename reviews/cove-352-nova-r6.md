# 🌠 Nova — PR #352 Round 6 Re-Review

**PR:** `kagura-agent/cove#352` — feat: channel file space with cove.md convention
**Branch:** `feat/channel-files`
**Stats:** +1,416 / −17 across 19 files
**Round:** 6 (5 prior rounds; all critical resolved before R6)
**Focus:** Monaco editor, guided cove.md card, mobile files sidebar fix, `UntrustedStructuredContext` injection; regression check on R1–R5 fixes.

---

## 1. Previous fixes — status check

| Item | Round | Status |
|---|---|---|
| Bot permission checks + tests | R2 | ✅ Intact — `requireBotChannelPermission` still gates GET/PUT/DELETE in `routes/channel-files.ts`; "denied bot" + "allowed bot" tests still present. |
| `CoveApiError` typed class + dispatch logging | R4 | ✅ Class exists in `rest-client.ts`. Dispatch handler in `plugin/src/dispatch.ts` logs via `log?.warn?.()` on unexpected error. **Caveat: see N3 below — only the `!res.ok` branch throws `CoveApiError`; the 5xx pre-throw still uses plain `Error`.** |
| 2 s timeout + `AbortSignal` on dispatch hot path | R5 | ✅ Confirmed: `restClient.getChannelFile(channelId, 'cove.md', AbortSignal.timeout(2000))`. |
| `content_type` cap, filename regex, `Buffer.byteLength` | R3/R4 | ✅ All present — regex `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$`, `content_type` ≤255 chars, `Buffer.byteLength(..., 'utf8')` used both in repo (`MAX_FILE_SIZE`) and route (`MAX_CONTENT_SIZE`). |
| Delete toast, store channel reset | R5 | ✅ `useEffect` in `FilesSidebar` clears file content and re-fetches when `channelId` changes; delete path clears selection in store. |
| 336 tests pass | claimed | Not re-run here — trust CI signal. |

**No regressions in code I inspected.**

### R4 deferred-items follow-up
- **P1.3** — Timeout on `getChannelFile` dispatch path → ✅ fixed in R5.
- **P1.4** — Unit tests for `getChannelFile` in plugin → still deferred. Acceptable given 8 dispatch tests cover the wrapper indirectly; could file follow-up.
- **N3** — 5xx `CoveApiError` consistency → ⚠️ **Partially fixed.** Only the `if (!res.ok)` branch throws `CoveApiError`. The `if (res.status >= 500)` branch (just above it) still does `lastError = new Error(...)` and re-throws after retry exhaustion. Result: a 5xx that survives retries surfaces as plain `Error`, so the `err instanceof CoveApiError && (err.status === 404 || err.status === 403)` filter in `getChannelFile` can never short-circuit on a 5xx — it just re-throws. That's actually safe (5xx ≠ "file missing"), but the typed-class invariant is incomplete. Cheap one-liner fix.
- **N4** — Files array flash on channel switch → ⚠️ **Not fixed.** `useEffect` calls `clearFileContent()` (selectedFile + fileContent only) and then `fetchFiles(channelId)` which only flips `loading: true` without resetting `files`. Result: when switching channels, the previous channel's filenames remain visible until the new list arrives. Minor UX nit; consider `set({ files: [], loading: true })` at the top of `fetchFiles`.

---

## 2. New code review

### 2.1 Monaco editor integration (`FilesSidebar.tsx`)

**Good**
- `lazy()` + `Suspense` correctly defers the ~5 MB bundle until the sidebar is opened.
- `automaticLayout: true` avoids manual resize observers.
- `wordWrap: "on"` + `minimap: false` are sensible mobile-friendly defaults.
- Language map covers common extensions; falls back to `plaintext`.
- `readOnly` toggles cleanly with `editing` state.

**Issues**

- **⚠️ P2 — CDN dependency at runtime (privacy/airgap/CSP risk).**
  `@monaco-editor/react` uses `@monaco-editor/loader` which, by default, **fetches monaco core + workers from jsDelivr** (`https://cdn.jsdelivr.net/npm/monaco-editor@x.y.z/min/vs`) at first render, even though `monaco-editor@0.55.1` is in `node_modules`. Consequences:
  1. **Offline / airgap:** editor never loads.
  2. **Privacy:** every Cove user fingerprint hits jsDelivr.
  3. **CSP:** any deployment with `default-src 'self'` will fail silently.
  4. **Supply chain:** version drift between the npm `monaco-editor` peer and the CDN-fetched version.

  Fix (one-time, in app bootstrap before first lazy import):
  ```ts
  import * as monaco from "monaco-editor";
  import { loader } from "@monaco-editor/react";
  loader.config({ monaco });
  ```
  Plus vite worker config (`monaco-editor/esm/vs/editor/editor.worker?worker`) to ship workers locally. Without this, R6's "Monaco editor" feature is effectively undeployable in restricted networks.

- **⚠️ P3 — Theme hardcoded to `vs-dark`.** App appears to have light/dark theming (CSS vars `--bg-secondary`, etc.). Editor will look out of place in light mode. Pass `theme={isDark ? "vs-dark" : "light"}` from app theme store.

- **N — No max line length / paste guard.** A 100 KB single-line paste in Monaco with `wordWrap: "on"` is fine but tokenization may stall briefly. Not blocking.

- **N — `MONACO_OPTIONS` defined at module scope.** Good (avoids recreating object on every render). Worth a comment that it's intentionally frozen.

### 2.2 Guided cove.md creation card

**Good**
- Conditional render gated by `!loading && !files.some(f => f.filename === 'cove.md')` — won't flash while loading.
- One-click creation followed by automatic open in edit mode — solid UX.

**Issues**

- **⚠️ P2 — Optimistic flow has 3 sequential awaits**, each round-trip:
  1. `saveFile` → PUT
  2. `saveFile` internal → `fetchFiles` (re-GET list)
  3. then `fetchFile` (GET the file we just created)

  On a slow link this is ~3× RTT before the editor pops. The PUT response already returns the full file (`return c.json(file, 200)` in the route, includes `content`). The client could:
  - Use PUT response directly to seed `fileContent` and skip step 3.
  - Use PUT response to push into `files` array locally and skip step 2 (or debounce it).
  Not blocking; quality-of-life.

- **N — No error path for "name already exists from another user just now".** `saveFile` is `INSERT … ON CONFLICT … DO UPDATE`, so creating cove.md when it already exists silently overwrites (size becomes the new size). Race-vs-second-user would clobber. Probably acceptable for the cove.md convention (it's collaborative), but worth a future "if-match" header.

- **N — `handleQuickCreateCoveMd` doesn't validate filename** — fine because it's hardcoded `"cove.md"`. But `handleCreateFile` (the generic +) doesn't pre-validate either; user gets the regex error only after a network round-trip. Mirroring the server regex client-side would be a kindness:
  ```ts
  const FILENAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,254}$/;
  if (!FILENAME_RE.test(name)) { message.error("Invalid filename"); return; }
  ```

### 2.3 Mobile files sidebar fix (backdrop + slide-in)

**Good**
- Backdrop `<div className="mobile-files-backdrop">` follows the exact pattern of sidebar/members — symmetry is correct.
- Mutual-exclusion logic in `App.tsx` correctly closes Members when Files opens and vice-versa, and resets the store `filesOpen` flag.
- CSS mirrors `.members-sidebar` styles (`transform: translateX(100%)` → `0`).

**Issues**

- **N — Local `filesOpen` state in `App.tsx` is dual-tracked with `useChannelFilesStore.filesOpen`.** Both are kept in sync via `setFilesOpen(next)` and the local `setFilesOpen` setter, but the store value is never *read* by anything (sidebar component doesn't gate on it; only the prop `channelId && <FilesSidebar />` from App matters). Either:
  - Remove the store `filesOpen` field entirely (and `toggleFiles`), or
  - Move the open/close into the store and read from there in App.
  Right now the store field is dead weight + a desync hazard. Low priority.

- **N — Backdrop overlay always rendered.** All three backdrops (sidebar/members/files) are always in the DOM with `pointerEvents` toggled via `overlayVisible` style. Fine — but if `styles.overlay` lacks `pointerEvents: 'none'` when not visible, the invisible backdrop could swallow clicks on desktop. (Couldn't see the styles file in the diff; if the existing sidebar/members backdrops work, this one will too — pattern parity is the safety net.)

### 2.4 `UntrustedStructuredContext` injection (dispatch.ts)

**Good**
- ✅ **Correct security boundary.** Moving from a custom `extraContext` field to the standard `UntrustedStructuredContext` array signals to downstream LLM scaffolding that this payload is untrusted user content — the right primitive for channel-controlled context.
- ✅ Structured envelope: `{ label, source, type, payload }` is consumable and labelable in prompts.
- ✅ 8 KB injection cap (`Buffer.byteLength(coveMd.content, 'utf8') <= 8000`) defends against an attacker filling the 100 KB file with prompt-injection payload.
- ✅ `getChannelFile` swallows 404/403 → cove.md remains genuinely optional.
- ✅ Errors don't block dispatch (try/catch wraps the fetch, dispatch proceeds with `coveMdContent = undefined`).
- ✅ Warn-level log includes channelId for triage.

**Issues**

- **⚠️ P3 — Silent 8 KB drop.** If cove.md is between 8 KB and 100 KB, it's stored fine but silently *not* injected. From the user's view, "I wrote channel context, why isn't the bot using it?" Suggest either:
  - Truncate at 8 KB and inject anyway (with a "// truncated" marker in the payload), or
  - Log a one-shot warn: `cove.md exceeds 8KB injection cap (size=N); skipping injection`.

- **⚠️ P3 — Total dispatch latency budget.** The cove.md fetch is sequential before `dispatchInboundDirectDmWithRuntime`. 2 s timeout is the safety net, but the **5xx retry loop inside `rest-client.ts` uses non-abortable `setTimeout` for backoff** (`new Promise(r => setTimeout(r, backoff))`). When `AbortSignal.timeout(2000)` fires during a backoff sleep, the timer keeps running; only the *next* fetch call notices the abort. Worst case for a 500-on-first-attempt: backoff = 1000 ms + jitter, then next fetch sees aborted signal and throws. So 2 s isn't a strict ceiling — could be ~2.5 s. Not a blocker; flag for future retry-with-AbortSignal refactor.

- **N — `err.message` in the warn log could leak server response text.** The `Cove API GET … failed: <status> <text>` message includes server-returned body. Low risk (it's an internal API), but if the server ever echoes user input in an error message, it lands in logs. Worth a future `err.status ? err.status : 'network'` style.

- **N — `'cove.md'` is a magic string** repeated in dispatch.ts, FilesSidebar.tsx, and the repo's ORDER BY. Consider a shared `COVE_MD_FILENAME` constant in `@cove/shared`. Cosmetic.

- **🟢 Verified:** label `"Channel cove.md"`, source `"cove"`, type `"channel-context"` — descriptive and namespaced, won't collide with other UntrustedStructuredContext entries.

### 2.5 REST routes / repo — re-scan

- ✅ `requireGuildMember` + `requireBotChannelPermission` consistently applied to all 4 routes.
- ✅ Filename validated on GET, PUT, DELETE (good — DELETE validation prevents an attacker probing odd paths).
- ✅ `parseJsonBody` + `validationError` reused — consistent with rest of codebase.
- ✅ 204 on DELETE matches REST conventions and the client void-cast.
- ✅ `upsert` preserves `created_at` via an existence check (good — observed in the test `created_at === original.created_at`).
- N — `upsert` does the existence-check `SELECT` then the `INSERT … ON CONFLICT … DO UPDATE` as two statements. Two round-trips to SQLite (cheap, same process), and the upsert could race with a concurrent delete between SELECT and INSERT — but the ON CONFLICT branch covers the re-insert case. No correctness bug.
- N — `upsert` returns `null` on oversize, which the route then maps to `validationError`. But the route already validated size *before* calling upsert (`MAX_CONTENT_SIZE` check). Redundant defensive code is fine; both share the same constant — could DRY into shared but not urgent.

### 2.6 Tests

24 tests across CRUD, listing+sort, auth, non-member 404, filename validation, size limit, 404 cases, content_type, bot-denied, bot-allowed. Coverage is strong. No tests for:
- The dispatch-time `getChannelFile` plugin wrapper (still deferred from R4).
- The Monaco editor (acceptable — Monaco itself is upstream-tested).
- The `UntrustedStructuredContext` envelope assembly in dispatch.

Adding 1–2 tests for dispatch envelope assembly would lock the contract.

---

## 3. Summary & Verdict

**Strengths**
- R6 builds cleanly on the R1–R5 foundation. No regressions in any reviewed area.
- `UntrustedStructuredContext` is the right primitive for LLM context injection — security model is sound.
- Mobile sidebar parity with members panel is clean, well-factored.
- Test coverage on the server-side is comprehensive (24 channel-files tests + permission matrix).
- Monaco lazy-loaded — no impact on first-paint for users who never open files.

**Concerns (not blocking, but should track)**
1. **P2** — Monaco CDN fallback is the most significant new issue: airgap/CSP-restricted deployments will silently break. One-line `loader.config({ monaco })` fix in app bootstrap.
2. **P2** — `handleQuickCreateCoveMd` does 3 sequential round-trips; PUT response can short-circuit.
3. **P3** — Light/dark theme not propagated to Monaco.
4. **P3** — Silent drop of cove.md >8 KB at injection time (UX surprise).
5. **P3** — `CoveApiError` typed-class story incomplete on 5xx (R4 N3 carryover).
6. **N3 / N4** from R4 — N3 partially fixed, N4 not fixed (files array flash on channel switch).

**Verdict: ✅ Ready to ship.**

R6 doesn't introduce any correctness, security, or data-integrity regressions. The Monaco CDN issue is the only concern with deployment teeth, and even that fails gracefully (editor doesn't render → user sees Suspense spinner) rather than corrupting data. Recommend merging and immediately filing a follow-up issue for: (a) Monaco bundling/CDN, (b) light-theme propagation, (c) files-array reset on channel switch, (d) `CoveApiError` 5xx consistency.

Production verification on `UntrustedStructuredContext` working as claimed is the strongest signal — that's the highest-risk change in this round and it's empirically validated.

— 🌠 Nova
