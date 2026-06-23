# 🌟 Stella — Round 2 Review: PR #413

## 1. R1 Issue Tracker

1. ✅ **Fixed — CRITICAL: static `EOF` delimiter in `GITHUB_OUTPUT`**
   - `.github/workflows/notify-issue-close.yml:32-36` now uses a runtime random delimiter via `openssl rand -hex 8`.
   - This removes the predictable delimiter attack from user-controlled issue titles. A malicious title can no longer precompute the terminator line with practical reliability.

2. ✅ **Fixed — spec “After” example drifted from implementation**
   - `docs/specs/393-shell-injection-fix.md:45-81` now mirrors the actual workflow structure, including `env:`, `jq`, `curl -sfS`, non-empty webhook handling, and the random output delimiter.

3. ✅ **Fixed — `curl -sf` / `curl -s` should surface failures**
   - `.github/workflows/notify-cove.yml:23` and `.github/workflows/notify-issue-close.yml:49` now use `curl -sfS`, preserving quiet success while surfacing error details.

4. ❌ **Not Fixed — automated regression coverage / actionlint not added**
   - No test, workflow validation job, or `actionlint` coverage was added in this PR.
   - Escalated from R1 suggestion to **minor follow-up** under the re-review protocol. I do not consider this blocking for this small security workflow fix, but it remains worth adding soon because this bug class is easy to regress in GitHub Actions YAML.

## 2. New Issues

No new blocking issues found.

Notes from fresh review:

- The main untrusted inputs are now passed through `env:` instead of direct shell interpolation:
  - issue fields in `.github/workflows/notify-issue-close.yml:13-20`
  - PR title/number in `.github/workflows/notify-cove.yml:15-18`
- JSON payload construction now uses `jq --arg`, which correctly preserves quotes, backticks, `$()`, backslashes, and newlines as data rather than shell or JSON syntax.
- `WEBHOOK_URL` empty checks at `.github/workflows/notify-issue-close.yml:47` and `.github/workflows/notify-cove.yml:20` are a useful robustness improvement.
- I verified the changed workflow files parse as YAML locally. `actionlint` is not installed in this environment, so I could not run that specific validation gate.

## 3. Summary & Verdict

✅ **Ready**

The R1 blocking security issue is addressed correctly. The implementation now follows GitHub’s recommended intermediate environment variable pattern, uses `jq` for JSON construction, improves webhook error visibility, and fixes the spec example. The remaining unaddressed R1 item is test/tooling coverage; I recommend adding `actionlint` or a regression check in a follow-up, but I would not block this security fix on it.
