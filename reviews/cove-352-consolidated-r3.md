# PR #352 Round 3 Consolidated Review

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

---

## R2 Fix Verification

| R2 Issue | R3 Status | Notes |
|----------|-----------|-------|
| Delete error toast | ✅ Fixed | All 3 agree — try/catch + message.error |
| Plugin getChannelFile selective catch | ⚠️ Partially Fixed | rest-client now rethrows non-404/403, BUT dispatch.ts outer catch {} re-swallows everything (Nova). Regex status matching is fragile (Nova). |
| Store state leak across channels | ✅ Fixed | selectedFile/fileContent/editing cleared on channelId change (Nova + Vega). Stella notes `files` array not cleared but this is minor flash, not data leak. |

---

## Remaining Issue: Plugin Error Handling (P1)

Nova identified a genuine gap — the rest-client fix is correct but the dispatch.ts call site defeats it:

1. **dispatch.ts `catch {}` re-swallows everything** — the selective rethrow from rest-client is caught again with no log. Operators can't distinguish "no cove.md" from "server down".
2. **Regex status matching is fragile** — `\b(404|403)\b` in error message could match filenames like `404.md`. Should use typed `CoveApiError.status` instead.
3. **No dedicated timeout** — cove.md fetch uses default 30s + retries on the hot dispatch path. Should be ≤3s, no retries.

**Fix (small):**
- Add `logger.warn` in dispatch.ts for non-404/403 errors (~2 lines)
- Use typed error status instead of regex (~5 lines)
- Pass short timeout for cove.md fetch (~3 lines)

---

## Reviewer Calibration Note

Vega escalated "redundant network requests" and "silent 8KB limit" to ❌ Major Issues. These are optimization/UX polish items, not functional bugs:
- Redundant requests: 3 instead of 1 on save — performance nit, not broken functionality
- Silent 8KB limit: a product decision about truncation vs. skip — not data corruption or security

Per review standard: "Needs Changes means the PR will cause real problems if merged as-is — bugs, security holes, data loss, broken builds. It does NOT mean 'could be cleaner'."

---

## Verdict Summary

| Reviewer | Rating | Key Concern |
|----------|--------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | files array flash on channel switch |
| 🌠 Nova | ⚠️ Needs Changes | P1 dispatch swallow + regex + timeout |
| 💫 Vega | ❌ Major Issues | Over-escalated optimization items |

### Overall: ⚠️ Needs Changes (minor)

Security is solid (R1 criticals fixed since R2). All R2 items addressed except P1 gap in dispatch.ts. One more small pass (~10 lines) to fix the plugin error logging + typed errors + timeout, then this is ✅ Ready.

If the team prefers velocity: merge now with a follow-up issue for P1 hardening. The current behavior (cove.md silently unavailable on server error) is graceful degradation, not broken functionality.
