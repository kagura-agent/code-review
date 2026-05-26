# Reviewer Performance Stats

> Auto-updated by reflection step. Tracks cross-run patterns.

## Reviewer Accuracy (vs human ground truth)

| Reviewer | Runs | True Positives | False Positives | Missed (human caught) | Accuracy |
|----------|------|---------------|-----------------|----------------------|----------|
| 🌟 Stella | 1 | — | — | 1 (CORS preflight) | pending ground truth |
| 🌠 Nova | 1 | — | — | 0 | pending ground truth |
| 💫 Vega | 1 | — | — | 1 (CORS preflight) | pending ground truth |

## Reviewer Strengths

- **Nova**: Deep investigation — fetches source files beyond the diff, cross-references route definitions. Strongest on security/architecture. Slowest (68s) but highest value.
- **Stella**: Clean structured output, catches dead code paths. Missed CORS. Mid speed (138s).
- **Vega**: Fastest (41s), adequate but surface-level. Doesn't dig beyond the diff.

## Prompt Evolution History

| # | Date | What Changed | Trigger |
|---|------|-------------|---------|
| 1 | 2026-05-26 | Added CORS/preflight + route ordering to Security dimension | cove#96: Nova caught CORS preflight 401 that others missed |

## Meta-Evolution Log

_Changes to the review process itself (workflow, reflection, tracking, stats)._

| Date | What Changed | Why |
|------|-------------|-----|
| 2026-05-26 | Initial setup | — |
| 2026-05-26 | First run — established reviewer strength baselines | cove#96 |
