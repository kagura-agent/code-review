# cove#168 — introduce proper guild storage

**Date:** 2026-06-04
**Verdict:** ⚠️ Needs Changes (2/3)

## Reviewer Performance

| Reviewer | Verdict | Unique Finds | Accuracy Notes |
|----------|---------|-------------|----------------|
| 🌟 Stella (GPT-5.5) | ⚠️ | Migration silent failure, membership enforcement | Deepest analysis — found the SQLite ALTER TABLE edge case |
| 🌠 Nova (Opus 4.7) | ✅ | getById cross-guild leak, positional arg drift | Thorough but calibrated as non-blocking; good for stable codebase |
| 💫 Vega (Gemini 3.1 Pro) | ⚠️ | — | Focused on channel ID collision, less depth than others |

## Consensus Issues
1. Channel ID collision across guilds (3/3)
2. DEFAULT 'cove' hardcoded in SQL (2/3)

## Process Notes
- FlowForge `--input` param doesn't exist — manually spawned reviewers. SKILL.md fixed.
- All three completed in ~3 minutes
- Stella found the most non-obvious issue (SQLite migration + catch swallowing)

## Re-review (Round 2) — 2026-06-04

**Verdict:** ✅ Ready with caveats (improved)

### Round 1 → Round 2 fixes
- Channel ID: slug → UUID ✅
- Auth + membership on guild routes ✅  
- Migration error handling: pattern match ✅

### Remaining
- Migration REFERENCES + FK enforcement edge case (Stella)
- Test coverage for auth paths (both)

### Reviewer Performance (Round 2)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | Found SQLite ALTER TABLE + FK edge case — deepest again |
| 🌠 Nova | ✅ | 8 suggestions, all well-calibrated, UUID behavioral break was unique |
| 💫 Vega | ? | Output exceeded size limit, review unreadable |

### Process Notes
- Vega (Gemini 3.1 Pro) produced oversized output that got truncated — need to add output length guidance to reviewer prompts

## Round 3 — 2026-06-04

**Verdict:** ⚠️ Needs Changes (3/3 unanimous)

### Key Finding
Direct channel/message routes bypass guild membership — 3/3 independently flagged same IDOR. This is the remaining blocker.

### Reviewer Performance (Round 3)
| Reviewer | Verdict | Unique Finds |
|----------|---------|-------------|
| 🌟 Stella | ⚠️ | Exact line numbers for all affected routes, ran full build to verify tests |
| 🌠 Nova | ⚠️ | getDefaultId fallback + duplicate names, most suggestions |
| 💫 Vega | ⚠️ | PRAGMA finally block, IDOR framing clearest |

### Process Notes
- Output constraint in prompt worked — Vega's review was readable this time
- All 3 reviewers converged on the same critical issue independently — high confidence finding
- Round-over-round tracking table added to PR comment for visibility

## Round 4 — 2026-06-04

**Verdict:** ✅ Ready (2/3)

### Round 3 → Round 4 fixes
- requireGuildMember helper + consistent application ✅
- Non-member test suite (9 negative cases) ✅
- PRAGMA in finally ✅
- getDefaultId fail-fast at startup ✅

### Remaining
- Presences endpoint no membership check (Stella critical / Nova suggestion)
- Partial negative test coverage for some auth branches (Stella)

### Reviewer Performance (Round 4)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | Found presences gap + ran full test suite locally. Test coverage requirement worked — she flagged missing negative tests as Critical per updated prompt |
| 🌠 Nova | ✅ | Same presences finding but calibrated as suggestion. 7 suggestions, all valid |
| 💫 Vega | ✅ | Clean pass, output within limits. Weakest depth — missed presences gap |

### Layer 2 — Prompt Evolution Check
- Read last 5 runs: cove-165 through cove-168
- Security test requirement (added after R3) triggered correctly in R4 — Stella escalated missing negative tests to Critical
- No new repeated patterns found across runs
- Prompt change validated: working as intended ✅

### Process Notes
- All 3 reviews readable (Vega output constraint working)
- Updated prompt successfully changed reviewer behavior — Stella explicitly cited test requirement
- Presences is the last holdout, consistent with the incremental fix pattern across rounds

## Round 5 — 2026-06-04

**Verdict:** ✅ Ready (2/3)

### Round 4 → Round 5 fixes
- Presences endpoint membership check ✅
- 16-case non-member test suite ✅
- getDefaultId fail-fast + memoize ✅
- requireGuildMember helper centralized ✅

### Remaining (follow-up)
- WS layer not guild-scoped (Stella only — out of PR scope)

### Reviewer Performance (Round 5)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | Went deepest again — found WS layer gap. Ran full build. But arguably over-scoped for this PR |
| 🌠 Nova | ✅ | 6 suggestions, all calibrated. SQL interpolation concern was unique and valid |
| 💫 Vega | ✅ | Found position calculation edge case — unique and non-obvious. Improved from earlier rounds |

### Layer 2 — Prompt Evolution Check
- Read last 5 runs (cove-165 through cove-168)
- Security test requirement working well — reviewers correctly flagged comprehensive negative tests as positive
- No new repeated suggestion patterns found
- Stella's WS concern is architectural, not a prompt gap — prompt correctly covers "what the PR touches"
- No prompt changes needed this round ✅

### Process Notes
- 5 rounds total for this PR — each round fixed what was found, steady convergence
- All 3 reviewers readable every round since output constraints added (R3+)
- Prompt evolution from R3 (security tests = Critical) validated across R4 and R5
