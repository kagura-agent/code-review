# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 9 | ~5m | 9/9 (100%) | Slowest but most thorough. Runs local tests. Found final-edit bug (R5). |
| 🌠 Nova | claude-opus-4.7 | 9 | ~2m | 9/9 (100%) | Fast, consistent, good security sense. |
| 💫 Vega | gemini-3.1-pro-preview | 9 | ~1.5m | 5/9 (56%) | R1-R3 (cove-96): provider fail. R5: false positive. R6: clean after prompt fix. Fastest when working. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
