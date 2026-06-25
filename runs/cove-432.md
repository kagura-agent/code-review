# Run Record: cove-432

**PR:** kagura-agent/cove#432
**Title:** feat: server-level roles and permissions (#430)
**Date:** 2026-06-25
**Round:** 1
**Verdict:** ⚠️ Needs Changes (Stella ⚠️, Nova ❌, Vega ⚠️)

## Critical Findings

1. **Bulk Position Privilege Escalation** (Nova + Vega, verified) — `PATCH /guilds/:guildId/roles` only checks target position, not current. Allows demoting high-privilege roles → assign to self → full escalation.
2. **Dispatcher Fail-Open** (3/3, verified) — `broadcastToGuildWithChannelFilter` skips permission check when repos are null.
3. **Cross-Guild Role Access** (3/3, verified) — `getById` has no guild_id filter.

## Reviewer Performance

| Reviewer | Verdict | Criticals Found | Unique Finds |
|----------|---------|-----------------|--------------|
| 🌟 Stella | ⚠️ | 3 (test-focused) | Missing security tests as Critical, old helpers not removed, redundant double permission computation |
| 🌠 Nova | ❌ | 2 (escalation-focused) | Bulk position escalation (C1), detailed attack scenario, comprehensive route coverage audit table |
| 💫 Vega | ⚠️ | 1 | Same bulk position (C1), migration test description mismatch |

## Key Observations

- **Nova found the most impactful security issue** (bulk position escalation) with a detailed attack scenario. Stella missed this entirely — focused on test coverage gaps instead of actual vulnerability analysis.
- **Stella's test-focused approach**: All 3 Criticals were about missing tests, not runtime bugs. Valid per review standard ("Security/auth paths without tests = Critical"), but less impactful than finding the actual escalation vector.
- **Vega** found the same escalation as Nova but was more concise. Also the only one at 100% finding verification.
- **3/3 consensus** on dispatcher fail-open and cross-guild access — high confidence findings.

## Prompt Evolution

- Consider adding to prompt: "For permission systems, trace specific attack scenarios (privilege escalation, bypass) rather than only checking test coverage. Finding the vulnerability is more valuable than noting the test is missing."
- The AI failure modes checklist helped: "plausible-but-wrong logic" applies directly to the bulk position check.

## Process Notes

- Large PR (26 files, +1163) but reviewers handled it well (4-8 min each)
- Plan-review.sh correctly categorized 19/28 files as high-risk
- Manual verification of top findings against cloned repo was essential — confirmed all 3 key issues
