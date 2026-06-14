# PR #348 Round 3 Consolidated Review

**Reviewers:** 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro) · 🌟 Stella (GPT-5.5 — failed, excluded)

---

## R2 Fix Verification

| R2 Issue | R3 Status | Notes |
|----------|-----------|-------|
| 🔴 CI webhook shell injection | ✅ **Fixed** | env + jq -nc, clean idiomatic fix (Nova + Vega) |
| 🟡 OAuth given_name not validated | ✅ **Fixed** | Both OAuth branches now call validateDisplayName (Nova + Vega) |
| 🟡 OAuth re-login COALESCE | ❌ **Regression** | See below — re-introduced the R1 bug (Nova + Vega) |

---

## 🔴 Critical Regression: OAuth COALESCE Overwrites User-Cleared Names (Nova + Vega)

**File:** `packages/server/src/routes/auth.ts`

R3 added `global_name = COALESCE(global_name, ?)` back to the existing-user OAuth UPDATE. This re-introduces the exact R1 concern:

- User clears display name in Settings → `global_name = NULL`
- User's session expires, OAuth re-login fires
- `COALESCE(NULL, given_name)` → display name silently re-filled with Google given_name
- User has to clear again. And again. Every login cycle.

**R2 had fixed this correctly** by not touching `global_name` on re-login at all.

**Fix:** Drop `global_name = COALESCE(...)` from the existing-user UPDATE entirely. Keep seeding only in the new-user `pending_registrations` insert.

Per escalation rule: R1 flagged → R2 fixed → R3 re-broken = **🔴 blocker**.

---

## Other Outstanding Items

| Issue | Status | Severity |
|-------|--------|----------|
| OAuth given_name length unbounded (no 80-char cap) | ❌ Not Fixed | 🟡 New (Nova) |
| Mention map keyed by non-unique display name | ❌ Not Fixed | 🟡 (Vega) |
| Optimistic self-message `global_name: null` | ❌ Not Fixed | 🟡 (Nova + Vega) |
| Missing OAuth re-login preservation test | ❌ Not Fixed | 🟡 → blocker (would have caught the regression) |
| Missing resolveMentions test | ❌ Not Fixed | 🟢 |
| findByToken redundant cast/literal | ❌ Not Fixed | 🟢 nit |

---

## Verdict

| Reviewer | Verdict | Key Finding |
|----------|---------|-------------|
| 🌠 Nova | ❌ Major Issues | COALESCE regression + given_name length + missing tests |
| 💫 Vega | ❌ Major Issues | COALESCE regression + mention collision + optimistic msg |
| 🌟 Stella | ❌ Failed (2 attempts) | — |

### Overall: ❌ Major Issues

The CI and OAuth validation fixes from R2 landed correctly ✅. But R3 re-introduced the exact OAuth COALESCE bug that was reported in R1 and fixed in R2. This is a confirmed regression.

**Before merge (blockers):**
1. **Remove `COALESCE(global_name, ?)` from existing-user OAuth UPDATE** — leave seeding only in pending_registrations
2. **Add OAuth re-login regression test** — set name → re-login → preserved; clear name → re-login → stays null
3. **Cap given_name to 80 chars** at OAuth ingestion

**Should fix:**
4. Fix optimistic self-message `global_name: null` in MessageInput.tsx (one-liner)
5. Fix mention map key collision (use user ID instead of display name)

**Nice to have:**
6. resolveMentions test, findByToken cleanup, stale test titles
