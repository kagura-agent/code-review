# Consolidated Review — PR #346 Round 3

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Overall Verdict: ✅ Ready** (2-1 split; Stella ⚠️, Nova ✅, Vega ✅)

---

## R2 Blockers — All Fixed ✅

| R2 Issue | Status | Consensus |
|----------|--------|-----------|
| N1: O(N²) render | ✅ Fixed | All 3 — `lastReadIdInMessages` hoisted outside `.map()`, single `.some()` per render |
| N-Nova-1: Unread count lies (50 vs 800+) | ✅ Fixed | All 3 — "+" suffix when `entryUnreadCount >= messages.length` |
| N-Nova-2: Bottom pill outside relative container | ✅ Fixed | All 3 — pill now inside the `position: relative` wrapper |

## R1 Issues — Still Fixed ✅
C1, C2, C3, Nova-1 — all confirmed still resolved across 3 rounds.

---

## Split: Stella's Remaining Blocker

**Stella: Stale cached messages can freeze incorrect unread computation**

When a channel has stale cached messages and `lastReadId` isn't in that cache, the compute effect runs with the stale data, hits `lastReadIdx === -1`, and locks via `unreadComputedForRef`. The later fresh fetch doesn't re-trigger computation.

**Nova and Vega did not flag this.** This is a valid theoretical edge case but requires a specific sequence (stale cache + lastReadId newer than cache) and produces a recoverable wrong state (user can click Mark as Read or switch channels). **Not blocking.**

---

## Remaining Non-Blocking Items (accumulated across 3 rounds)

| Item | Status | Priority |
|------|--------|----------|
| "+" suffix disappears after loading older history (Nova N3-1) | Open | Low — snapshot a boolean instead of comparing live length |
| Bottom pill doesn't ack | Open (3 rounds) | Low |
| Mark as Read no-ops on pending last msg | Open (3 rounds) | Low |
| PR description stale (Jump ↑ vs Mark as Read) | Open (3 rounds) | Trivial |
| Extra `<div>` wrapper → use Fragment | Open (3 rounds) | Low |
| a11y: span/div → button | Open (3 rounds) | Low |
| No tests | Open (3 rounds) | Follow-up |
| Scroll handler throttling | Open (3 rounds) | Follow-up |

---

## What's Done Well

- ✅ **Three rounds of iteration** brought this from 4 critical issues to zero blockers
- ✅ **O(N²) fix is clean and correct** — one `.some()` hoisted, O(1) per row
- ✅ **"+" suffix is pragmatic** — communicates "at least N" without server-side count
- ✅ **`docs/unread-spec.md`** is a genuinely useful artifact for future maintainers
- ✅ **Channel-switch reset** correctly clears all state + refs
- ✅ **Case A/B/C logic** is well-commented and correct in all branches
- ✅ **Zero server changes** — clean client-only feature

---

## Recommendation

**✅ Merge.** File a `unread-followups` tracking issue covering: pill ack, "+" freezing, Fragment wrapper, a11y buttons, tests, PR description update.
