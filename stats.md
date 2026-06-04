# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 28 | ~3m | 28/28 (100%) | Runs build+test. Catches edge cases. Deepest on migration/DB issues. |
| 🌠 Nova | claude-opus-4.7 | 28 | ~2m | 28/28 (100%) | Strongest on security + architecture. Most calibrated severity. |
| 💫 Vega | gemini-3.1-pro-preview | 28 | ~1m | 21/28 (75%) | R2 #168 oversized (fixed with output constraints). IDOR framing clearest in R3. |

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
| #167 | cove | 2026-06-04 | R1-R2 | ✅ Ready |
| #168 | cove | 2026-06-04 | R1-R3 | ⚠️ In progress |
