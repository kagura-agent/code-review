# Code Review: PR #431 — ci: notify #cove-dev on Luna's PR approval

**Reviewer:** 🌠 Nova  
**Date:** 2026-06-25  
**PR:** https://github.com/kagura-agent/cove/pull/431  
**Verdict:** ✅ Ready

---

## Summary

Two CI workflow changes:
1. **New `notify-approve.yml`** — Sends a webhook notification to #cove-dev when Luna (daniyuu) approves a PR.
2. **Fix `deploy-staging.yml` Notify step** — Adds `continue-on-error: true` and fixes multiline commit message truncation with `head -1`.

Pure CI/notification plumbing, no business logic changes.

---

## Security Analysis

### Secrets Handling — ✅ PASS

| Check | Status |
|-------|--------|
| Webhook URL stored in GitHub Secrets (`COVE_DEV_WEBHOOK_URL`) | ✅ |
| Secret passed via `env:` block (not echoed in logs) | ✅ |
| No hardcoded URLs or tokens | ✅ |
| No `${{ secrets.* }}` directly in `run:` blocks | ✅ |

### Shell Injection — ✅ PASS

Both workflows correctly use the safe pattern:
1. Dynamic values (`PR_TITLE`, `PR_NUM`) are set via `env:` blocks from `${{ }}` expressions
2. Referenced as shell variables (`$PR_TITLE`, `$PR_NUM`) in `run:` — not directly interpolated by Actions
3. JSON payload constructed with `jq -nc --arg content "$MSG"` — properly escapes special characters

This means a PR title like `"; curl http://evil.com #` would be safely handled:
- It becomes a shell variable (no injection into the shell)
- `jq --arg` escapes it for JSON (no JSON injection)

**No injection vector exists in this PR.**

---

## Correctness Analysis

### Trigger & Filter (`notify-approve.yml`) — ✅ CORRECT

```yaml
on:
  pull_request_review:
    types: [submitted]
jobs:
  notify:
    if: github.event.review.state == 'approved' && github.event.review.user.login == 'daniyuu'
```

- `pull_request_review` with `types: [submitted]` fires on every review submission (comment, approve, request changes).
- The `if:` condition correctly narrows to only `approved` state AND only the `daniyuu` user.
- `github.event.review.state` returns lowercase `'approved'` — matches correctly.
- `github.event.review.user.login` is the reviewer's login — correct field.

### `head -1` Fix (`deploy-staging.yml`) — ✅ CORRECT

**Before:** `${PR_TITLE%$'\n'*}` — Bash parameter expansion to strip after newline.  
**After:** `FIRST_LINE=$(echo "$PR_TITLE" | head -1)`

The old approach was fragile because `$'\n'` in pattern matching within `${..%..}` can behave inconsistently across shells/contexts. The `head -1` approach is universally reliable.

Edge cases:
- Empty `PR_TITLE` → empty `FIRST_LINE` → harmless message "✅ Deployed: (abc1234)"
- Single-line title → `head -1` returns it unchanged ✅
- Multi-line squash merge message → correctly takes first line ✅

---

## Reliability Analysis

### `continue-on-error: true` on deploy-staging Notify — ✅ APPROPRIATE

The notification is non-critical. A webhook failure (endpoint down, rate limit, network blip) should never fail an otherwise successful deployment. Good defensive change.

### No `continue-on-error` on `notify-approve.yml` — ⚡ SUGGESTION

The new workflow has no `continue-on-error`. If curl fails (webhook endpoint down), the workflow fails and shows as a red ❌ check on the PR. Since this is purely a notification workflow:
- It won't block merging (unless branch protection requires ALL checks green)
- But it creates visual noise on the PR

**Suggestion:** Add `continue-on-error: true` on the step, or at minimum add it as a future consideration if branch protection could be an issue.

### Empty Webhook Guard — ✅ GOOD

```bash
if [ -z "$WEBHOOK_URL" ]; then echo '::warning::WEBHOOK_URL is empty, skipping'; exit 0; fi
```

Handles the case where the secret isn't configured (e.g., in forks). The `::warning::` annotation is a nice touch for visibility.

### Missing `timeout-minutes` — ⚡ SUGGESTION

Neither the new job nor the step sets a timeout. Default is 6 hours for a job. For a simple curl notification, adding `timeout-minutes: 2` would prevent runaway jobs if something hangs.

---

## Minor Observations

| Item | Note |
|------|------|
| `curl -sfS` flags | `-s` silent, `-f` fail on HTTP error, `-S` show error on failure — good combination |
| `username: "GitHub"` in payload | Nice UX touch — messages appear from "GitHub" in Cove |
| Existing `deploy-staging` curl uses `-sf` (no `-S`) | Minor inconsistency but fine — deploy step now has `continue-on-error` anyway |

---

## Final Verdict

### ✅ Ready to Merge

**Strengths:**
- Correct and safe shell/JSON construction pattern (`env:` → shell vars → `jq --arg`)
- Proper secrets handling
- Good defensive coding (empty webhook guard, `continue-on-error`)
- Clean, minimal diff for the stated purpose

**No blocking issues.** The two suggestions (timeout, continue-on-error on notify-approve) are nice-to-haves for robustness but not required for merge.
