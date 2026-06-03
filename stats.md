# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 13 | ~3m | 13/13 (100%) | Most thorough. Reproduced migration bug with SQLite test (cove-144). Runs local tests. |
| 🌠 Nova | claude-opus-4.7 | 13 | ~2m | 13/13 (100%) | Consistently strongest. Best at tracing failure paths and architectural edge cases. |
| 💫 Vega | gemini-3.1-pro-preview | 13 | ~1.5m | 9/13 (69%) | 4 consecutive clean runs. Calibration good — ❌ for data-loss is defensible. Fastest. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1 | ⚠️ Needs Changes |

## Milestones
- **cove-144**: First PR where all 3 reviewers caught a genuine data-loss bug. Validates multi-model approach.
