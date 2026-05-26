# Code Review Service — Reviewer Stats

## Per-Reviewer Performance

| Reviewer | Model | Reviews | Avg Runtime | Reliability | Notes |
|----------|-------|---------|-------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 3 | ~2m30s | 3/3 (100%) | Thorough, catches build artifacts. Slower but consistent. |
| 🌠 Nova | claude-opus-4.7 | 3 | ~40s | 3/3 (100%) | Fast, detailed suggestions, good security sense. |
| 💫 Vega | gemini-3.1-pro-preview | 3 | N/A | 0/3 (0%) | Failed all 3 rounds. R1-R2: provider issue (0 tokens). R3: missing maxTokens config. Now fixed — pending verification. |

## Review History

| PR | Repo | Date | Mode | Verdict | Instance |
|----|------|------|------|---------|----------|
| #96 | kagura-agent/cove | 2026-05-26 | report | ⚠️ Needs Changes | #2844 |
| #96 | kagura-agent/cove | 2026-05-26 | report (r2) | ✅ Ready | #2844 |
| #96 | kagura-agent/cove | 2026-05-26 | comment (r3) | ✅ Ready | #2846 |
