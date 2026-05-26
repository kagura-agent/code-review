# Review: kagura-agent/cove#96
Date: 2026-05-26T10:20+08:00
Reviewers: Stella / Nova / Vega

## Verdicts
- Stella: ✅ Ready
- Nova: ⚠️ Needs Changes
- Vega: ✅ Ready

## Consensus Findings
- Double user resolution (middleware resolves then discards, handlers resolve again) — all 3
- Health endpoint tested with auth but is public — all 3
- PUBLIC_PATHS exact match won't scale for future auth sub-routes — all 3
- Dead branch in /api/v10/users/@me (middleware guarantees auth) — Nova + Stella

## Divergences
- **CORS preflight (Nova only)**: Nova flagged OPTIONS requests getting 401'd. This is a real issue if frontend is cross-origin (OAuth flow suggests it is). Stella and Vega missed this entirely. Nova was correct — this is the highest-value finding.
- **PUBLIC_PATHS /api/auth/me stale entry (Nova only)**: Nova checked the actual auth route file and found the route doesn't exist. Good investigative depth.
- **Missing Bearer token negative test (Stella only)**: Minor gap, valid catch.
- **Protected read endpoint 401 test (Vega only)**: Valid coverage suggestion.

## Prompt Blind Spots
- The default review standard mentions "no injection vulnerabilities" but doesn't call out **CORS/preflight handling** as a security dimension. For web APIs with auth middleware, CORS interaction is critical and should be in the prompt.
- No prompt guidance on checking **route registration ordering** as a correctness concern (Hono's middleware applies to routes registered after it).

## Reviewer Notes
- **Nova was strongest this round**: found 2 unique critical/important issues (CORS preflight, stale PUBLIC_PATHS entry) that others missed. Also dug deeper by fetching actual route source code to verify claims. Most thorough.
- **Stella was solid**: clean structure, caught the dead branch, but missed CORS.
- **Vega was adequate**: correct but surface-level, no deep investigation of the codebase beyond the diff.
- **Speed**: Vega 41s, Nova 68s, Stella 138s. Vega fastest but shallowest.
