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
