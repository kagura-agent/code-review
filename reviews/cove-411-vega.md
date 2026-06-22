## Summary
This PR updates the staging deployment workflow to replace a race-condition-prone `scp -r` command with a reliable `tar` pipe stream for uploading client build artifacts. It also removes redundant unique path suffixes (relying on workflow concurrency instead) and adds a fail-fast check to ensure client assets actually exist before attempting deployment.

## Critical Issues
None. The logic cleanly addresses the SFTP mkdir race condition, prevents partial/failed deployment states by explicitly verifying the presence of the `assets/` directory, and cleanly cleans up its temp directories.

## Product Impact
None for end-users. For developers, this reduces or eliminates intermittent staging deploy failures, leading to more reliable continuous delivery and less time spent re-running CI jobs.

## Suggestions
1. **Glob expansion in `cp -r`**: In the final command `sudo cp -r /tmp/cove-staging-client/* /var/www/cove-staging/`, the `/*` glob will ignore hidden dotfiles (e.g., `.well-known`, `.htaccess`) at the root level of `dist`. The previous `scp -r .../*` command had the same behavior, so this is not a regression, but since your `tar -cf - .` command now includes them, you could simplify and safely copy everything by changing it to `sudo cp -r /tmp/cove-staging-client/. /var/www/cove-staging/`.

## Positive Notes
- The added `test -d packages/client/dist/assets` check is a great fail-fast addition that prevents deploying a broken or empty build.
- Utilizing a tar pipe over SSH is an elegant, dependency-free solution to avoid the known OpenSSH `scp -r` race condition on nested folder creation.
- Cleaning up the `$GITHUB_RUN_ID` from the temp folder path makes the script easier to read, properly leveraging the workflow's concurrency group controls.

**Verdict**: ✅ Ready
