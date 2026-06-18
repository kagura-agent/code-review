# Consolidated Review — cove PR #408

**PR:** kagura-agent/cove#408
**Title:** fix(ci): prevent staging deploy race condition (#407)
**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 2.5 Pro)
**Date:** 2026-06-18

---

## Verdict: ⚠️ Needs Changes (1 issue)

The PR correctly fixes the reported race — per-run tmp dirs, concurrency group, asset verification, and tightened `redeploy-main` condition are all the right moves. But the workflow-level `concurrency` block introduces a new race where a no-op merged-PR workflow run can cancel a real in-flight deploy.

**Reviewer split:** Stella ✅ Ready, Vega ✅ Ready, Nova ⚠️ Needs Changes.

---

## Issue

### No-op merged-PR run can cancel the real `push main` deploy (Nova)

When a PR is merged, GitHub fires two events simultaneously:
1. `pull_request_target` with `action=closed, merged=true`
2. `push` to `main`

After this PR, Run #1 skips both jobs (deploy skips on `closed`, redeploy-main skips on `merged=true`) — it's a **no-op**. But it still occupies the workflow-level `concurrency: staging-deploy` slot.

If the real `push main` run starts first and the no-op run starts second → **the no-op cancels the real deploy mid-flight**. With `rm -rf /var/www/cove-staging && cp -r ...`, cancellation between rm and cp recreates the exact white-screen symptom #407 was meant to fix.

**Fix:** Move `concurrency:` from workflow-level to per-job scope on `deploy` and `redeploy-main`. No-op runs that skip both jobs never grab the slot.

---

## Suggestions

1. **Orphaned tmp dir cleanup** (Nova + Vega) — Cancelled/failed runs leave `/tmp/cove-staging-client-$GITHUB_RUN_ID` on the VM. Add `find /tmp -maxdepth 1 -name 'cove-staging-client-*' -mmin +60 -exec rm -rf {} +` before creating the new dir, or an `if: always()` cleanup step.

2. **Asset verification should include `index.html`** (Stella + Vega + Nova) — Current check (`ls assets/*.js`) catches missing JS but not missing SPA entrypoint, which also produces white screen.

3. **Atomic publish via `mv`** (Stella + Nova) — Current `rm -rf && cp -r` has a window where staging is broken. The standard fix: build into a `.new` dir, verify, then `mv` to swap atomically.

4. **Two deploy blocks are ~95% duplicated** (Nova) — Extract into a reusable workflow or composite action so fixes don't need to be applied twice.

---

## Positive Notes

- `$GITHUB_RUN_ID` suffix is the right primitive — unique, sortable, no secret leakage
- Tightening `redeploy-main` to `merged == false` removes a real double-deploy
- Post-deploy asset verification is the right kind of check — verify the artifact reached the destination
- Small, focused PR with linked issue — easy to review and revert
