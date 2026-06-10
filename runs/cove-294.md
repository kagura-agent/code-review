# Run Record: cove#294

**Date:** 2026-06-10
**PR:** feat: add webhook support for cross-channel messaging
**Verdict:** ❌ Major Issues
**Round:** 1

## Consensus Critical (2+ reviewers)
1. FK violation: `createFromWebhook` inserts webhookId into `messages.sender` → FK crash (Stella + Vega)
2. No rate limiting on unauthenticated execute endpoint (3/3)
3. `username`/`avatar_url` overrides unvalidated on public endpoint (Stella + Nova)
4. Webhook messages lose identity on reload — `bot: false`, avatar null (Stella + Vega)
5. No tests for any new code path (Stella + Nova)

## Nova Unique Critical
6. Token exfiltration: list/get endpoints return raw `token` to any guild member
7. Webhook creation has no permission check beyond guild membership

## Suggestions
- Dead `dispatcher` param in `webhookRoutes` (Nova)
- UUID tokens vs randomBytes for visual non-secret distinction (Nova)
- Transaction for execute + updateLastMessageId (Stella)
- Missing index on `webhooks(guild_id)` (Stella)

## Reviewer Assessment
| Reviewer | Rating | Unique Finds | Notes |
|----------|--------|-------------|-------|
| Stella | ❌ | 2 | Caught FK violation, transaction gap, missing index |
| Nova | ⚠️ | 7 | Most thorough — token leak is a critical unique find, excellent security depth |
| Vega | ❌ | 0 | Crashed but wrote review file — FK + avatar data loss. No unique finds this round |

## Blind Spots
- Nova's token exfiltration finding is critical and neither Stella nor Vega caught it — this is a "security model design" dimension, not just code-level. Worth monitoring if this pattern recurs.
- None of the reviewers checked whether `parseJsonBody` has a max body size limit — defense in depth for the public endpoint.

## Prompt Evolution
- No prompt change needed. The "Key Security Concerns" section I added to this PR's reviewer prompt (token exposure, rate limiting, content validation) directly led to good coverage. Continue adding per-PR security hints.

## Process
- Vega crashed (3m29s runtime, 116k tokens) but review file was saved — FlowForge handled gracefully.
- Plan-review correctly categorized 7/8 files as 🔴 High Risk (all server-side).

---

## Round 2

**Verdict:** ⚠️ Needs Changes

### R1 Issue Status
| # | Issue | Status |
|---|-------|--------|
| 1 | FK violation | ✅ Fixed |
| 2 | No rate limiting | ⚠️ Partial — limiter exists but pre-auth DoS + memory leak |
| 3 | Validation | ⚠️ Partial — length checked, no URL scheme |
| 4 | Token leak | ✅ Fixed |
| 5 | Identity on reload | ⚠️ Partial — bot:true restored, avatar still null |
| 6 | No tests | ✅ Fixed — 213 lines |
| 7 | Permission model | ❌ Not fixed — ESCALATED |

### New Findings
- Client URL shows `/undefined` after reload (3/3 consensus)
- Rate limiter pre-auth bucket filling → DoS vector (2/3)
- ON DELETE SET NULL erases webhook message identity (2/3)

### Reviewer Assessment R2
| Reviewer | Rating | Notes |
|----------|--------|-------|
| Stella | ❌ | Rate limiter DoS analysis, permission escalation |
| Nova | ⚠️ | Most detailed — client URL regression, bucket leak, scheme validation |
| Vega | ❌ | Permission + client URL, concise |
