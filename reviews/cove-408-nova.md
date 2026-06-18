# 🌠 Nova Review — cove#408 (fix staging deploy race)

## Summary

The PR moves in the right direction (workflow-level `concurrency`, per-run tmp dirs, post-deploy asset probe, and tightened `redeploy-main` condition). The two parts I was asked to focus on:

- **Run-isolated tmp dirs**: ✅ the `$GITHUB_RUN_ID` suffix correctly removes the cross-run `scp` ↔ `rm -rf` race that #407 hit. Bash interpolates `$GITHUB_RUN_ID` on the runner before the string is shipped over SSH, so the path is unique per workflow run.
- **`concurrency` group + `cancel-in-progress`**: serializes **most** of the bad cases, but introduces a new failure mode where a no-op workflow run cancels a real in-flight deploy (details below). And cancelling mid-deploy combined with the existing `rm -rf /var/www/cove-staging && cp -r ...` pattern can still leave staging visibly broken.

Net: this fixes the reported symptom and is better than `main`, but the design has two residual race windows worth addressing before declaring #407 closed.

Verdict: **⚠️ Needs Changes** — at minimum the no-op-cancels-real-deploy race should be closed; the tmp-dir GC and atomic publish are strong suggestions.

## Critical Issues

### C1. A merged PR can fire a no-op workflow run that cancels the real `push main` deploy

GitHub fires **two** workflow runs simultaneously when a PR is merged:

1. `pull_request_target` with `action=closed`, `pull_request.merged=true`
2. `push` to `main`

After this PR:

- Run #1 evaluates both job `if:`s → `deploy` is skipped (`action == 'closed'`), `redeploy-main` is skipped (requires `merged == false`). The run is a **no-op** but it still occupies the concurrency slot.
- Run #2 runs the real `deploy` job from `main`.

Both runs land in the same concurrency group (`staging-deploy`) with `cancel-in-progress: true`. Whichever starts second cancels the first. Order is not guaranteed:

