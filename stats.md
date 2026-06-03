# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 16 | ~3m | 16/16 (100%) | Most thorough. Runs tests locally. Catches edge cases (migration recovery, accessibility, duplicate IDENTIFY). |
| 🌠 Nova | claude-opus-4.7 | 16 | ~2m | 16/16 (100%) | Consistently strongest. Best at protocol/auth analysis, breaking changes, architectural paths. |
| 💫 Vega | gemini-3.1-pro-preview | 16 | ~1m | 11/16 (69%) | R1 cove-145 failed (no output). Otherwise good calibration. Unique findings when working (readyState guard). Fastest. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready (w/ caveat) |
| #145 | cove | 2026-06-03 | R1-R2 | ✅ Ready |

## Milestones
- **cove-144 R1**: First PR where all 3 caught a genuine data-loss bug.
- **cove-144 R2**: First split verdict — Stella found deeper edge case.
- **cove-145 R1**: Vega failed (no output). First 2-reviewer review.
- **cove-145 R2**: Vega recovered. All 3 clean.
