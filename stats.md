# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 15 | ~3m | 15/15 (100%) | Most thorough. Runs tests locally. Catches edge cases others miss (migration recovery, accessibility). |
| 🌠 Nova | claude-opus-4.7 | 15 | ~2m | 15/15 (100%) | Consistently strongest. Best at protocol/auth analysis, breaking changes, architectural paths. |
| 💫 Vega | gemini-3.1-pro-preview | 15 | ~1m | 10/15 (67%) | Failed on cove-145 (no output, broke 5-run streak). Fast when working. Calibration good on successful runs. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready (w/ caveat) |
| #145 | cove | 2026-06-03 | R1 | ✅ Ready |

## Milestones
- **cove-144 R1**: First PR where all 3 caught a genuine data-loss bug.
- **cove-144 R2**: First split verdict — Stella found deeper edge case.
- **cove-145**: Vega failed (no output) — first failure since 5-run clean streak.