- If the no-op run starts first and the real `push` run starts later → real run cancels the no-op → fine.
- If the real `push` run starts first (longer queue, etc.) and the no-op run starts later → **the no-op cancels the real deploy mid-flight**. Staging is left in whatever partial state the cancellation hit (very plausibly: `rm -rf /var/www/cove-staging` already happened, `cp` not yet finished → white screen, exactly the symptom #407 was supposed to fix).

This is a regression created by the new `concurrency` block; pre-PR both ran independently to completion.

**Fix options** (any one is enough):

- Add a workflow-level skip so the no-op run never enters the concurrency group, e.g.:
  ```yaml
  jobs:
    deploy:
      if: github.event.action != 'closed'
      ...
    redeploy-main:
      if: github.event.action == 'closed' && github.event.pull_request.merged == false
      ...
    # plus: short-circuit the no-op case before it occupies the slot
  ```
  The cleanest way is to gate the *trigger* — e.g., handle merged-PR redeploy under the existing `push: main` event only (you already do), and drop `pull_request_target.closed` from the trigger list when `merged == true`. Since GH can't filter event payloads at the trigger level, the canonical workaround is a tiny "guard" job whose only purpose is to exit immediately when nothing else will run, **outside** the concurrency group:
  ```yaml
  concurrency:
    group: staging-deploy
    cancel-in-progress: true
  # …then move the concurrency block onto the individual real jobs instead
  # of the workflow, so no-op runs don't compete for the slot.
  ```
  Per-job concurrency is the standard fix here — apply `concurrency:` to `deploy` and `redeploy-main` individually, not at workflow scope. The no-op run never schedules either job and therefore never grabs the slot.
- Alternatively, switch to `cancel-in-progress: false` so the no-op queues behind (and harmlessly after) the real deploy. The downside is that rapid PR pushes will queue instead of cancel stale builds — usually not what you want for PR previews.

I'd take the per-job `concurrency:` route — it preserves cancel-stale-PR-builds and also closes this race.

### C2. Cancellation + `rm -rf /var/www/cove-staging && cp -r …` still leaves a broken-staging window

Independent of C1, `cancel-in-progress: true` means *any* superseding run can interrupt a deploy mid-`cp`. Because the publish step is:

```
sudo rm -rf /var/www/cove-staging \
  && sudo mkdir -p /var/www/cove-staging \
  && sudo cp -r /tmp/cove-staging-client-$GITHUB_RUN_ID/* /var/www/cove-staging/ \
  && rm -rf /tmp/cove-staging-client-$GITHUB_RUN_ID
```

if the runner gets the cancel signal between `rm -rf` and the end of `cp -r`, nginx serves a half-populated `/var/www/cove-staging` until the *next* deploy reaches its own `cp`. The new asset-verification step doesn't help — it only runs in the canceled job and is itself killed.

The fix is the standard "publish atomically via rename" pattern (same filesystem so `mv` is atomic):

```
NEW=/var/www/cove-staging.new.$GITHUB_RUN_ID
OLD=/var/www/cove-staging.old.$GITHUB_RUN_ID
$SSH "sudo rm -rf $NEW && sudo mkdir -p $NEW && \
      sudo cp -r /tmp/cove-staging-client-$GITHUB_RUN_ID/* $NEW/ && \
      sudo test -f $NEW/index.html && sudo ls $NEW/assets/*.js >/dev/null && \
      sudo mv /var/www/cove-staging $OLD 2>/dev/null || true && \
      sudo mv $NEW /var/www/cove-staging && \
      sudo rm -rf $OLD /tmp/cove-staging-client-$GITHUB_RUN_ID"
```

This gives you:
- Zero-window swap (nginx either sees old dir or new dir, never partial).
- Verification happens **before** the swap, so a corrupt/partial upload never reaches `/var/www/cove-staging`.
- Cancellation at any point leaves the live dir untouched.

Without this, you've narrowed the race that #407 reported but you haven't actually removed the class of bug — you've just made it less likely.

## Suggestions

### S1. No GC for orphaned `/tmp/cove-staging-client-*` from cancelled/failed runs

Per-run tmp dirs solve the collision, but the `rm -rf /tmp/cove-staging-client-$GITHUB_RUN_ID` lives at the *end* of the SSH command. If the runner is cancelled (which `cancel-in-progress: true` makes routine) or if `cp` fails, the tmp dir stays on the VM forever. Over months of frequent PR activity these will leak megabytes-to-gigabytes per stale dir into `/tmp` on VM1.

Two-line fix at the *start* of the upload block:
```
$SSH "find /tmp -maxdepth 1 -name 'cove-staging-client-*' -mmin +60 -exec sudo rm -rf {} +"
```
Run it before the new tmp dir is created; it sweeps anything older than an hour. Cheap and self-healing.

### S2. Asset verification is too narrow — won't catch missing `index.html`

`test -d assets && ls assets/*.js > /dev/null` will pass for a deploy that uploaded only `assets/` but lost the SPA entrypoint, which still produces a white screen. Add at least:
```
$SSH "test -f /var/www/cove-staging/index.html && test -d /var/www/cove-staging/assets && ls /var/www/cove-staging/assets/*.js >/dev/null 2>&1" \
  || { echo '❌ Client assets missing after deploy'; exit 1; }
```
And consider comparing file count against the runner-side `find packages/client/dist -type f | wc -l` for cheap completeness.

### S3. Two long deploy blocks are now ~95% duplicated

`deploy` and `redeploy-main` have diverged only by checkout ref + the absence of the systemd unit re-render in `redeploy-main`. Every fix above (C2, S1, S2) has to be applied twice and stay in sync. Extract into a reusable workflow (`workflows/_deploy-staging.yml` with `workflow_call`) or a composite action. Pre-existing tech debt but this PR is the moment it becomes painful — three changes already touch both blocks identically.

### S4. `npm install … 2>/dev/null` swallows real failures

Pre-existing, but: if `better-sqlite3` or `ws` fail to install (e.g., glibc mismatch, npm registry hiccup), the script silently continues and the systemd restart fails opaquely later. Drop the `2>/dev/null`, or at least keep stderr and only suppress stdout.

### S5. `ssh-keyscan` race / TOCTOU

`ssh-keyscan -H $HOST >> ~/.ssh/known_hosts` trusts whatever first response comes back. Not directly related to #407 but: the deploy already uses `StrictHostKeyChecking=no` on every `ssh`/`scp`, so the `ssh-keyscan` line is effectively cosmetic. Either drop it or replace with a pinned hostkey file from secrets.

### S6. `secrets.COVE_ADMIN_TOKEN` interpolated into a heredoc rendered on the remote host

```
$SSH "sudo tee /etc/systemd/system/cove-staging.service > /dev/null << 'UNIT'
…
Environment=COVE_ADMIN_TOKEN=${{ secrets.COVE_ADMIN_TOKEN }}
…
UNIT"
```

The single-quoted `'UNIT'` prevents *remote* shell expansion, which is fine, but the secret is still expanded *locally* and ends up in the SSH command line — meaning it appears in the runner's process list briefly and in any verbose SSH logs. Also the resulting unit file persists the token in plaintext in `/etc/systemd/system/`. Out of scope for #407 but worth a follow-up: load via `EnvironmentFile=` pointing at a `chmod 600` file written via stdin, not via the command-line argument.

## Product Impact

- Behavior change: PRs closed-with-merge no longer trigger `redeploy-main`. Correct — `push main` already does this, so we avoid a duplicate deploy. No user-visible regression.
- Behavior change: PRs closed-without-merge will redeploy main, reverting staging from PR-preview content. This is the intended preview-cleanup path. Confirm with Luna that this is the desired UX; before this PR it also did this, so no change.
- Behavior change introduced by C1: under bad ordering, a merged PR can leave staging broken until the next push. This is a real product regression compared to pre-PR behavior.

## Positive Notes

- `$GITHUB_RUN_ID` suffix is the right primitive — unique, sortable, available on all event types, no secret leakage. Clean fix to the original collision.
- Post-deploy `ls assets/*.js` is the right *kind* of check (verify the artifact reached the destination, not just that SSH returned 0). Just needs to be a bit stricter.
- Tightening `redeploy-main` to `merged == false` removes a real double-deploy. Good catch while in the file.
- Bundling all of this into one focused PR with a linked issue (#407) makes the change easy to review and revert.

## Verdict

⚠️ **Needs Changes** — C1 must be addressed (move `concurrency:` to per-job scope, or otherwise prevent the no-op `pull_request_target closed merged=true` run from competing for the slot). C2 (atomic publish via `mv`) is the structurally correct fix for the class of bug #407 reports; without it the race is narrowed but not eliminated. S1 (tmp-dir GC) is a 2-line follow-on that prevents the new per-run dirs from becoming a disk leak.
