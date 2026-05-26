# Review: kagura-agent/cove#96 — Round 3 (comment mode)

**PR**: Require authentication on all API endpoints
**Date**: 2026-05-26
**Mode**: comment (inline comments on PR)
**Instance**: FlowForge #2846

## Reviewers
| Reviewer | Model | Verdict | Runtime | Notes |
|----------|-------|---------|---------|-------|
| 🌟 Stella | default-llm-sg/gpt-5.5 | ✅ Ready | 2m41s | 2 suggestions, 3 positives |
| 🌠 Nova | default-llm-sg/claude-opus-4.7 | ✅ Ready | 43s | 6 suggestions, 5 positives |
| 💫 Vega | default-llm-sg/gemini-3.1-pro-preview | ❌ Failed | 2s | Provider config: missing maxTokens |

## Consensus
✅ Ready — no critical issues found (post-update PR fixed CORS preflight)

## Findings Posted
6 inline comments on PR:
1. tsconfig.tsbuildinfo should be gitignored [Stella]
2. PUBLIC_PATHS overlaps route ordering — add comment [Nova]
3. CORS middleware not visible in createApp [Nova]
4. Typed ContextVariableMap for botUser [Nova]
5. authGet helper positive [Nova]
6. Add GET 401 test coverage [Stella+Nova]

## Issues Encountered
- Vega failed 3 consecutive rounds due to `maxTokens` not set for Gemini models on `default-llm-sg` provider
- Root cause: Anthropic Messages transport requires positive maxTokens value
- Fix: Added maxTokens=65536 + contextWindow=1048576 for all Gemini models (official Google specs)
- Also discovered 12 other models with wrong maxTokens/contextWindow across 3 providers — all corrected

## Ground Truth

**Human reviewer**: daniyuu — APPROVED (no comments)
**PR outcome**: MERGED 2026-05-26T11:00:07Z
**Verdict accuracy**: ✅ Our "ready" matched human approval. No missed issues.

## Process Notes
- FlowForge `advance` without `-w` flag defaults to wrong workflow when multiple active — need to always specify `-w code-review`
- Got distracted debugging provider config mid-flow, should have noted FlowForge state and come back
