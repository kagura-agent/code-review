# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 18 | ~3m | 18/18 (100%) | Most thorough. Runs tests locally. Catches rendering/structural bugs. |
| 🌠 Nova | claude-opus-4.7 | 18 | ~2m | 18/18 (100%) | Consistently strongest. Best at security (XSS), architecture, breaking changes. |
| 💫 Vega | gemini-3.1-pro-preview | 18 | ~1m | 12/18 (67%) | Recovered after prompt fix (no sessions_yield). Good fix suggestions when working. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready (w/ caveat) |
| #145 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #156 | cove | 2026-06-03 | R1-R2 | ⚠️ Needs Changes |

## Milestones
- **cove-144 R1**: First PR where all 3 caught a genuine data-loss bug.
- **cove-156 R2**: 3/3 caught XSS vulnerability. Vega recovered after prompt fix.
