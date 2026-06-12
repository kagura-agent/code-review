# 🌠 Nova — R2 Re-review: PR #331 (kagura-agent/cove)

**PR:** feat: add cove-admin skill for channel management
**Files:** `skills/cove-admin/SKILL.md`, `skills/cove-admin/scripts/cove-admin.mjs`
**Verdict:** ✅ **Ready** (with minor non-blocking notes carried forward)

---

## Summary

R1 raised two blocking issues (no top-level error handling, delete with no
confirmation) and a handful of non-blocking suggestions. R2 fixes both
blockers cleanly and lands several of the non-blocking items as well. The
remaining gaps are quality-of-life polish, not correctness or safety.

## R1 Issue Tracking

| # | R1 Issue | Severity R1 | R2 Status | Notes |
|---|----------|-------------|-----------|-------|
| C1 | No top-level error handling — raw stack traces | Critical | ✅ Fixed | Single `try { … } catch (err) { … process.exit(1) }` wraps the dispatch block; subcommands also `process.exit(1)` on usage errors. |
| C2 | Delete had no confirmation flag | Critical | ✅ Fixed | `channelDelete` requires `--yes` or `--force`; without it, prints a clear warning and exits 1 before any API call. |
| N1 | Token redaction in error output | Non-blocking | ✅ Fixed | `err.message.replace(/Bot\s+[\w-]+/g, "Bot ***")` in the top-level catch. Defensive — API errors normally don't echo the token, but this is a cheap belt-and-suspenders. |
| N2 | Arg parsing brittleness (use `node:util` `parseArgs`) | Non-blocking | ❌ Not addressed | Still hand-rolled `indexOf` parsing. See "Suggestions" below — same edge cases as R1 (e.g. `--name --topic foo` would consume `--topic` as the name value). |
| N3 | SKILL.md Direct API snippet used CommonJS `require` | Non-blocking | ✅ Fixed | Snippet now uses `import { readFileSync } from 'node:fs'`. |
| N4 | Config loaded multiple times per command | Non-blocking | ⚠️ Partially addressed | `api()` still calls `loadConfig()` on every request, and `channelCreate`/`channelUpdate` also call it independently. Functionally fine (sync, small file), just slightly wasteful. Cache on first call would be a one-line fix. |
| N5 | `baseUrl` example points to staging | Non-blocking | ❌ Not addressed | SKILL.md still shows `https://staging.cove.kagura-agent.com`. Either swap to a placeholder (`https://<your-cove-host>`) or add a comment that it's the staging example. |
| N6 | Add `--help`/`-h` | Non-blocking | ❌ Not addressed | No help flag. Unknown action prints an available-actions hint, which partly covers it. |

**Escalation check:** No previously-flagged issue was downgraded. The two
critical items are genuinely resolved (not just claimed). Unaddressed
non-blocking items stay non-blocking — they don't compound into anything
worse.

## Critical Issues

None. Both R1 blockers are resolved.

## Product Impact

- **Safety:** Destructive `channel delete` now requires explicit `--yes`/
  `--force`. Matches the doc and removes the foot-gun.
- **DX:** Failures produce a single `❌ <message>` line instead of a stack
  trace; token-shaped substrings are redacted before display.
- **Docs ↔ behaviour:** SKILL.md command examples include `--yes` for
  delete and match the script's contract; the Direct-API snippet is valid
  ESM and matches the script's import style.

No regressions introduced relative to R1.

## Suggestions (non-blocking, optional follow-ups)

1. **`parseArgs` migration (N2).** `import { parseArgs } from 'node:util'`
   would eliminate the `--name --topic foo` swallow case and let you drop
   the `if (nameIdx !== -1 && args[nameIdx + 1])` boilerplate. Single
   shared `options` schema, applied per-subcommand.
2. **Cache config (N4).** Memoize `loadConfig()`:
   ```js
   let _cfg;
   function loadConfig() { return (_cfg ??= /* parse */); }
   ```
3. **Neutralize the baseUrl example (N5).** `https://<your-cove-host>` or
   prepend a `// example: staging` comment so nobody copy-pastes staging
   into a prod config by accident.
4. **`--help`/`-h` (N6).** Even a 10-line `printHelp()` printed when
   `args.includes('--help')` or when no resource is given would close
   this. Reuse the JSDoc Usage block.
5. **Validate channel name client-side.** SKILL.md says "lowercase, no
   spaces (use hyphens)" — a quick `/^[a-z0-9-]+$/` check in
   `channelCreate`/`channelUpdate` would fail fast with a friendlier
   message than a server 400.
6. **Token redaction scope.** Current regex covers `Bot <token>` shape.
   If the API ever echoes the raw token (unlikely), it'd slip through.
   Consider also redacting any exact match of `config.token` in the
   catch handler.

## Positive Notes

- Clean, single-purpose dispatch; aliases (`ls`, `rm`) are a nice touch.
- 204 handling in `api()` is correct (`DELETE` returns no body).
- Error messages from `api()` include status + body text — easy to debug
  without leaking auth.
- SKILL.md endpoint table is accurate against the script's call sites.
- The `SCRIPT="node $(dirname "$0")/scripts/cove-admin.mjs"` pattern in
  the SKILL.md examples is the right idiom for skill-relative scripts.

**Rating:** ✅ Ready to merge. The remaining items are polish and can land
in a follow-up PR without blocking this one.
