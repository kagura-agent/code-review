# PR #352 Round 2 Consolidated Review

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Verdict: ⚠️ Needs Changes (unanimous, but minor)**

---

## R1 Critical Issues — ✅ Both Fixed

| R1 Issue | R2 Status |
|----------|-----------|
| 🔴 Bot permission bypass | ✅ Fixed — `requireBotChannelPermission(VIEW_CHANNEL)` on all 4 routes, returns 403/50013 |
| 🔴 Missing bot permission tests | ✅ Fixed — 6 new tests (4 deny, 2 allow) |

**Security gate is closed.** 🎉

---

## R1 Suggestions — Status

| Issue | Status | Notes |
|-------|--------|-------|
| content_type 255-char cap | ✅ Fixed | All 3 agree |
| GET/DELETE filename regex | ✅ Fixed | All 3 agree |
| Buffer.byteLength for cove.md | ✅ Fixed | All 3 agree |
| UI error on save/create | ✅ Fixed | message.error added |
| UI error on delete | ❌ Missing | handleDelete has no try/catch (All 3 flagged) |
| Plugin error swallowing (P1) | ❌ Not Fixed → 🟠 | getChannelFile catches all errors silently; outage indistinguishable from "no cove.md" (Nova escalated) |
| Client state leaks across channels (U2) | ❌ Not Fixed → 🟠 | selectedFile/fileContent persists when switching channels — visible cross-channel data bleed (Nova + Vega) |
| Upsert SELECT + INSERT race | ❌ Not Fixed | Kept 🟡 — single-statement ON CONFLICT would be cleaner (Nova + Vega) |
| Oversize check duplicated | ❌ Not Fixed | Kept 🟡 — tidiness (Nova) |
| Sidebar no refetch on reopen | ❌ Not Fixed | Kept 🟡 — mitigated by deferred #354 (Nova) |
| Rate-limit bucket for file writes | ❌ Not Fixed | Stella escalated to 🟡 |

---

## Recommended Actions Before Merge

**Should fix (small, ~10-20 lines total):**
1. **Delete error toast** — wrap `handleDelete` in try/catch + `message.error` (~3 lines)
2. **Plugin error logging** — distinguish 404 from 5xx in `getChannelFile`, add debug log (~5 lines)
3. **Reset store on channel switch** — clear `selectedFile`/`fileContent` in `fetchFiles` when channelId changes (~5 lines)

**Can defer as follow-ups:**
4. Upsert simplification (S2)
5. Remove duplicate oversize check (S3)
6. Sidebar refetch on reopen (U3, covered by #354)
7. Rate-limit bucket extension
8. Granted-bot update/delete tests (Stella's partial coverage note)

---

## Verdict Summary

| Reviewer | Rating | Key Remaining Concern |
|----------|--------|----------------------|
| 🌟 Stella | ⚠️ Needs Changes | Rate-limit bucket + delete error |
| 🌠 Nova | ⚠️ Needs Changes (minor) | Plugin error swallowing + store leak |
| 💫 Vega | ⚠️ Needs Changes | State leaks + redundant requests |

### Overall: ⚠️ Needs Changes (minor)

R1's critical security issues are properly fixed. This PR is close to mergeable. Three small fixes (delete toast, plugin error logging, store reset on channel switch) would clear it. Everything else can ship as follow-ups.
