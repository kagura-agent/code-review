# Consolidated Review: PR #308 — fix: prevent content reflow on scrollbar hover

**Reviewers:** 🌟 Stella ✅ | 🌠 Nova ✅ | 💫 Vega ✅

---

## Critical Issues

None.

## Consensus Findings

### `as any` cast on `scrollbarGutter` (all 3)
`MessageList.tsx:62` uses `scrollbarGutter: "stable" as any`. All three reviewers note this can be dropped when `@types/react`/`csstype` is updated (already supported in `csstype ≥ 3.1.x`). Non-blocking.

## Suggestions

1. **Global `.scroll-container` impact** — CSS change affects all `.scroll-container` users, not just MessageList. Verify no other surface (e.g. narrow sidebars) relied on zero-width behavior (Nova)
2. **Consider moving `scrollbar-gutter: stable` into `.scroll-container` class** — keeps the no-reflow guarantee co-located with the custom scrollbar styling (Nova)
3. **Safari support note** — `scrollbar-gutter` requires Safari 18.2+; older Safari falls back gracefully (Nova)
4. **PR description says "one-line change"** but diff also touches `index.css` (Stella)

## Positive Notes (consensus)

- Correct root cause: previous CSS toggled `scrollbar-width` on hover, which itself triggers reflow in Firefox
- Minimal, targeted fix — 3 added / 2 deleted across 2 files
- Modern `scrollbar-gutter` approach instead of hacky padding workarounds
- WebKit and Firefox paths now symmetric (transparent thumb until hover)

## Overall Verdict: ✅ Ready — 3/3 unanimous
