# 🌠 Nova — PR #408 Re-Review (Round 2)

**Focus:** Race conditions, concurrency, deploy atomicity

## Summary

The headline Critical from Round 1 — workflow-level `concurrency: staging-deploy` cancelling real `push: main` deploys when a merged PR fires the no-op `pull_request_target closed` event — **is correctly fixed**. The fix has two parts, both load-bearing:

1. `concurrency:` was moved from workflow scope to per-job scope on `deploy` and `redeploy-main`.
2. `redeploy-main` gained `github.event.pull_request.merged == false`, so merged PRs no longer trigger any job from the closed event — the `push: main` event owns the merge deploy alone.

Because per-job concurrency is only acquired when the job actually runs (skipped `if:` conditions do not acquire the group), a no-op closed-merged workflow now cannot cancel a real deploy. The fix is structurally sound.

However, the original 4 suggestions are all **unaddressed**, and two of them interact badly with the now-active `cancel-in-progress: true` mechanic. Per the escalation rule, severities go up.

**Verdict: ⚠️ Needs Changes** — not for the original Critical (fixed), but because making cancellation real exposes a half-deployed-state window that needs at minimum a guard, ideally atomic publish.

---

## Critical Issues

### C1. Cancellation now produces a half-deployed `/var/www/cove-staging` (escalated from Round 1 #4)

The deploy publishes via:
```
sudo rm -rf /var/www/cove-staging
sudo mkdir -p /var/www/cove-staging
sudo cp -r /tmp/cove-staging-client-$RUN_ID/* /var/www/cove-staging/
```

This was already a non-atomic publish window in Round 1, but I marked it a Suggestion because nothing was actively cancelling runs. **This PR introduces `cancel-in-progress: true`** — the explicit design is "kill the in-flight run and start a new one." When the cancellation lands between the `rm -rf` and the end of `cp -r`, nginx serves a `/var/www/cove-staging` that is either empty (404 on `index.html`) or partially copied (missing chunks → blank app, MIME errors). The verification step (`test -d .../assets && ls .../assets/*.js`) runs in the cancelled job, so it never fires, and the *next* run will repeat the same destroy-then-copy with the same window.

Escalating to Critical because the fix in this PR is what makes this race observable. Recommended fix is atomic swap:

```bash
$SSH "sudo rm -rf /var/www/cove-staging.new && sudo mkdir -p /var/www/cove-staging.new \
  && sudo cp -r /tmp/cove-staging-client-$GITHUB_RUN_ID/* /var/www/cove-staging.new/ \
  && sudo rm -rf /var/www/cove-staging.old \
  && ([ -d /var/www/cove-staging ] && sudo mv /var/www/cove-staging /var/www/cove-staging.old || true) \
  && sudo mv /var/www/cove-staging.new /var/www/cove-staging \
  && rm -rf /tmp/cove-staging-client-$GITHUB_RUN_ID"
```

`mv` on the same filesystem is atomic at the rename syscall, so nginx never observes an empty/partial dir. Both deploy blocks need the same change.

---

## Findings

### F1. Orphaned `/tmp/cove-staging-client-$RUN_ID` on cancellation (escalated from Round 1 #2 → Warning)

Round 1 already flagged this. With `cancel-in-progress: true` now active, this is no longer hypothetical — every cancelled PR sync run leaves a tmp dir on the VM that nothing ever removes. The `rm -rf /tmp/cove-staging-client-$RUN_ID` cleanup is inline in the same `$SSH` invocation as the `cp -r`, so a cancel before that command completes (or before SSH even starts because the runner was killed) leaks the dir. The `$RUN_ID` suffix prevents collision but defeats any naive "clean up the well-known name" pattern.

