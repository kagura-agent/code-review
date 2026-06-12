# PR #337 Review Run Record

**Date:** 2026-06-12
**PR:** kagura-agent/cove#337
**Title:** feat: @mention with autocomplete and highlight (closes #332)
**Scope:** 7 files, +278/-12
**Round:** 1

## Verdict: ⚠️ Needs Changes (3/3)

## Critical Issues
1. Enter blocked when no autocomplete matches (all 3)
2. cursorPos stale on caret moves (Stella + Nova)
3. Mention resolution leaks non-guild users (Stella)
4. Edit path doesn't refresh mentions (Stella)
5. Unrelated workflow change (all 3)

## Reviewer Performance

| Reviewer | Verdict | Unique Finds |
|----------|---------|-------------|
| 🌟 Stella | ⚠️ | Guild scoping leak, edit path missing resolveMentions |
| 🌠 Nova | ⚠️ | Most thorough — cursorPos, listener churn, mention count cap, click-outside, escape re-trigger |
| 💫 Vega | ⚠️ | Escape re-trigger, regex concern |
