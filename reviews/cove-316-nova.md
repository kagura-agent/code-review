# Nova Review — PR #316 (Round 5, final)

**PR**: `feat: channel permission overwrites — bot visibility control (closes #315)`
**Branch**: `feat/channel-permissions` · State: OPEN · +1072 / -97 / 27 files

## Summary
Round 5 closes the last gap from R4: the four missing negative tests for
channel‑level `VIEW_CHANNEL` enforcement on `/channels/:id` GET/PATCH/DELETE
and on the guild channel list have been added, all C1–C5 / READY / channel
lifecycle fixes from earlier rounds remain in place, and CI shows 12 test
files / **223 tests passing** on the head commit. Verdict: ✅ Ready.

## Verification

### 1. New negative tests present and correctly targeted
File `packages/server/src/__tests__/permissions.test.ts` adds a new
`describe("Channel route VIEW_CHANNEL enforcement", …)` block (diff lines
915–989) with a dedicated `beforeEach` that seeds:
- an admin user (`bot=1`, joined to default guild),
- a `denied-bot` user (`bot=1`, joined, **no** permission overwrite),
- `general` channel from `seedChannels`.

The four added cases hit exactly the previously‑uncovered routes:

| Test | Path | Method | Asserts |
|---|---|---|---|
| `denied bot cannot GET /channels/:id` | `${API_PREFIX}/channels/${generalId}` | GET | `status === 403` |
| `denied bot cannot PATCH /channels/:id` | same | PATCH (`{name:"hacked"}`) | `status === 403` |
| `denied bot cannot DELETE /channels/:id` | same | DELETE | `status === 403` |
| `denied bot gets filtered guild channel list` | `${API_PREFIX}/guilds/${guildId}/channels` | GET | `status === 200` and `channels.every(ch => ch.id !== generalId)` |

These map 1:1 to the three `requireBotChannelPermission(...) → 403 {code:50001}`
guards added in `routes/channels.ts` (GET/PATCH/DELETE on `/channels/:id`,
diff lines 1349–1369, 1376–1389, 1403–1416) and to the new bot‑aware
`filter(...)` in `GET /guilds/:guildId/channels` (diff lines 1340–1348).
The list‑filter test goes a step further by granting `VIEW_CHANNEL` (bit
1024) to admin only, so the assertion proves the channel disappears
because the bot lacks an explicit allow (correct overwrite semantics),
not just because the channel is missing.

Combined with the earlier (R≤4) cases in the same file — `denied bot
cannot read/send/PATCH/DELETE messages`, `cannot react / unreact`,
`cannot use typing indicator`, plus the WS dispatch positive/negative
pair — every public surface gated by `requireBotChannelPermission` now
has a 403 / filtered‑result negative test. The `Missing Access` (50001)
vs `Missing Permissions` (50013) split between channel routes and
message/reaction routes is preserved exactly as the code returns; tests
only assert the status code, so the split is not asserted but also not
contradicted (acceptable).

### 2. 223 tests pass
- GitHub Actions `test` job on the head commit:
  `Test Files 12 passed (12)`, `Tests 223 passed (223)`,
  duration 3.02 s (run 27334310564, job 80754365738, both `test` and
  `deploy` checks green).
- Local reproduction was attempted but blocked by an unrelated
  `better-sqlite3` native build issue in this sandbox (no prebuilt
  binary for Node 24.16 and `node-gyp rebuild` hung). CI is the
  authoritative signal here; the test source is what I reviewed.

### 3. Fresh re‑evaluation (anti‑confirmation bias)
Looked again for things the new tests still don't cover:

- **Negative tests don't verify `code: 50001` body**, only the 403
  status. Minor — earlier message/reaction negatives in the same file
  also only assert status; consistent and fine.
- **No positive test for "bot WITH VIEW_CHANNEL can GET /channels/:id"**.
  Strictly the positive side of channel‑route enforcement is implicit
  (admin in the new block isn't exercised on these routes; existing
  api.test.ts coverage relies on non‑bot users). Not blocking — the
  helper is symmetric and the negative side proves the gate fires;
  the existing dispatcher positive/negative pair plus the message‑route
  positive tests in api.test.ts already exercise the
  `requireBotChannelPermission(... isBot=true) → allow` path for bots
  that have the permission via the dispatcher tests
  (`bot WITH VIEW_CHANNEL receives dispatched events`).
- **`requireBotChannelPermission` short‑circuits on `!isBotUser`** —
  non‑bot users keep current behaviour; covered indirectly by the
  pre‑existing api.test.ts suite (still green).
- Guard ordering in routes is correct: `requireGuildMember` first
  (→ 404 for outsiders, preserving info‑leak hygiene), then the
  permission check (→ 403 for members lacking VIEW_CHANNEL). Matches
  Discord semantics.
- Filter implementation in `GET /guilds/:guildId/channels` runs the
  permission check per channel inside `.filter(...)`. With current
  `repos.permissions.hasPermission` (single SQL lookup per call), this
  is O(N) per list call — fine for realistic guild sizes; not a
  blocker. Worth keeping in mind if guild channel counts grow large
  (could be batched), but explicitly out of scope here.

No new regressions spotted. Nothing else from R1–R4 has slipped.

## Critical Issues
None.

## Product Impact
Unchanged from R4 assessment: bots without `VIEW_CHANNEL` are now
consistently invisible from both message/reaction routes **and**
channel CRUD / listing, matching the PR's stated goal of bot
visibility control. The filtered list behaviour is the user‑facing
change most likely to surprise integrators; the new test pins it down.

## Suggestions (non‑blocking, optional)
1. Consider asserting the JSON error code (`50001` for channel routes,
   `50013` for message routes) in at least one negative test per
   group, so future refactors don't silently swap the Discord error
   code while keeping the 403.
2. Add a single positive `denied bot WITH VIEW_CHANNEL CAN GET
   /channels/:id` case alongside the new negatives — cheap and makes
   the new block fully symmetric.
3. If guild channel counts ever grow large, batch
   `permissions.hasPermission` into one query per
   `GET /guilds/:guildId/channels`.

## Positive Notes
- Test seeding mirrors the dispatcher block (same admin/denied‑bot
  pattern), keeping the file coherent and easy to extend.
- The list‑filter test uses a real allow overwrite for admin rather
  than just relying on default behaviour, which proves the filter is
  driven by `hasPermission` and not by an unrelated default.
- Author addressed every R1–R4 blocker without scope drift; the diff
  for R5 is exactly the four tests requested.

## Verdict
✅ **Ready** — merge.
