# PR #308 Review — fix: prevent content reflow on scrollbar hover

**Reviewer:** 🌠 Nova
**Verdict:** ✅ Ready (with minor suggestion)

## Summary
Tiny, targeted fix for issue #286. The root cause is that on Firefox the `:hover` rule was toggling `scrollbar-width` from `none` → `thin`, which actually reserves layout space and reflows the message content. The fix flips the strategy: always reserve a thin gutter, but render the thumb transparent until hover. Combined with `scrollbar-gutter: stable` on the MessageList container, content width is now constant regardless of scrollbar visibility. Implementation matches PR description; 3 added / 2 deleted across 2 files.

## Critical Issues
None.

## Product Impact
- **Firefox**: The hidden state now shows a `thin` track lane instead of zero width. Because the thumb (and presumably the track) is transparent, the lane should be visually invisible, but the gutter does occupy ~6–10px of layout width. This is exactly the intent — predictable layout > zero-width scrollbar.
- **WebKit (Chromium/Safari)**: Behavior is driven by `::-webkit-scrollbar { width: 8px }` which was unchanged, plus `scrollbar-gutter: stable` newly applied to `MessageList`. Net effect: gutter stable, thumb invisible until hover. Matches Firefox behavior. ✅
- **Other `.scroll-container` users**: The CSS change affects every element using `.scroll-container`, not just MessageList. Worth a quick grep to confirm no other surface relied on the old zero-width behavior (e.g., narrow sidebars where a permanent 8px gutter would look wrong). The MessageList tsx change is scoped, but the CSS change is global.

## Suggestions
1. **Drop the `as any` cast** in `MessageList.tsx:62`. `scrollbarGutter` has been in `csstype`/React's CSSProperties for a while (`csstype ≥ 3.1.x`). If TS does complain, prefer `scrollbarGutter: "stable"` with no cast, or add a single ts-expect-error with a comment — `as any` silently hides future type regressions. Low priority.
2. **Consider applying `scrollbar-gutter: stable` inside `.scroll-container`** itself instead of (or in addition to) inlining it on `MessageList`. That keeps the "no reflow" guarantee co-located with the class that opts into the custom scrollbar treatment, and benefits any other consumer of `.scroll-container` for free. Not blocking — current placement works.
3. **Browser support note**: `scrollbar-gutter` requires Firefox 97+, Chrome 94+, Safari 18.2+. Safari support is recent (late 2024); older Safari falls back gracefully (gutter not reserved → original reflow returns on hover). Acceptable for a chat client targeting modern browsers, but worth knowing.
4. **Firefox `scrollbar-width: thin` track color**: With `scrollbar-color: transparent transparent`, both thumb and track are transparent in the resting state — good. Just confirm visually in Firefox that no faint track line appears (some themes render a 1px divider regardless).

## Positive Notes
- Correct diagnosis: the previous CSS toggled `scrollbar-width` on hover, which is itself a reflow trigger in Firefox. Fixing the toggle is the right layer to fix at.
- Minimal diff, single responsibility, clear PR description with the actual mechanism explained.
- Uses the modern `scrollbar-gutter` property rather than hacky padding workarounds.
- WebKit and Firefox paths are now symmetric (transparent thumb until hover) — easier to reason about going forward.
