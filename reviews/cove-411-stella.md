# Review: kagura-agent/cove PR #411

## Summary
This PR replaces the flaky `scp -r packages/client/dist/*` staging client upload with a tar-over-SSH stream in both deploy paths and adds a fast-fail check for missing built assets. The implementation matches the stated intent and should remove the OpenSSH/SFTP recursive-copy race without adding dependencies. I did not find a merge-blocking correctness, security, or schema/config issue in the workflow diff, but there are a few small robustness and documentation inconsistencies worth cleaning up.

## Critical Issues
None found.

## Product Impact
- Staging deploys should become more reliable because the client build is transferred as one tar stream instead of many recursive `scp` operations (`.github/workflows/deploy-staging.yml:69-72`, `217-220`).
- If `packages/client/dist/assets` is absent, the workflow now fails before uploading rather than deploying an incomplete client (`.github/workflows/deploy-staging.yml:69`, `217`). That is a positive behavior change, but it may surface build-output layout changes immediately.
- The PR body/spec says this is a draft/waiting for spec approval, while the workflow implementation is already included. That can confuse reviewers/release expectations, though it is not a runtime blocker.

## Suggestions
- Consider using a run-scoped remote temp directory again, e.g. `/tmp/cove-staging-client-$GITHUB_RUN_ID`, or a `mktemp -d` directory, even with GitHub concurrency (`.github/workflows/deploy-staging.yml:70`, `218`). The static path is probably safe under normal serialized runs, but a run-scoped path gives extra protection against cancellation/retry overlap and makes debugging leftover temp data easier.
- Update `docs/specs/392-deploy-scp-fix.md:2` and the PR body to reflect that this PR includes the implementation, not only the spec/draft approval step.
- The new asset guard only checks that `assets/` exists. If the goal is to ensure a usable Vite client build, you could also mirror the post-deploy JS check locally before transfer, e.g. require `index.html` and at least one `assets/*.js` (`.github/workflows/deploy-staging.yml:69`, `217`).
- `$SCP` remains defined because server bundle upload still uses it (`.github/workflows/deploy-staging.yml:59`, `210`), so no cleanup needed there.

## Positive Notes
- The same fix is applied consistently to both staging deploy paths (`deploy` and `redeploy-main`).
- The tar pipe avoids shell glob expansion and SFTP recursive-copy semantics, directly addressing the intermittent failure mode.
- The post-deploy verification remains in place, so the workflow still validates that client assets actually reached `/var/www/cove-staging/assets`.

## Rating
✅ Ready
