# Code Review: PR #431 — ci: notify #cove-dev on Luna's PR approval

**Reviewer:** 💫 Vega  
**Repo:** kagura-agent/cove  
**PR:** #431  
**Date:** 2026-06-25  

---

## Rating: ✅ Ready

This is a clean, well-written CI change. The author has made good security choices throughout.

---

## File: `.github/workflows/notify-approve.yml` (new)

### Security ✅

| Concern | Assessment |
|---------|-----------|
| Webhook URL | Stored in `secrets.COVE_DEV_WEBHOOK_URL` — properly secured, not hardcoded |
| Secret exposure in logs | `curl -sfS` — `-s` suppresses progress but `-S` shows errors. The URL is passed via `$WEBHOOK_URL` env var, not interpolated in the `run:` string, so it won't leak in workflow logs |
| Shell injection via `${{ }}` | **No issue.** PR_TITLE and PR_NUM are passed through `env:` block and referenced as `$PR_TITLE` / `$PR_NUM` shell variables — NOT directly interpolated into the `run:` block. This is the correct pattern to prevent script injection |

### Correctness ✅

| Item | Assessment |
|------|-----------|
| Trigger `pull_request_review: types: [submitted]` | Correct. Fires on review submission |
| Job condition `github.event.review.state == 'approved'` | Correct. Filters to only approved reviews |
| User filter `github.event.review.user.login == 'daniyuu'` | Correct. Only fires for Luna's approvals |
| JSON payload construction | Uses `jq -nc --arg content "$MSG"` — this is **excellent**. Properly escapes special characters (quotes, newlines, unicode) in the message. No injection risk |

### Reliability

| Item | Assessment |
|------|-----------|
| Empty webhook guard | `if [ -z "$WEBHOOK_URL" ]` with early exit and `::warning::` annotation — good defensive coding |
| No `continue-on-error` | Acceptable. If the notification fails, the workflow run shows as failed, which is visible but doesn't block anything (this workflow has no other downstream jobs) |
| Concurrent approvals | No issue. Each review event triggers independently. No shared state or race conditions |

### Suggestions (non-blocking)

1. **Minor:** Consider adding `continue-on-error: true` on the curl step for consistency with `deploy-staging.yml`. A webhook outage would mark the workflow run as failed, which may create noise in the Actions tab. However, this is also an argument *for* keeping it — you'd notice if the webhook is broken.

2. **Minor:** The `username: "GitHub"` field in the payload is a nice touch for Cove/Discord-style display.

---

## File: `.github/workflows/deploy-staging.yml` (modified)

### Change 1: `continue-on-error: true`

**Assessment: ✅ Good fix.**

The notification step is non-critical. If the webhook endpoint is down or returns an error, the deployment itself already succeeded. Adding `continue-on-error: true` prevents a successful deploy from being marked as failed due to notification issues.

### Change 2: `head -1` for commit message truncation

**Assessment: ✅ Correct fix.**

| Before | After |
|--------|-------|
| `${PR_TITLE%$'\n'*}` — Bash parameter expansion to strip after first newline | `echo "$PR_TITLE" \| head -1` — Takes first line |

**Analysis:**
- The old `${PR_TITLE%$'\n'*}` pattern is unreliable in GitHub Actions' shell context. The `$'\n'` ANSI-C quoting inside parameter expansion doesn't always work as expected, especially with multi-line strings from squash merge commits.
- `head -1` is simple, portable, and unambiguous.
- Edge case: if `PR_TITLE` is empty, `head -1` outputs nothing, resulting in `"✅ Deployed:  (abc1234)"` — acceptable.

### Existing curl pattern in deploy-staging.yml

I note the existing notification in `deploy-staging.yml` still uses direct shell interpolation for the curl JSON:
```bash
curl -sf -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"${MSG}\", ...}"
```

This is **pre-existing** and not introduced by this PR, but it's worth noting that if `MSG` contains double quotes or backslashes, the JSON would break (though it wouldn't cause injection since the values come from controlled formatting). The new `notify-approve.yml` correctly uses `jq` for this — an improvement the deploy workflow could adopt in a future cleanup.

---

## Summary

| Category | Verdict |
|----------|---------|
| Security | ✅ No issues. Secrets in GitHub Secrets, env-var indirection prevents injection, `jq` for safe JSON construction |
| Correctness | ✅ Triggers and filters are correct. `head -1` is a reliable fix |
| Reliability | ✅ Appropriate error handling. No race conditions |
| Shell injection risk | ✅ None. PR title passed via `env:` (not `${{ }}` in `run:`), and `jq --arg` safely escapes |
| Scope | ✅ Pure CI, minimal and focused |

**Final verdict: ✅ Ready to merge.**
