# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 23 | ~3m | 23/23 (100%) | Runs build+test. Catches compile-time issues. |
| 🌠 Nova | claude-opus-4.7 | 23 | ~2m | 23/23 (100%) | Strongest on security + architecture. |
| 💫 Vega | gemini-3.1-pro-preview | 23 | ~1m | 17/23 (74%) | 6 consecutive clean runs after prompt fix. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #145 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #155 | cove | 2026-06-03 | R1 | ✅ Ready |
| #156 | cove | 2026-06-03 | R1-R3 | ✅ Ready |
| #165 | cove | 2026-06-04 | R1-R2 | ✅ Ready |
| #166 | cove | 2026-06-04 | R1 | ✅ Ready |
