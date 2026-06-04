# cove#191 — multi-line message input with auto-resize (Shift+Enter)

**Date:** 2026-06-04
**Verdict:** ⚠️ Needs Changes (2/3)

## Consensus Critical
- IME composition Enter sends prematurely — missing isComposing guard (Stella + Nova)

## Reviewer Performance (Round 1)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | 2m13s. IME + focus ring + height restore on failure. CI verified |
| 🌠 Nova | ⚠️ | IME + mobile UX + accessibility + 7 suggestions. Most thorough |
| 💫 Vega | ✅ | Mobile UX noted. Resize jitter suggestion unique |

## Layer 2 — Prompt Evolution Check
- "IME composition guard" is a new pattern — first occurrence across reviews
- This is a UI/internationalization concern. Could be a prompt dimension? Track — if it appears again, add "internationalization/IME" to prompt
- No prompt changes this round ✅

## Round 2 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (3/3)

### R1 → R2 fixes
- IME composition guard ✅
- aria-label ✅

### Escalated (3/3 consensus)
- Focus ring removed (outline: none, no replacement)
- Height not restored on send failure
- Mobile multi-line impossible

### Reviewer Performance (Round 2)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | useLayoutEffect + resize helper suggestion. Focus + composition state tracking |
| 🌠 Nova | ⚠️ | Most thorough. useEffect resize pattern, matchMedia mobile detection, WCAG cite |
| 💫 Vega | ❌ | Strictest. All 3 escalated to Critical |

### Layer 2 — Prompt Evolution Check
- "Focus ring removal" is an accessibility pattern — first occurrence in our reviews
- "Height not restored on programmatic state change" — React reconciliation gap, first occurrence
- These are UI/a11y patterns. Consider adding "accessibility" as a review dimension? Track
- No prompt changes this round ✅

## Round 3 — 2026-06-04 (FlowForge)

**Verdict:** ✅ Ready (3/3 unanimous) 🎉

### R2 → R3 fixes (all 3 resolved)
- Focus ring → :focus-visible box-shadow in MessageInput.css ✅
- Height restore → useLayoutEffect([content]) ✅
- Mobile → isTouchDevice gate + always-visible send button ✅

### Reviewer Performance (Round 3)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ✅ | 2m7s. High-contrast mode note, send button aria-label. Thorough |
| 🌠 Nova | ✅ | "Every line earns its place." Hybrid device note. Most detailed positive analysis |
| 💫 Vega | ✅ | Clean pass. Send button visibility noted |

### Layer 2 — Prompt Evolution Check
- IME composition, focus ring, mobile UX all tracked as new patterns
- All resolved in 3 rounds — clean convergence
- "Accessibility" as a review dimension? Now seen in 2 PRs (focus ring in #191, aria-label). Track for potential escalation
- No prompt changes this round ✅
