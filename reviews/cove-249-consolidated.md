# Consolidated Review — cove#249: weekend cleanup batch 1 (#210, #187, #243)

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7)

## Summary

Clean, focused batch (86+/60-, 8 files) addressing three issues. The diff is mechanical and easy to follow. Build + 150 tests pass. Two reviewers identified the same product/access-control concern.

## Critical / Blocking

### 🟡 Newly registered users have no guild and no way to join one (Stella, Nova)

After #210, `register.ts` no longer adds new users to the default guild. But:
- There's **no API path for a guildless user to join any guild** — `PUT /guilds/:guildId/members/:userId` requires the acting user to already be a member
- `invite_codes` have no `guild_id` column, so the invite itself can't place them
- Meanwhile, `routes/auth.ts:78-84` **still** auto-joins *existing* OAuth users to the default guild on login

**Result:** New users register → see nothing → stuck. Existing users who left the guild get re-added on next login. Both behaviors are inconsistent with #210's intent.

**Recommendation:**
1. Either also remove the OAuth auto-join in `auth.ts` (and file a follow-up issue for guild invite flow), or
2. Keep the default-guild join for now and address in a separate PR with a proper invite-to-guild mechanism

This is the only thing reviewers disagree on severity: Stella says ⚠️ blocking, Nova says "approve with follow-up." For a personal project, filing a follow-up issue and merging is reasonable.

## Product Impact

- **#210**: New users start with empty guild list — intentional, but needs an onboarding path
- **#187**: Deleted users' WS sessions now forcibly close with 4004 + offline presence broadcast — **good security fix**
- **#243**: Pure cleanup — no user-visible change

## Suggestions (non-blocking)

1. **Add regression test for #210** — assert zero `guild_members` rows after register (Stella, Nova)
2. **Add regression test for #187** — `removeUser()` with multiple sessions: both closed with 4004, offline presence broadcast (Stella, Nova)
3. **Comment on double `removeSession` call** — `removeUser()` calls `removeSession` then `close`, which triggers `ws.on("close")` calling `removeSession` again (idempotent, but surprising)
4. **`missingAccess()` helper unused** — added but not referenced in this diff
5. **`agents.ts` trailing whitespace** — blank line where `const auth` was removed (Nova)
6. **Consider `ErrorCodes` enum** — magic numbers in helpers are still magic numbers, just in fewer places (Nova)

## Positive Notes

- GatewayOpcode enum substitution — textbook magic-number cleanup ✅
- Per-route `requireAuth` removal is correct — global middleware already covers `/api/*` ✅
- `removeUser()` snapshot-then-iterate avoids mutation during iteration ✅
- `removeSession` before `close` ensures presence broadcast while guildIds are still populated ✅
- Well-scoped batch, high signal-to-noise ✅

## Verdict

**⚠️ Needs Minor Changes** — The code itself is correct and clean. The one concern is the asymmetric guild-join behavior (#210 fix is incomplete without also addressing the OAuth auto-join). Options:
1. Fix `auth.ts` in this PR + file follow-up for guild invite mechanism → ✅ merge
2. File follow-up issue acknowledging the gap → ✅ merge with caveat
3. Ship as-is → ⚠️ new users are silently stuck
