# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 17 | ~3m | 17/17 (100%) | Most thorough. Runs tests locally. Catches rendering bugs others miss. |
| 🌠 Nova | claude-opus-4.7 | 17 | ~2m | 17/17 (100%) | Consistently strongest. Best at logic analysis and UX implications. |
| 💫 Vega | gemini-3.1-pro-preview | 17 | ~1m | 11/17 (65%) | 2 consecutive failures (cove-145 R1 + cove-156). Needs investigation. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready (w/ caveat) |
| #145 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #156 | cove | 2026-06-03 | R1 | ⚠️ Needs Changes |

## Milestones
- **cove-144 R1**: First PR where all 3 caught a genuine data-loss bug.
- **cove-144 R2**: First split verdict — Stella found deeper edge case.
- **cove-156**: Both valid reviewers caught same rendering bug (p→span). Vega 2nd consecutive fail.
