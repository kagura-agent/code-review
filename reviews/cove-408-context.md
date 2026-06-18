# PR #408 Context

**Repo:** kagura-agent/cove
**PR:** #408
**Title:** fix(ci): prevent staging deploy race condition (#407)
**Branch:** fix/407-deploy-race → main
**Stats:** +17 / -7, 1 file changed

## Files Changed
1. `.github/workflows/deploy-staging.yml` — +17/-7

## What This PR Does

Fixes a staging deploy race condition where PR merge triggers both `push main` and `pull_request_target closed` events simultaneously. Both deploy jobs wrote to `/tmp/cove-staging-client`, and `rm -rf` from one raced with `scp -r` from the other → white screen (missing assets).

### Fixes
1. **Concurrency group** — `staging-deploy` with `cancel-in-progress: true`
2. **Run-isolated tmp dirs** — `/tmp/cove-staging-client-$GITHUB_RUN_ID`
3. **Asset verification** — fail if `/var/www/cove-staging/assets/*.js` missing after deploy

Applied to both `deploy` and `redeploy-main` jobs. Closes #407.
