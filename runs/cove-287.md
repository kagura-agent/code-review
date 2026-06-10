# Run Record: cove#287

**Date:** 2026-06-10
**PR:** feat: add resolver.resolveTargets to Cove plugin
**Verdict:** ⚠️ Needs Changes
**Round:** 1

## Consensus Critical
1. `resolveAccount()` throws on missing token — makes `missingTokenNote` dead code (3/3)
2. `mapResolved` leaks `guildId` into `id`/`name` on unresolved entries (2/3)

## Consensus Suggestion
3. No new tests for resolver paths (2/3)

## Unique Findings
- Stella: `resolveAccount` also throws on missing `agentId` (not needed for resolution) — Critical
- Stella: Consider `#channel-name` prefix stripping for CLI
- Stella: Duplicate channel names silently pick first match
- Nova: `getChannels()` API errors unhandled — crash on network failure
- Nova: User-kind branch unnecessarily wraps `resolveTargetsWithOptionalToken`
- Vega: Same as Nova on `getChannels` error handling

## Reviewer Assessment
| Reviewer | Rating | Unique Finds | Notes |
|----------|--------|-------------|-------|
| Stella | ⚠️ | 3 | Caught agentId throw (unique), good product thinking |
| Nova | ⚠️ | 2 | Most detailed, code-level precision, caught mapResolved leak clearly |
| Vega | ✅ | 1 | Concise but missed Critical #1 severity — flagged as suggestion not critical |

## Blind Spots
- None of the reviewers verified whether the `resolveTargetsWithOptionalToken` import path (`openclaw/plugin-sdk/target-resolver-runtime`) is actually in the SDK's exports map
- Pattern: "resolveAccount throws before SDK helper can handle graceful failure" — this is a **resolver vs runtime config** pattern. Could add to prompt: "When reviewing resolver/target-resolution code, verify that config loading does not throw before the resolution helper can return structured unresolved results."

## Prompt Evolution
- No prompt change needed yet — the `resolveAccount` throw pattern is project-specific, not a general dimension. If it repeats in another PR, escalate to prompt.

## Process
- FlowForge ran smoothly. plan_review was auto-skipped (1 file PR).
- All 3 reviewers completed within ~4 minutes.

---

## Round 2

**Verdict:** ✅ Ready (3/3)

### R1 Issue Status — All Fixed
1. ✅ `resolveAccount` throw → new `readAccountConfig` (non-throwing)
2. ✅ `mapResolved` guildId leak → gated by `entry.resolved`
3. ✅ Missing tests → 7 test cases in `resolver.test.ts`
4. ✅ `agentId` throw → `readAccountConfig` doesn't check it
5. ✅ `getChannels` error → wrapped in try/catch

### Non-blocking suggestions
- `err: any` → `err instanceof Error ? err.message : String(err)` (Stella + Nova)
- `cfg: any` could use minimal typed shape (Nova)
- `mapResolved` drops `guildId` on resolved entries — check SDK contract (Nova)

### Reviewer Assessment
| Reviewer | Rating | Notes |
|----------|--------|-------|
| Stella | ✅ | Verified build+tests, caught err:any nit |
| Nova | ✅ | Most detailed, 6 non-blocking suggestions |
| Vega | ✅ | Concise, no issues found |
