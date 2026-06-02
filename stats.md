# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 7 | ~4m | 7/7 (100%) | Slowest but most thorough. Runs local tests (pnpm test/check/build). High token usage (~1M). |
| 🌠 Nova | claude-opus-4.7 | 7 | ~2m | 7/7 (100%) | Fast, detailed suggestions, good security sense. Consistent. |
| 💫 Vega | gemini-3.1-pro-preview | 7 | ~1.5m | 4/7 (57%) | R1-R3 (cove-96) failed due to provider/config issues. Fixed since cove-124 R2 — 4/4 since fix. Fastest. |

## Review History

| PR | Repo | Date | Mode | Verdict | Notes |
|----|------|------|------|---------|-------|
| #96 | kagura-agent/cove | 2026-05-26 | report | ⚠️ Needs Changes | Vega failed (provider issue) |
| #96 | kagura-agent/cove | 2026-05-26 | report (r2) | ✅ Ready | Vega failed again |
| #96 | kagura-agent/cove | 2026-05-26 | comment (r3) | ✅ Ready | Vega failed (maxTokens) |
| #124 | kagura-agent/cove | 2026-06-02 | report (R1) | ⚠️ Needs Changes | Wrong model IDs → Stella/Vega fallback to claude-opus-4.6 |
| #124 | kagura-agent/cove | 2026-06-02 | report (R2) | ✅ Ready | Model IDs fixed, all 3 models correct |
| #124 | kagura-agent/cove | 2026-06-02 | report (R3) | ✅ Ready | R2 suggestions addressed |
| #124 | kagura-agent/cove | 2026-06-02 | report (R4) | ✅ Ready | First FlowForge-driven review |
