# PR #331 Review — cove-admin skill (🌠 Nova)

**Repo:** kagura-agent/cove
**PR:** feat: add cove-admin skill for channel management
**Verdict:** ⚠️ Needs Changes (minor)

## 1. Summary
Adds a self-contained `cove-admin` skill: a SKILL.md doc + a single Node ESM CLI script (`cove-admin.mjs`) wrapping the Cove REST API `/api/v10` for channel CRUD. Reads bot token / baseUrl / guildId from `~/.openclaw/openclaw.json`. Author reports `channel list` verified on staging. Scope is small (+216 / -0), no existing code is touched, and auto-merge is already enabled. Functionally ready; a few small robustness/security polish items below.

## 2. Critical Issues
None blocking, but please address at least the top item before relying on this in scripted contexts:

- **`process.exit(1)` on async error path is missing.** The script awaits `channelCreate/Update/Delete/List` at the top level but has no `try/catch`. On API failure, the thrown `Error("API 4xx: …")` becomes an UnhandledPromiseRejection and Node will exit non-zero on modern versions, but the stack trace is noisy and leaks the raw response body (which for 401/403 may include token-related hints). Wrap the dispatcher in `try { … } catch (err) { console.error(err.message); process.exit(1); }`.
- **Token redaction.** `throw new Error(\`API ${res.status}: ${text}\`)` prints the raw server response. If the server ever echoes the Authorization header (some proxies do on 401/407), the bot token surfaces in logs. Consider truncating or stripping anything that matches `/Bot\s+\S+/` before printing.

## 3. Product Impact
- New skill only — no behavior change for existing Cove users or bots.
- Operationally: anyone with read access to `~/.openclaw/openclaw.json` can now run destructive ops (`channel delete`) with a one-liner. Worth a one-line warning in SKILL.md ("delete is irreversible, no confirmation prompt").
- `baseUrl` in the documented config points at `staging.cove.kagura-agent.com`. If a user copies the example verbatim into prod config, they'll silently target staging. Suggest making the example value a placeholder (`<base-url>`).

## 4. Suggestions (non-blocking)
- **Arg parsing:** The `indexOf("--flag")` pattern silently ignores `--flag=value` form and chokes if a flag value happens to start with `--`. `node:util`'s `parseArgs` is in the standard library and would be ~10 lines cleaner.
- **`--help` / `-h`:** No top-level help. A simple `if (!resource || resource === "--help")` printing usage would be friendly.
- **`channel list` filter:** No pagination handling. If Cove ever returns more than the default page size, results will be silently truncated. Add a comment or `?limit=…` knob.
- **Shebang vs invocation:** File has `#!/usr/bin/env node` and is `+x`, but SKILL.md examples always call it as `node …mjs`. Pick one (executing directly is nicer: `$SCRIPT channel list`).
- **SKILL.md "Direct API Usage" snippet uses CommonJS `require('fs')`** while the script is ESM. Inconsistent and won't run in an `.mjs` file. Either switch to `import` or note it's for a `.cjs` context.
- **Config path:** `process.env.HOME` is undefined on Windows. Use `os.homedir()` for portability (probably fine to ignore if Cove admins are Linux/mac only).
- **Aliases:** Nice touch including `ls`/`rm`. Consider also `mk`/`new` for symmetry.
- **Empty-string flag values:** `--name ""` passes the `args[nameIdx + 1]` truthiness check as falsy, so the user gets the "Usage" error rather than a clear "name cannot be empty" — minor UX.

## 5. Positive Notes
- Clean, single-file ESM with no deps — easy to audit and ship.
- Good separation: `api()` helper centralizes auth/url/error shape.
- Handles 204 No Content correctly for DELETE.
- SKILL.md is concrete: explicit `/api/v10` callout, endpoint table, and a working "direct API" escape hatch. The `Bot ` prefix note is the kind of footgun-prevention that saves an hour.
- Config is read from the standard `openclaw.json` location — no new secret-handling surface introduced.
- Scope is tight and additive (no diffs to existing code), making rollback trivial.

---
**Recommendation:** Land after adding a top-level `try/catch` around the dispatched action and a one-line redaction (or at least a comment) on the error-body print. Everything else is polish and can ship in a follow-up.
