# PR #156 — feat(client): Markdown rendering in chat messages

**Repo**: kagura-agent/cove
**Reviewed**: 2026-06-03
**Files**: 5 (+938/-6)
**FlowForge**: #3433 (R1), #3440 (R2)

## Round 1 (react-markdown)
| Reviewer | Verdict |
|----------|---------|
| Stella | ⚠️ Needs Changes |
| Nova | ⚠️ Needs Changes |
| Vega | ❌ Failed (timeout) |

Findings: p→span collapse, nested pre tags, no syntax highlighting claim.

## Round 2 (custom parser rewrite)
| Reviewer | Verdict |
|----------|---------|
| Stella | ⚠️ Needs Changes |
| Nova | ⚠️ Needs Changes |
| Vega | ⚠️ Needs Changes |

Findings: XSS via javascript: links (3/3), paragraph collapse persists (3/3), block-in-span invalid HTML (2/3).

## Overall: ⚠️ Needs Changes (R2)

## Key Milestones
- **Vega recovered!** Prompt fix ("do not use sessions_yield") worked. First successful Vega review after 2 consecutive failures.
- **3/3 consensus on XSS** — all three independently found the javascript: link vulnerability.
- PR rewrote from react-markdown to custom parser between R1 and R2 — but core issues persisted.

## Reviewer Assessment
- **Stella**: 18/18 (100%). Found block-in-span + unused lang + table cell inline. Thorough.
- **Nova**: 18/18 (100%). XSS analysis most detailed. Good architectural suggestions.
- **Vega**: 12/18 (67%). Back from 2 consecutive fails. Clean review with good fix suggestion for paragraph collapse.
