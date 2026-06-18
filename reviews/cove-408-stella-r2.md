# PR #408 Round 2 Review — Stella

## Summary
This revision fixes the Round 1 blocker by moving `concurrency` from workflow scope to job scope and by skipping `redeploy-main` for merged PR close events. A merged-PR `pull_request_target` run should no longer enqueue a no-op workflow-level concurrency group that can cancel a real `push main` deploy. The remaining items are staging-hardening/maintainability suggestions rather than merge blockers.

**Verdict: ✅ Ready**

## Critical Issues
None.

Round 1 critical status:
- **Addressed:** The previous workflow-level `concurrency: staging-deploy` no-op cancellation hazard is resolved. `deploy` now owns concurrency at `.github/workflows/deploy-staging.yml:13-15` and excludes closed events at line 16; `redeploy-main` now only runs for unmerged closed PRs at line 163 and owns its own job-level concurrency at lines 164-166. A merged PR close event should skip both jobs, while the actual `push` to `main` still runs `deploy`.

## Product Impact
Staging deploy behavior is clearer and safer for merged PRs: merge-close events no longer compete with the main-branch deploy. Unmerged PR closures still intentionally cancel/replace any active staging preview deploy so staging returns to `main`.

One minor UX mismatch remains: the preview comment still says “Staging will redeploy main when this PR is merged or closed” at `.github/workflows/deploy-staging.yml:135`. With the new logic, merges rely on the `push main` event rather than `redeploy-main`. The end result is still staging returning to main, so this is not blocking.

## Suggestions
1. **Clean orphaned run-scoped tmp dirs on cancellation.**  
   The tmp dir is now run-scoped (`/tmp/cove-staging-client-$GITHUB_RUN_ID`) at `.github/workflows/deploy-staging.yml:69-71` and `216-218`, which avoids cross-run clobbering, but cancellation before the final `rm -rf` can still leave orphaned dirs. Consider adding a best-effort cleanup step with `if: always()` or a periodic cleanup of old `/tmp/cove-staging-client-*` dirs.

2. **Verify `index.html` in addition to JS assets.**  
   The new verification at `.github/workflows/deploy-staging.yml:73-74` and `220-221` catches missing JS bundles, but a static SPA deploy also needs `/var/www/cove-staging/index.html`. Add `test -f /var/www/cove-staging/index.html` so a partial copy or malformed dist cannot pass with assets only.

3. **Publish client assets atomically.**  
   `.github/workflows/deploy-staging.yml:71` and `218` still do `sudo rm -rf /var/www/cove-staging && sudo mkdir -p ... && sudo cp -r ...`, leaving a window where staging has no static files if the job is cancelled or `cp` fails mid-publish. A safer pattern is copy into a new release directory, verify it, then atomically swap a symlink or `mv` into place.

4. **Reduce duplicated deploy blocks when convenient.**  
   The `deploy` and `redeploy-main` jobs still duplicate most build/deploy logic. This is acceptable for this small workflow, but extracting a reusable workflow or composite action would reduce drift as staging deploy logic evolves.

## Positive Notes
- The important concurrency fix is targeted and preserves the single-staging-environment invariant.
- Run-scoped tmp paths are an improvement over the original shared `/tmp/cove-staging-client` path and reduce accidental cross-run interference.
- Adding post-copy asset verification is a good safety net, even if it should include `index.html` too.
