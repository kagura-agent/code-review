# Stella Review — cove PR #408

## Summary

✅ **Ready.** This PR addresses the reported staging deploy race in the right places: the merged-PR double trigger is removed by skipping `redeploy-main` for merged PRs, the workflow-level concurrency group serializes the singleton staging environment, and the remote upload temp directory is no longer shared across workflow runs. The added asset verification is a useful guardrail for the white-screen failure mode, though it is best treated as detection rather than a fully atomic/rollback-safe deploy mechanism.

## Critical Issues

None found.

## Product Impact

- The merge path now relies on the `push`-to-`main` deployment only (`deploy` job, lines 16-17), while `redeploy-main` only runs for closed-unmerged PRs (line 164). That matches the intended staging behavior and avoids the old merge-time duplicate deployment.
- `concurrency.group: staging-deploy` with `cancel-in-progress: true` (lines 11-13) is appropriate for a singleton staging host: newer staging deploys supersede older ones instead of racing against them.
- The staging preview comment still says “Staging will redeploy main when this PR is merged or closed” (line 136). Functionally this remains true for users because a merge triggers `push: main`, but the implementation detail changed. No product risk; just slightly stale wording.

## Suggestions

1. **Verify staged assets before replacing the live directory.**  
   The new check on lines 74-75 and 218-219 correctly catches missing deployed JS assets after copy, which would have exposed the previous silent `scp` warning. However, because verification happens after `/var/www/cove-staging` is removed and recreated (lines 72 and 216), a failed copy can still leave staging broken while correctly failing CI. A more robust deploy pattern would verify `/tmp/cove-staging-client-$GITHUB_RUN_ID/assets/*.js` first, then swap/copy into `/var/www/cove-staging` only after the staged artifact is known-good. If you want true rollback safety, deploy into a release directory and atomically update a symlink.

2. **Consider including `GITHUB_RUN_ATTEMPT` in the temp directory name.**  
   `GITHUB_RUN_ID` gives run isolation for normal concurrent workflow runs (lines 70-72 and 214-216), so it fixes the reported race. Adding `${GITHUB_RUN_ATTEMPT}` would make manual reruns/cancel-retry cases even more isolated, especially if a previous attempt left remote cleanup incomplete.

3. **Optional: check the full asset set referenced by `index.html`.**  
   The current `assets/*.js` check is sufficient for the reported missing-JS white screen and is much better than no verification. If this workflow becomes more critical, a stronger guard would verify that every `/assets/...` reference in the deployed `index.html` exists, covering CSS and other emitted assets too.

## Positive Notes

- The root race is addressed redundantly: event-level fix (`redeploy-main` skip on merged PR), workflow serialization, and temp-dir isolation each reduce the chance of recurrence.
- The temp directory change is applied consistently to both deployment paths.
- The verification command is simple, shell-safe for the intended Vite-style output, and will fail the workflow on the exact class of missing JS assets that caused the white screen.
