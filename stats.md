# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 14 | ~3m | 14/14 (100%) | Most thorough. Reproduces bugs with real tests. Found R2 recovery edge case others missed. |
| 🌠 Nova | claude-opus-4.7 | 14 | ~2m | 14/14 (100%) | Consistently strongest on architecture. Best at tracing full code paths. |
| 💫 Vega | gemini-3.1-pro-preview | 14 | ~1m | 10/14 (71%) | 5 consecutive clean runs. Fastest. Calibration steadily improving. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready (w/ caveat) |

## Milestones
- **cove-144 R1**: First PR where all 3 reviewers caught a genuine data-loss bug.
- **cove-144 R2**: First split verdict — Stella found deeper edge case others missed. Value of model diversity.
