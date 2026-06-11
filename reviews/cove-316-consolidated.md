# Consolidated Review: PR #316 — feat: channel permission overwrites (bot visibility)

**Reviewers:** 🌟 Stella ❌ | 🌠 Nova ⚠️ | 💫 Vega ❌

---

## Critical Issues (consensus — all 3 reviewers agree)

### C1: Permission routes lack admin authorization — bots can self-grant access (3/3)
`PUT/DELETE /channels/:channelId/permissions/:targetId` only checks `requireGuildMember`. Any guild member, including a denied bot, can call `PUT` with `allow=VIEW_CHANNEL` on its own ID and bypass the entire default-deny model. The PR's headline guarantee is not enforced server-side.
**Fix:** Restrict to human users or a MANAGE_CHANNELS/admin equivalent. Add negative test for unauthorized callers.

### C2: REST endpoints not gated by VIEW_CHANNEL (3/3)
Filter is only on the WS dispatcher path. A denied bot can still:
- `GET /channels/:id` — discover hidden channels
- `GET /channels/:id/messages` — read full message history
- `POST /channels/:id/messages` — post messages
- React, type, acknowledge in channels it should not see

**Fix:** Add VIEW_CHANNEL check to REST routes, or explicitly scope-out and document as MVP limitation.

### C3: Missing negative auth tests for permission mutation (3/3)
No tests proving unauthorized callers get 403 when modifying overwrites. Review standard requires both positive and negative tests for new auth gates.

---

## Critical Issues (consensus — 2/3)

### C4: Dispatcher only filters MESSAGE_CREATE/UPDATE/DELETE — other events leak (Stella, Nova)
`broadcastToGuildWithChannelFilter` is only wired for 3 event types. Denied bots still receive:
- `MESSAGE_DELETE_BULK`, `TYPING_START`, `MESSAGE_REACTION_ADD/REMOVE`
- `CHANNEL_CREATE/UPDATE/DELETE` for hidden channels
- READY payload includes all channels

### C5: `allow`/`deny` BigInt validation missing — malformed values crash dispatcher (Stella, Nova)
Route accepts any string, stores it. `BigInt(row.allow)` on the dispatcher hot path throws `SyntaxError` on invalid values like `"abc"`, potentially breaking event delivery for the entire guild.
**Fix:** Validate as `/^\d+$/` with length cap. Consider try/catch in `hasPermission` to fail closed.

---

## Suggestions (non-blocking)

1. **N+1 query** — `list()` calls `listByChannel()` per channel; batch with `WHERE channel_id IN (...)` (Nova, Vega)
2. **Dispatcher fails open** when `permissionsRepo` is null — inject via constructor or fail closed (Nova)
3. **`target_type` not in PK** — `(channel_id, target_id)` could collide if roles share IDs with members (Nova)
4. **Client error handling** — `handleToggleBotPermission` doesn't surface 403 errors to UI (Nova)
5. **Stale migration test comments** — still say "user_version = 8" while asserting 9 (Nova)

---

## Positive Notes (consensus)

- Migration is additive with `ON DELETE CASCADE`, tested
- `PermissionsRepo.upsert` uses `ON CONFLICT DO UPDATE` — clean and idempotent
- Bitfield as string + BigInt is the right approach for JSON safety, matches Discord
- Bot-vs-human branching correctly bypasses humans
- UI toggle is clean and feature-flagged
- Tests cover CRUD, cascade delete, dispatcher filtering, and validation

---

## Overall Verdict: ❌ Major Issues

The PR's core promise ("default deny — bots need explicit authorization") is undermined by:
1. Bots can self-grant access (C1)
2. REST is completely unfiltered (C2)
3. Only 3 of many event types are filtered (C4)

These need to be addressed or the scope explicitly narrowed in the PR description before merge.
