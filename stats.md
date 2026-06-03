# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 12 | ~3m | 12/12 (100%) | Thorough, runs build+test locally. Fewer unique findings than Nova. |
| 🌠 Nova | claude-opus-4.7 | 12 | ~2m | 12/12 (100%) | Consistently strongest. Best at behavioral changes, architectural edge cases, constant drift. |
| 💫 Vega | gemini-3.1-pro-preview | 12 | ~1.5m | 8/12 (67%) | R1-R3 (cove-96): provider fail. R5 (cove-124): false positive. cove-125 R1: over-severity. Improving — 3 consecutive clean runs. Fastest. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready |
