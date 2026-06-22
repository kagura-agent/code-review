# 🌠 Nova — Code Review: cove#411

**Title:** docs: spec for #392 — fix intermittent scp deploy failure with tar pipe
**Verdict:** ✅ **Ready** (with minor suggestions)

---

## 1. Summary

Replaces `scp -r packages/client/dist/*` with a `tar | ssh tar -x` pipe in both `deploy` and `redeploy-main` jobs of `.github/workflows/deploy-staging.yml`, and adds a `docs/specs/392-deploy-scp-fix.md` design note. The diagnosis (OpenSSH 9.x SFTP-mode scp racing on subdir mkdir when the glob mixes files and directories) is plausible and well-known; tar-piping is the standard, dependency-free fix. The change is small, symmetric across the two jobs, drops the no-longer-needed `$GITHUB_RUN_ID` suffix safely under the existing `concurrency: group: staging-deploy, cancel-in-progress: true`, and adds an empty-build guard (`test -d packages/client/dist/assets`). Risk surface is contained to staging.

## 2. Critical Issues

None blocking.

## 3. Product Impact

- **Staging deploy reliability** ↑ — the original intermittent failure leaves staging pinned to a stale build; this should remove that class of failure.
- **No user-facing runtime behavior change** — production deploys are untouched.
- **Brief empty-window risk during deploy** (pre-existing, not introduced here): the single SSH line `sudo rm -rf /var/www/cove-staging && sudo mkdir -p … && sudo cp -r …` still has a window where `/var/www/cove-staging` is empty. The verify-step (`test -d /var/www/cove-staging/assets`) catches the failure case but not the in-flight window. Acceptable for staging.

## 4. Suggestions (non-blocking)

1. **Pipefail guarantees** — GitHub Actions' default shell for `run:` on Linux is `bash --noprofile --norc -eo pipefail {0}`, so `tar -C packages/client/dist -cf - . | $SSH "tar -C /tmp/cove-staging-client -xf -"` will surface a local `tar` failure. Worth a one-line comment in the workflow noting the dependency on pipefail — it's invisible context that future edits could break.

2. **Hidden-file semantics drift** — `scp -r dist/*` relied on the shell glob, which by default does **not** match dotfiles, while `tar -C dist -cf - .` includes everything (including any future `.vite/`, `.DS_Store`, `.htaccess`-style files). Today Vite's `dist/` is dotfile-free so behavior is equivalent, but if a future build introduces a dotfile you don't want shipped, it would silently appear in `/var/www`. Either acknowledge this explicitly or add `--exclude='.*'` if you want to preserve old semantics.

3. **Concurrency coupling is now load-bearing** — dropping `$GITHUB_RUN_ID` from `/tmp/cove-staging-client` is safe **only because** both jobs share `group: staging-deploy` with `cancel-in-progress: true`. Worth a short comment in the workflow at that line, e.g. `# safe to share /tmp path: serialized via concurrency group staging-deploy`. Cheap insurance against a future edit that splits the concurrency groups.

4. **Verification block is unchanged but worth a sanity check** — the post-deploy `ls /var/www/cove-staging/assets/*.js` should also catch the original race, but consider tightening to also verify `index.html` exists (the SPA entrypoint is the user-visible failure mode).

5. **Spec/impl framing in the PR body** — the body says "Waiting for spec approval before implementing" yet the same PR already modifies the workflow file. Either retitle to "spec + impl" / drop the waiting line, or split spec from impl. Minor; doesn't affect merge.

6. **Spec line references** — `docs/specs/392-deploy-scp-fix.md` cites lines ~70-72 and ~130-132; the actual edits land near ~68 and ~216. Trivial; update or remove for future-readers.

7. **Compression** — `tar -czf` + `tar -xzf` on a dist that's mostly already-minified JS won't gain much, and it adds CPU cost on the runner. Current choice (no compression) is fine; just noting for completeness.

8. **`SCP` variable kept** — correctly retained for `server-bundle.js` upload. ✅

## 5. Positive Notes

- **Right diagnosis, simple fix.** Tar pipe is the canonical replacement for racy `scp -r` and adds zero new tooling.
- **Symmetric change** across `deploy` and `redeploy-main` — both code paths kept in sync so the bug can't survive on one side.
- **Empty-build guard** (`test -d packages/client/dist/assets`) fails fast before mutating the remote — good defensive layer.
- **Existing verify step preserved** (`test -d /var/www/cove-staging/assets && ls .../*.js`) — gives a clear failure signal if anything regresses.
- **Spec doc is genuinely useful** — explains *why* the suffix is now safe (concurrency group) and lists the before/after explicitly. Future maintainers will thank you.
- **Scope discipline** — server bundle path, systemd unit, health check all untouched. Minimal blast radius.

---

**Recommendation:** ✅ Merge. Optionally pick up suggestion #3 (one-line comment about concurrency coupling) before or after merge — cheap and durable.
