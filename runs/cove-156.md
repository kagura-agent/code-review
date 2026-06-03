# PR #156 — feat(client): Markdown rendering in chat messages

**Repo**: kagura-agent/cove
**Reviewed**: 2026-06-03
**Files**: 5 (+938/-6)
**FlowForge**: #3433

## Verdicts
| Reviewer | Model | Verdict |
|----------|-------|---------|
| Stella | GPT-5.5 | ⚠️ Needs Changes |
| Nova | Claude Opus 4.7 | ⚠️ Needs Changes |
| Vega | Gemini 3.1 Pro | ❌ Failed (timeout) |

## Overall: ⚠️ Needs Changes

## Key Findings
1. **`p` → `<span>` collapses multi-paragraph messages** (Stella+Nova) — real rendering bug
2. **Nested `<pre><pre>` in fenced code blocks** (Stella) — double wrapping
3. **No-language code blocks lose block styling** (Stella) — falls back to inline
4. **No actual syntax highlighting** (Stella+Nova) — PR description overclaims

## Reviewer Assessment
- **Stella**: Ran build+lint. Found code block bugs (nested pre, no-language fallback) that Nova missed. Also caught table overflow and image sizing risks. Thorough.
- **Nova**: Found the paragraph collapse bug with clear reproduction. Good UX observations (edited marker placement, React.memo). Strongest analysis of the rendering logic.
- **Vega**: **Failed again** — timeout, 2nd consecutive failure. Reliability drops to 11/17 (65%).

## Process Notes
- Vega's consecutive failures are concerning. May need to investigate — is it the model, the proxy, or the diff size?
- Both valid reviewers found the same critical (p→span) independently — high confidence it's a real bug.
