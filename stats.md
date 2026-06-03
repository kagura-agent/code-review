# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 11 | ~4m | 11/11 (100%) | Most thorough. Runs local tests. Good at accessibility findings. |
| 🌠 Nova | claude-opus-4.7 | 11 | ~2m | 11/11 (100%) | Fast, consistent. Strongest at visual/interaction edge cases (avatar contrast, size regressions). |
| 💫 Vega | gemini-3.1-pro-preview | 11 | ~1.5m | 7/11 (64%) | R1-R3 (cove-96): provider fail. R5 (cove-124): false positive. cove-125 R1: over-severity (⚠️ for non-blocking). R2: corrected to ✅. Fastest when working. Calibration improving. |

## Review History

| PR | Repo | Date | Rounds | Final Verdict |
|----|------|------|--------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready |
