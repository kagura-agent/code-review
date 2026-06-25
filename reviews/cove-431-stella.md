# Code Review: PR #431 — ci: notify #cove-dev on Luna's PR approval

**Reviewer:** 🌟 Stella  
**Date:** 2026-06-25  
**PR:** https://github.com/kagura-agent/cove/pull/431  
**Rating:** ✅ Ready

---

## Summary

Two CI workflow changes:
1. **New `notify-approve.yml`** — sends a webhook notification to #cove-dev when Luna (daniyuu) approves a PR.
2. **Fix `deploy-staging.yml`** — adds `continue-on-error: true` to the notify step + replaces broken bash parameter expansion with `head -1` for truncating multiline commit messages.

Pure CI change, no business logic affected. Well-structured and follows secure patterns.

---

## Security Analysis

### Secrets Handling ✅
- `COVE_DEV_WEBHOOK_URL` is stored in GitHub Secrets and referenced via `${{ secrets.COVE_DEV_WEBHOOK_URL }}`.
- Never logged or echoed to output.
- No hardcoded URLs or tokens.

### Shell Injection Risk ✅ (Safe)
- **Critical pattern check**: `${{ github.event.pull_request.title }}` is assigned to an **env var** (`PR_TITLE`), NOT interpolated directly in the `run:` block. This is the GitHub-recommended safe pattern.
- The `MSG` variable is then passed to `jq -nc --arg content "$MSG"` which properly escapes all special characters for JSON output.
- A malicious PR title like `"; curl attacker.com; echo "` would be safely contained as a shell variable value and then JSON-escaped by jq.
- **Verdict**: No injection vector exists in either workflow.

---

## Correctness Analysis

### Workflow Trigger (notify-approve.yml) ✅
- `pull_request_review` with `types: [submitted]` fires on every review submission.
- The `if` condition filters to: `state == 'approved'` AND `user.login == 'daniyuu'`.
- GitHub normalizes the `login` field, so case-sensitivity is not a practical concern.
- This correctly ignores comment-only reviews and change-requests.

### `head -1` Fix (deploy-staging.yml) ✅
- **Old**: `${PR_TITLE%$'\n'*}` — bash parameter expansion that attempts to strip from first newline. This fails silently in some shell contexts (especially when `$'\n'` isn't treated as a literal newline in the pattern).
- **New**: `FIRST_LINE=$(echo "$PR_TITLE" | head -1)` — portable, clear, correct.
- Applied only in the `else` branch (push events where `PR_TITLE` falls back to `github.event.head_commit.message`, which can be multiline from squash merges). The `if` branch handles PR events where titles are always single-line. Logic is correct.

### Edge Cases
- Empty commit message → `head -1` returns empty → MSG = "✅ Deployed:  (abcdef1)" — acceptable, non-breaking.
- Title with special shell chars → safely contained in variable + jq-escaped. Fine.

---

## Reliability Analysis

### `continue-on-error: true` on deploy-staging ✅
- Appropriate. A notification failure should not mark a successful deploy as failed.
- This was the root cause of the original issue (curl exit 22 from multiline JSON payload → step failure → whole job marked failed even though deploy succeeded).

### Webhook failure handling in notify-approve.yml ⚡ (Suggestion)
- If curl fails (webhook down, network issue), the workflow run will be marked as failed.
- Since this is a standalone notification workflow (doesn't block merges or other jobs), a failed run is cosmetic noise but not harmful.
- The empty-URL guard (`if [ -z "$WEBHOOK_URL" ]`) is a nice touch — prevents cryptic curl errors if the secret isn't configured.

### No retry logic — acceptable for non-critical notifications.

---

## Suggestions (Non-blocking)

### 1. Add `continue-on-error: true` to notify-approve.yml step
```yaml
      - name: Send approval notification to Cove
        continue-on-error: true
        env:
```
**Rationale**: Prevents noisy red ❌ on the repo's Actions tab if the webhook is temporarily down. Since this is purely informational, a silent failure is preferable.

### 2. Consider `--max-time` on curl
```bash
curl -sfS --max-time 10 -X POST "$WEBHOOK_URL" ...
```
**Rationale**: Prevents the job from hanging if the webhook endpoint is slow/unresponsive. Default curl timeout is quite long.

### 3. Minor: `username` field in payload
```json
'{content: $content, username: "GitHub"}'
```
The `username` override works for Discord-style webhooks. If Cove's webhook doesn't support it, it'll just be ignored — no issue. But confirm it behaves as expected.

---

## File-by-File

| File | Verdict | Notes |
|------|---------|-------|
| `.github/workflows/notify-approve.yml` | ✅ | Clean, secure, well-guarded |
| `.github/workflows/deploy-staging.yml` | ✅ | Correct fix for multiline issue |

---

## Final Verdict: ✅ Ready

This is a clean, well-written CI change. Security patterns are correct (env vars + jq for dynamic content), the fix addresses the real root cause, and the new workflow is appropriately scoped. The suggestions above are minor quality-of-life improvements, not blockers.

Approve.
