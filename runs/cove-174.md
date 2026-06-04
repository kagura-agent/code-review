# cove#174 — remove island fields, align with Discord schema

**Date:** 2026-06-04
**Verdict:** ⚠️ Needs Changes (2/3)

## Consensus Issues
1. Missing input validation for position/type/topic fields (3/3)

## Reviewer Performance (Round 1)
| Reviewer | Verdict | Unique Finds |
|----------|---------|-------------|
| 🌟 Stella | ⚠️ | FK-off try/finally, clearest on the POST topic gap |
| 🌠 Nova | ✅ | Most suggestions (6), topic nullability breaking change, scene_state cleanup |
| 💫 Vega | ⚠️ | POST ignoring type field — clearest on dead interface |

## Layer 2 — Prompt Evolution Check
- Input validation is a new-ish pattern (not seen in last 5 runs which were all guild-focused)
- Not yet a repeated cross-PR pattern — track but don't escalate to prompt yet
- If this appears again in next PR, add "new fields accepting user input must be validated" to prompt
- No prompt changes this round ✅

## Round 2 — 2026-06-04

**Verdict:** ✅ Ready (3/3 unanimous)

### Round 1 → Round 2 fixes
- Input validation for position/type/topic ✅
- POST exposes type ✅
- Migration FK try/finally ✅
- scene_state + channel_state cleanup ✅

### Reviewer Performance (Round 2)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ✅ | Verified CI + local build. Type allowlist scope was unique find |
| 🌠 Nova | ✅ | Gateway events + type allowlist duplication — most suggestions, all valid |
| 💫 Vega | ✅ | Per-guild position scoping — unique find. Used sessions_yield incorrectly but review content was good |

### Layer 2 — Prompt Evolution Check
- Input validation pattern appeared in both #174 R1 (3/3) and now confirmed fixed in R2
- This is the 2nd PR where input validation was a consensus finding
- **Escalating to prompt**: "New fields accepting user input must be validated at the route level" — adding to review standard
- Migration position subquery pattern noted by all 3 in both rounds — not a prompt issue, just SQLite knowledge

### Process Notes
- Vega used sessions_yield instead of plain text output — still got the review content via session history
- All R1 issues resolved in one round — clean convergence
