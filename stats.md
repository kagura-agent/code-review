# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 8 | ~5m | 8/8 (100%) | Slowest but most thorough. Runs local tests. Found real final-edit bug in R5. High token usage (~1M). |
| 🌠 Nova | claude-opus-4.7 | 8 | ~2m | 8/8 (100%) | Fast, consistent, good security sense. |
| 💫 Vega | gemini-3.1-pro-preview | 8 | ~1.5m | 4/8 (50%) | R1-R3 (cove-96): provider failures. R5: false positive ❌ from stale PR description. Fastest when working but calibration issues. |

## Review History

| PR | Repo | Date | Mode | Verdict | Notes |
|----|------|------|------|---------|-------|
| #96 | cove | 2026-05-26 | report | ⚠️ Needs Changes | Vega failed (provider issue) |
| #96 | cove | 2026-05-26 | report (r2) | ✅ Ready | Vega failed again |
| #96 | cove | 2026-05-26 | comment (r3) | ✅ Ready | Vega failed (maxTokens) |
| #124 | cove | 2026-06-02 | report (R1) | ⚠️ Needs Changes | Wrong model IDs |
| #124 | cove | 2026-06-02 | report (R2) | ✅ Ready | Model IDs fixed |
| #124 | cove | 2026-06-02 | report (R3) | ✅ Ready | R2 suggestions addressed |
| #124 | cove | 2026-06-02 | report (R4) | ✅ Ready | First FlowForge review |
| #124 | cove | 2026-06-02 | report (R5) | ⚠️ Needs Changes | Final edit fallback missing; Vega false positive |
