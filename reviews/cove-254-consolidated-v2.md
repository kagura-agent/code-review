# Consolidated Review (Updated) — cove#254: remove hardcoded guild ID from plugin

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

## Summary

Tiny PR (10+/4-, 4 files) removing hardcoded `"cove"` guild ID from plugin source code. Gateway client captures guilds from READY. Rest client requires explicit guildId. `CoveAccount.guildId` becomes `string | null`.

## Critical / Blocking

### 🟡 `openclaw.plugin.json` still has `"default": "cove"` (Stella)

`packages/plugin/openclaw.plugin.json:23`:
```json
"guildId": { "type": "string", "default": "cove" }
```

If OpenClaw applies schema defaults before `resolveAccount()`, then `section?.guildId` will always be `"cove"`, making the `?? null` fallback in `channel.ts:131` unreachable. The PR title says "remove hardcoded guild ID" but the config manifest still hardcodes it.

**Fix:** Remove `"default": "cove"` from the manifest, or make `guildId` optional with no default.

## Suggestions (non-blocking)

1. **`guilds` field is write-only** (Nova) — Captured from READY but nothing reads it. Follow-up needed: `account.guildId ??= guilds[0]?.id` or similar hydration.
2. **README still shows `guildId: cove`** (Stella) — Encourages new installs to hardcode.
3. **`bundle.js` still has old defaults** (Stella) — Tracked file with `"cove"` fallback.
4. **No `ReadyEventData` type** (Nova) — Inline cast duplicates protocol shape; extract to `@cove/shared`.

## Positive Notes

- Type-honest: `string | null` reflects reality ✅
- Zero regression risk — no downstream consumers of `account.guildId` or `getChannels` exist (Nova verified) ✅
- Tight blast radius: 4 files in `packages/plugin/src` ✅
- PR body's "Not changed" section is excellent scope control ✅

## Verdict

**⚠️ Needs Minor Change** — Source code is correct, but the plugin manifest `default: "cove"` undermines the refactor. Remove the default → ✅ Ready.
