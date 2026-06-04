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