Minimum fix: a pre-step (idempotent) that prunes `/tmp/cove-staging-client-*` older than N hours, e.g.:
```bash
$SSH "sudo find /tmp -maxdepth 1 -name 'cove-staging-client-*' -mmin +60 -exec rm -rf {} +"
```
Better: also run it as a `if: always()` cleanup step at the end of the job (still won't fire on hard-cancel, but covers timeouts and step failures).

### F2. Asset verification still skips `index.html` and the bundle entry (held from Round 1 #3 → Suggestion)

`test -d /var/www/cove-staging/assets && ls /var/www/cove-staging/assets/*.js` will pass even if `/var/www/cove-staging/index.html` is missing (e.g., if Vite's output structure changed or `cp -r` was partially interrupted on a non-assets file). For an SPA, a missing `index.html` is a hard 404 on `/`. Add at minimum:
```bash
$SSH "test -f /var/www/cove-staging/index.html" || { echo '❌ index.html missing'; exit 1; }
```
Plus a tiny end-to-end curl against the public URL would catch nginx-path / permission regressions that the localhost health check on `:3501` can't see.

### F3. Duplicated deploy blocks (held from Round 1 #5 → Suggestion)

Still ~95% duplicated between `deploy` and `redeploy-main`. Now that this workflow is being actively iterated on (this is the second round of fixes), every future change has to be made twice and kept in sync — the verification step in this PR is a good example: both copies were updated, but a missed copy on a future change is exactly how the original Round 1 Critical class of bug recurs. Extract into `.github/workflows/_deploy-staging-reusable.yml` and call with `workflow_call` + `inputs.ref`.

### F4. Concurrency group shared between two jobs — verify intent (new)

Both `deploy` and `redeploy-main` use `group: staging-deploy`. This means:

- A `pull_request closed (merged=false)` event triggering `redeploy-main` will cancel an in-flight PR `deploy` from a different PR. That's almost certainly correct ("latest intent wins, only one staging slot").
- A new push to a PR cancelling its own previous `deploy` is correct.
- A `push: main` triggering `deploy` will cancel an in-flight PR `deploy`. Also correct.

This is intentional and right, but it's worth a one-line comment in the workflow stating "shared group across `deploy` and `redeploy-main` is intentional: one staging slot, latest-wins." Otherwise the next person editing this file (or the next Round-3 reviewer) has to re-derive the model.

### F5. `redeploy-main` uses `pull_request.merged == false` — confirm GitHub semantics (new)

The condition `github.event.action == 'closed' && github.event.pull_request.merged == false` correctly routes merged-PR deploys to the `push: main` path. One thing to double-check on the next deploy: GitHub's `pull_request_target` `merged` field is a boolean on the PR object, not a string — the YAML comparison `== false` works because Actions expression syntax does typed comparison, but it's worth confirming the close-without-merge path actually deploys main as intended on the first real test. If the boolean is somehow stringified to `"false"` in some edge case, `== false` fails and the redeploy is skipped silently. A defensive form would be `!github.event.pull_request.merged`. Low risk, but free to fix.

---

## Positive Notes

- **Concurrency placement is exactly right.** Moving from workflow-level to per-job is the surgical fix; many would have just removed `cancel-in-progress` and lost the latest-wins behavior. This preserves it for real deploys while killing the no-op cancellation path.
- **Belt-and-suspenders with `merged == false`.** Even if per-job concurrency semantics changed in a future Actions version, the merged-PR no-op job would still not acquire the lock because it never starts. Two independent mechanisms protect the same invariant.
- **`$GITHUB_RUN_ID` suffix on tmp dir.** Eliminates the "two concurrent deploys clobber each other's staging area" race even before cancellation kicks in.
- **Asset verification step added.** Even though F2 says it's incomplete, having a verification gate at all is a real improvement over "trust `cp -r`."

---

## Re-review Summary Table

| Round 1 Finding | Round 2 Status | New Severity |
|---|---|---|
| #1 Workflow-level concurrency cancels real deploys | **Fixed** (per-job + `merged==false`) | Resolved |
| #2 Orphaned tmp dir | Unaddressed; cancel-in-progress makes it active | Warning (was Suggestion) |
| #3 Asset verification should include `index.html` | Unaddressed | Suggestion (held) |
| #4 Atomic publish via `mv` | Unaddressed; cancel-in-progress makes it a real race | **Critical** (was Suggestion) |
| #5 Deduplicate deploy blocks | Unaddressed | Suggestion (held) |

**New findings:** F4 (document shared concurrency intent), F5 (defensive `!merged` form).

**Verdict: ⚠️ Needs Changes** — block on C1 (atomic publish), strongly recommend F1, address others when convenient.

---

~/.openclaw/workspace/code-review/reviews/cove-408-nova-r2.md
