# Review: cove PR #408

**Verdict:** ✅ Ready

---

### Summary
This PR correctly fixes the reported race condition for staging deploys. It introduces a concurrency group to prevent simultaneous runs, uses run-specific temporary directories to avoid conflicts, and adds a verification step to ensure client assets are present after deployment. The implementation is solid and directly addresses the failure mode described in #407.

### Critical Issues
None.

### Suggestions
1.  **Disk Cleanup on Cancellation:** The remote temporary directory `/tmp/cove-staging-client-$GITHUB_RUN_ID` is not cleaned up if the workflow is cancelled or fails after the `scp` command but before the final `rm -rf`. While these directories are small and `/tmp` is periodically cleared by the OS, they can accumulate in the short term.
    - **Recommendation:** Consider adding a final, "always-run" step to the job that SSHes in and cleans up the run-specific temp directory. This ensures cleanup even on failure or cancellation.
    ```yaml
    - name: Cleanup remote temp dir
      if: always()
      run: |
        $SSH "rm -rf /tmp/cove-staging-client-$GITHUB_RUN_ID"
    ```

2.  **Asset Verification Robustness:** The current asset check (`ls /var/www/cove-staging/assets/*.js`) is good, but could be brittle if the build output changes (e.g., uses content hashes in filenames, different subdirectories).
    - **Recommendation:** A slightly more robust check would be to verify the existence of the main `index.html` file, which is less likely to change and is the ultimate entrypoint.
    ```bash
    # Alternative verification
    $SSH "test -f /var/www/cove-staging/index.html" || { echo '❌ index.html missing after deploy'; exit 1; }
    ```
    This is a minor point; the current check is sufficient for now.

### Positive Notes
- **Correct concurrency control:** The use of `concurrency.group` with `cancel-in-progress: true` is the right tool for this problem and is implemented correctly.
- **Isolated temp dirs:** Using `$GITHUB_RUN_ID` to create unique temporary directories is a great, robust solution to the file collision problem.
- **Atomic-enough deploy:** The deploy logic of copying to a new directory and then moving it into place (`rm` then `cp`) is a good pattern. The addition of the post-deploy verification step correctly handles failures during the copy, ensuring the job fails if the site is left in a broken (empty) state.
- **Clear and focused:** The PR is small, focused, and directly solves the problem it set out to fix.
