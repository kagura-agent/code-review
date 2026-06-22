# Review: kagura-agent/cove PR #413 — Stella

**Rating: ⚠️ Needs Changes**

## Summary

This PR correctly moves the obvious shell-injection sources out of inline shell interpolation and uses `jq` to construct webhook JSON, which is the right direction for the reported backtick/`$()` failure. I verified the main snippets locally with hostile titles containing backticks, command substitutions, and quotes; those values remain literal. However, the issue workflow still writes attacker-controlled title text through a fixed `GITHUB_OUTPUT` heredoc delimiter, so a valid issue title can break output parsing and keep the notification workflow fragile. Given this is a security hardening PR and there are no automated regression checks for the hostile inputs, I would not merge as-is.

## Critical Issues

1. **Fixed `GITHUB_OUTPUT` delimiter can be broken by user-controlled issue titles** — `.github/workflows/notify-issue-close.yml:33`
   - The workflow writes `steps.msg.outputs.message` using a fixed `EOF` delimiter while the message includes `github.event.issue.title` from users. An issue titled exactly `EOF` will appear as a delimiter line inside the value, prematurely terminate the output, and likely make the following URL line invalid output syntax. This is not shell execution, but it is still an attacker-controlled workflow failure in the same notification path this PR is hardening.
   - Fix options: avoid passing the composed message through `GITHUB_OUTPUT` and build/send the JSON in one step, or use a collision-resistant delimiter such as a generated UUID and ensure it cannot appear as a standalone line in the value.

2. **No automated regression coverage for the security fix** — affected workflows: `.github/workflows/notify-cove.yml`, `.github/workflows/notify-issue-close.yml`
   - The spec lists manual verification only. For a shell-injection fix, add at least a lightweight regression test/smoke script that exercises titles like `` `whoami` ``, `$(echo injected)`, quotes, JSON-special characters, and the output-delimiter edge case above. Without this, the exact class of bug can regress silently in future workflow edits.

## Product Impact

- Positive: PR and issue notifications should now preserve literal special characters in titles instead of failing or executing shell syntax.
- Risk: issue notifications can still fail for a simple title like `EOF` until the output-passing method is made delimiter-safe.
- Behavior change: `curl -sf` now makes webhook HTTP failures fail the workflow instead of being silent. That is probably desirable for observability, but it may surface transient Cove/webhook outages as red GitHub workflow runs.

## Suggestions

- Consider removing the intermediate `Build notification message` output entirely and doing message construction plus `jq` payload generation in the send step; that eliminates one whole escaping surface.
- Add `actionlint` to CI or run it as part of the PR checks for workflow-only changes.
- Update `docs/specs/393-shell-injection-fix.md` so the “After” example matches the safer final implementation; currently the example still shows a less-safe output-writing pattern than the PR code.

## Positive Notes

- Moving untrusted GitHub event fields into `env:` follows GitHub’s recommended mitigation for script injection in Actions.
- JSON construction with `jq --arg` is a strong improvement over hand-escaped JSON strings.
- The changed `GITHUB_OUTPUT` syntax handles ordinary multiline messages much better than the previous single-line `echo message=...` approach.
