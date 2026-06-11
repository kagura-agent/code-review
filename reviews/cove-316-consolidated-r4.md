# Consolidated Review R4: PR #316 — channel permission overwrites (bot visibility)

**Reviewers:** 🌟 Stella ⚠️ | 🌠 Nova ✅ | 💫 Vega ⚠️

---

## R3 Issue Status — ALL CODE FIXES CONFIRMED ✅

| ID | Finding | R4 Status |
|----|---------|-----------|
| C1 | Admin auth | ✅ |
| C2 | REST gating (3rd time) | ✅ **Finally fixed** — GET/PATCH/DELETE /channels/:id + guild list all gated |
| C3 | Negative tests | ✅ (messages/reactions/typing) |
| C4 | CHANNEL_CREATE/DELETE | ✅ Intentionally unfiltered via `broadcastToGuild` |
| C5 | BigInt validation | ✅ |
| READY leak | ✅ |

**The code is correct.** All three reviewers confirm C2 is closed. `requireBotChannelPermission` helper extracted cleanly in `routes/helpers.ts`.

---

## One Remaining Item: Missing negative tests for channel routes (2/3)

Stella and Vega flag as blocking per review standard ("auth paths without tests = Critical"):
- `denied bot GET /channels/:id → 403`
- `denied bot PATCH /channels/:id → 403`
- `denied bot DELETE /channels/:id → 403`
- `denied bot GET /guilds/:id/channels → channel filtered from list`

Nova also recommends these tests but doesn't block on them ("cheap, ~10 min").

These are the routes that regressed across R1→R2→R3 — regression tests are the right hedge.

---

## Suggestions (non-blocking, all from Nova)

1. **Add 2-line comment** in `dispatcher.ts` explaining why CHANNEL_CREATE/DELETE are intentionally unfiltered while CHANNEL_UPDATE is filtered
2. **Make `permissionsRepo` required** in `setupGateway`/`identify` — optional parameter is a silent regression vector
3. **Centralize `VIEW_CHANNEL` bit** — `1n << 10n` redeclared in 3 places, should import from shared
4. **BigInt bounds** — add `>= 0n` and upper bound check

---

## Positive Notes (consensus)

- C2 is definitively fixed with a clean centralized helper — no more copy-paste drift
- CHANNEL_CREATE/DELETE → `broadcastToGuild` elegantly sidesteps both CASCADE ordering and no-overwrites-on-new-channel problems
- `requireBotChannelPermission` helper cleanly bypasses humans, one source of truth
- Negative test suite for messages/reactions/typing is genuinely strong (8 tests with code 50013)
- 219 tests pass, builds pass
- Core design is sound — 4 rounds refined a solid permission system

---

## Overall Verdict: ⚠️ Needs Changes (almost there!)

Code is 100% correct. Just add 3-4 negative tests for the channel routes (same pattern as existing message tests) and this is ✅ Ready. Should take ~10 minutes.
