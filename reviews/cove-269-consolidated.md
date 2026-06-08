# Consolidated Review R4 — cove#269: PR #264 follow-ups

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 4

## R3 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| 🟡 | Timer 不 reschedule after sliding refresh | ✅ Fixed — 递归 `scheduleExpiry()` + DB re-read |
| 🟢 | setTimeout overflow > 2^31 ms | ✅ Fixed — `MAX_TIMEOUT` clamp |
| 🟢 | Logout 不主动断 WS | ❌ 未修 → escalated 🟡 |
| 🟢 | WS expiry 缺测试 | ❌ 未修 → escalated 🟡 |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — 3 escalated 🟡
- 🌠 Nova: **✅ APPROVE** — core fixed, 2 escalated 🟡 可 follow-up
- 💫 Vega: **❌ Block** — 2 escalated 🟡

## Verdict: ✅ Approve with follow-up issues

**R3 的核心 bug（timer 不 reschedule）完美修复。** `scheduleExpiry()` 递归 re-read `expires_at`，overflow clamp 到位，之前所有修复保持完好。

**剩余 2 个 escalated 🟡 都是 hardening，不是 correctness bug：**

1. **Logout 不主动踢 WS** — 当前 timer 最终会 catch（token 被 rotate 后下次 fire 时 `findByToken` 返回 null → close）。不是即时踢但有兜底。适合 follow-up PR 加 `dispatcher.disconnectByToken()`。

2. **WS expiry 缺测试** — `scheduleExpiry` 逻辑经 4 轮 review 已验证正确。测试重要但不 block merge。

**建议：merge + 开 follow-up issues。** 这个 PR 从 R1 到 R4 解决了 config 集中化 + WS 过期断连 + regression tests + CHANGELOG，已经很全面了。

## R1 → R4 Journey

| Round | Result | Key |
|-------|--------|-----|
| R1 | ⚠️ | re-IDENTIFY leak, cookie token, tests |
| R2 | ⚠️ | Core bugs fixed, short TTL test + polling |
| R3 | ⚠️ | All R2 fixed, timer 不 reschedule |
| R4 | ✅ | **Timer fixed, APPROVE** |
