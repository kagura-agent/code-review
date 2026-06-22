# Code Review: PR #413 — fix(ci): shell injection in notification workflows

**Reviewer:** 🌠 Nova
**Repo:** kagura-agent/cove
**Fixes:** #393
**Files:** `.github/workflows/notify-cove.yml`, `.github/workflows/notify-issue-close.yml`, `docs/specs/393-shell-injection-fix.md`

## Verdict: ✅ Ready

---

## 1. Summary

This PR closes a real shell-injection vector in two notification workflows by following GitHub's official hardening guidance: untrusted GitHub event fields (`issue.title`, `pull_request.title`, `label.name`, `assignee.login`, `actor`) are moved out of the `${{ }}` template into `env:` blocks, then read as ordinary shell variables. JSON payloads to Cove webhooks are built with `jq --arg` instead of string concatenation. The fix is small, focused, internally consistent with the linked spec, and directly addresses the failure mode evidenced by issue #392 (backtick-in-title → exit 127). No critical issues found.

## 2. Critical Issues

None. The fix is correct and complete for both workflows in scope.

## 3. Product Impact

- **User-visible behavior:** Notification messages will now render special characters (backticks, `$()`, quotes) as literal text instead of failing or executing — that is the intended improvement.
- **New failure mode (minor):** `curl -s` was changed to `curl -sf` in both workflows. `-f` makes curl exit non-zero on HTTP 4xx/5xx, so a webhook outage will now turn the job red instead of failing silently. This is the better default (loud failures > silent drops), but worth flagging because it's an observable change in CI signal — expect the occasional red workflow if Cove ingest hiccups.
- **No schema/API changes**, no downstream consumers affected.

## 4. Suggestions (non-blocking)

1. **`$GITHUB_OUTPUT` heredoc delimiter** (`notify-issue-close.yml` ~L33–35): The fixed `EOF` delimiter is technically vulnerable if a payload value contains a bare `EOF` line. In practice GitHub issue titles and URLs cannot contain newlines, so this is safe today. If you ever start passing multi-line user content through `$GITHUB_OUTPUT`, switch to a random delimiter (`delim=$(openssl rand -hex 16)`).
2. **Spec drift (cosmetic):** `docs/specs/393-shell-injection-fix.md` "After" snippet shows a plain `echo "message=…" >> $GITHUB_OUTPUT` for the multi-line output, but the actual workflow correctly uses the `message<<EOF … EOF` heredoc form. The implementation is the better one — consider updating the spec snippet to match so future readers don't copy the inferior pattern.
3. **`notify-cove.yml` — `PR_TITLE` source:** `${{ github.event.pull_request.title }}` is set via `env:` which is correct. Consider also adding `WEBHOOK_URL` validation (`[ -n "$WEBHOOK_URL" ] || exit 1`) so a missing secret fails loudly instead of curling an empty URL — small DX win.
4. **Consistency:** `notify-issue-close.yml` job runs on `closed/reopened/labeled/...` but `Wait for staging deploy` only fires on `closed`. That's correct, just worth a one-line comment explaining why labeled/assigned events skip the wait.

## 5. Positive Notes

- Textbook application of GitHub's "intermediate environment variable" guidance — exactly the pattern Security Lab recommends.
- `jq -nc --arg content "$MSG"` is the right tool: it handles quoting, control characters, and Unicode correctly. No more `\"` escaping that could be bypassed.
- The case-statement refactor in `notify-issue-close.yml` collapses 48 → 25 lines without losing branches; readability went up.
- Added `-f` to `curl` is a quiet quality-of-life improvement that turns silent webhook failures into visible CI errors.
- Spec doc (`docs/specs/393-shell-injection-fix.md`) provides clear before/after, evidence (run IDs), and a manual verification plan — good practice for security fixes that lack automated tests.
- Scope is tight: only the two affected workflows touched, no incidental refactors.

---

**Reviewed dimensions:** Correctness ✓ · Security ✓ (primary focus, fix is sound) · Performance n/a · Readability ✓ · Testing — no automated tests, but workflow YAML is hard to unit-test and the spec provides a manual verification recipe (acceptable for this PR class) · Input validation ✓ · API design n/a · Schema consistency n/a · Product impact noted above.
