# PR #348 Round 2 Consolidated Review

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

---

## R1 Issue Resolution

| R1 Issue | Status | Notes |
|----------|--------|-------|
| C1: Empty string normalization | ✅ Fixed | Trim + empty→null in PATCH route, tested |
| C2: Control char / ZWS / RTL validation | ✅ Fixed | New `validateDisplayName()` with tests |
| C3: Missing tests | ⚠️ Partial | PATCH tests added (9 cases). Missing: OAuth re-login preservation, resolveMentions |
| C4: Settings hint misleading | ✅ Fixed | Now "Leave empty to use your account name" |
| Stella: toUser() hardcoded null | ✅ Fixed | Now `row.global_name ?? null` |
| Nova: body passthrough | ✅ Fixed | Explicit patch object |
| Vega: OAuth COALESCE overwrites | ✅ Fixed | Re-login no longer touches global_name |
| Vega: validateString rejects null | ✅ Fixed | Confirmed null accepted |
| Nova: findByToken redundant cast | ❌ Not Fixed (nit) | Low-risk style issue |
| Nova: nick chain in MessageItem | ⚠️ TODO added | Consistent within scope, follow-up for nick support |

**R1 critical issues substantially addressed.** Good work on the fixes.

---

## New Issues in R2

### 🔴 Critical — CI webhook shell-injection via PR title (Stella + Nova)

**File:** `.github/workflows/ci.yml`

The new CI failure notification interpolates `${{ github.event.pull_request.title }}` directly into a shell `run:` block inside double quotes. A PR title containing `"`, `$()`, backticks, or `\` will produce malformed JSON, fail the webhook, or execute arbitrary shell commands. Since this step also accesses a secret webhook URL, this is a security-sensitive injection vector reachable by anyone who can open a PR.

**Fix:** Pass title via `env:` block and build JSON with `jq -nc`:
```yaml
env:
  PR_NUM:   ${{ github.event.pull_request.number }}
  PR_TITLE: ${{ github.event.pull_request.title }}
  RUN_URL:  https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}
run: |
  payload=$(jq -nc --arg c "❌ CI failed on PR #$PR_NUM: $PR_TITLE
$RUN_URL" '{content:$c, username:"GitHub CI"}')
  curl -sf -X POST "$COVE_DEV_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload"
```

### 🟡 Suggestion — OAuth `given_name` bypasses `validateDisplayName` (Stella + Nova)

**File:** `packages/server/src/routes/auth.ts`

`googleUser.given_name` is stored directly into `pending_registrations.global_name` without passing through `validateDisplayName`. While Google rarely returns control chars, this is an unvalidated external input path into `global_name`. Sanitize at the boundary for consistency.

### 🟡 Suggestion — Mention map keyed by display name (non-unique) (Stella)

`MentionAutocomplete` passes `global_name || username` to `onSelect()`, and `MessageInput` stores `mentionMapRef` keyed by that display string. If two users share the same display name, the map key collides. Consider keying by user ID or username instead.

---

## Verdict Summary

| Reviewer | R2 Verdict | Key Concern |
|----------|------------|-------------|
| 🌟 Stella | ❌ Major Issues | CI shell injection + partial R1 gaps |
| 🌠 Nova | ⚠️ Needs Changes | CI shell injection (blocker); display-name feature itself is ready |
| 💫 Vega | ✅ Ready | All R1 issues resolved, no new issues found |

### Overall: ⚠️ Needs Changes

The display-name feature itself is in good shape — R1 critical issues were well addressed. The blocker is the **CI webhook shell-injection** (new code in this PR, found by 2/3 reviewers). Fix is ~5 lines.

**Before merge:**
1. **Must:** Fix CI webhook shell injection (use env vars + jq)
2. **Should:** Validate OAuth `given_name` with `validateDisplayName`
3. **Nice:** Add OAuth re-login regression test, fix mention map key collision
