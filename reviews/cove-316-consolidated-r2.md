# Consolidated Review R2: PR #316 — channel permission overwrites (bot visibility)

**Reviewers:** 🌟 Stella ❌ | 🌠 Nova ⚠️ | 💫 Vega ❌

---

## R1 Issue Status

| ID | Finding | R1 | R2 |
|----|---------|----|----|
| C1 | Permission routes lack admin auth | ❌ | ✅ Fixed — bots rejected with 403/50013 |
| C2 | REST not gated by VIEW_CHANNEL | ❌ | ⚠️ **Partially fixed — ESCALATED** |
| C3 | Missing negative auth tests | ❌ | 🟡 Partially — tests only cover fixed routes |
| C4 | Dispatcher event filtering | ❌ | 🟡 Mostly fixed — channel lifecycle events still leak |
| C5 | BigInt validation | ❌ | ✅ Fixed — try/catch + 400 |

---

## Remaining Critical Issues

### C2 (ESCALATED): REST gating applied to only 2 of ~10 channel routes (3/3)

`requireBotChannelPermission` was added to `GET/POST /channels/:id/messages` and webhooks, but **all other channel-scoped routes are still unprotected**:

- `GET /channels/:id` — leaks channel metadata + permission overwrites
- `GET /channels/:id/messages/:msgId` — single message read
- `PATCH /channels/:id/messages/:msgId` — edit messages
- `DELETE /channels/:id/messages/:msgId` — delete messages
- `POST /channels/:id/messages/bulk-delete`
- `DELETE /channels/:id/messages` — clear all
- `PUT /channels/:id/messages/:msgId/ack` — acknowledge
- `POST /channels/:id/typing` — typing indicator (humans still see it)
- `PUT/DELETE/GET reactions` — all 3 reaction routes

**Fix:** Apply `requireBotChannelPermission` to ALL `/channels/:id/...` routes. Consider a middleware/wrapper to avoid per-route duplication.

### NEW: READY payload leaks full channel list to bots (Nova)

`ws/session.ts:48-50` sends all channels (with `permission_overwrites`) to every bot at identify time. A bot with zero VIEW_CHANNEL still learns all channel IDs, names, topics, and which other bots have access. This directly contradicts "default deny."

**Fix:** Filter channels in READY payload for bot sessions, same as the `GET /guilds/:guildId/channels` fix.

### C4 follow-up: Channel lifecycle events still unfiltered (Stella, Nova)

`CHANNEL_CREATE/UPDATE/DELETE` in `dispatcher.ts:99-107` still use `broadcastToGuild`. Denied bots receive hidden channel objects live, including overwrites on UPDATE.

---

## Suggestions

1. **Extract middleware** — centralize VIEW_CHANNEL check for all `/channels/:id/...` routes (all 3)
2. **Negative tests for all gated routes** — at minimum single message GET + reactions (Nova, Vega)
3. **Duplicate VIEW_CHANNEL constant** — `1n << 10n` defined inline in 3 places, import from shared (Nova)
4. **BigInt bounds** — add `>= 0n` and `< (1n << 64n)` check (Nova)
5. **N+1 enrichment query** — batch `listByChannel` calls (Nova)

---

## Positive Notes (consensus)

- C1 fix is solid — bots rejected with Discord error code 50013
- C5 fix works — try/catch prevents dispatcher crashes
- `permissions.test.ts` is well-structured with 4 negative test cases
- CASCADE tested, admin user header migration done consistently
- Dispatcher filtering for messages/typing/reactions is clean
- Core design is sound — this is finish-the-job work, not a redesign

---

## Overall Verdict: ⚠️ Needs Changes (escalated)

C2 is the main blocker — most channel routes are still unprotected. The fix is mechanical (one line per route + tests), not architectural. READY payload filtering should also land in this PR. After that, this should be ✅ Ready.
