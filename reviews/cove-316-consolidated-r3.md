# Consolidated Review R3: PR #316 — channel permission overwrites (bot visibility)

**Reviewers:** 🌟 Stella ❌ | 🌠 Nova ⚠️ | 💫 Vega ❌

---

## R2 Issue Status

| ID | Finding | R2 | R3 |
|----|---------|----|----|
| C1 | Admin auth | ✅ | ✅ |
| C2 | REST gating | ⚠️ escalated | ⚠️ **Still incomplete — re-escalated** |
| C3 | Negative tests | 🟡 | ✅ Now solid (8 tests with code 50013) |
| C4 | Dispatcher events | 🟡 | ✅ Filter in place, but see new issues below |
| C5 | BigInt validation | ✅ | ✅ |
| READY leak | ❌ | ✅ Fixed |

---

## Remaining Critical Issues

### C2 (RE-ESCALATED): GET/PATCH/DELETE `/channels/:id` still ungated (3/3)

The same class of issue for the **third round**. `requireBotChannelPermission` was added to messages, reactions, webhooks, guild channel list, READY — but the 3 direct channel routes were missed again:

- `GET /channels/:id` — leaks channel metadata + `permission_overwrites`
- `PATCH /channels/:id` — denied bot can rename/retopic hidden channels
- `DELETE /channels/:id` — **denied bot can delete hidden channels** (critical product risk)

**Fix:** Add `requireBotChannelPermission` to all three routes in `channels.ts`. This is 3 lines of code.

### NEW: `CHANNEL_DELETE` never reaches authorized bots (Stella, Nova)

Channel is deleted before dispatching → CASCADE removes overwrite rows → `hasPermission` returns false for all bots → authorized bots never learn the channel was deleted. Stale client state until reconnect.

**Fix:** Dispatch before delete, or snapshot eligible sessions pre-delete.

### NEW: `CHANNEL_CREATE` unreachable for bots (Nova)

New channels have no overwrites → default-deny → all bots filtered out of `CHANNEL_CREATE`. When admin later grants VIEW_CHANNEL, no event is emitted. Bot is blind to new channels until reconnect.

**Fix:** Either emit synthetic `CHANNEL_CREATE` on permission grant, or don't filter `CHANNEL_CREATE` (knowing channel exists is not a confidentiality leak).

---

## Suggestions

1. **Webhook resource routes** (`GET/PATCH/DELETE /webhooks/:id`, `GET /guilds/:id/webhooks`) don't check VIEW_CHANNEL on parent channel (Stella, Nova)
2. **Missing negative tests** for webhook routes, READY payload, guild channel list filtering, and the 3 channel routes once gated (Stella, Vega)
3. **Duplicate VIEW_CHANNEL constant** — defined in 3 places, centralize to shared (Nova)
4. **BigInt accepts negative values** — add `>= 0n` check (Nova)

---

## Positive Notes (consensus)

- Negative test coverage is now genuinely strong — 8 tests with Discord error codes
- READY payload filtering works correctly for bots
- Dispatcher channel filter (`broadcastToGuildWithChannelFilter`) is clean and well-factored
- Message/reaction/typing/ack/bulk-delete/clear REST routes all properly gated
- Admin-only permission management working with correct error codes
- 219 tests pass

---

## Overall Verdict: ⚠️ Needs Changes (re-escalated)

C2 is the same gap for the third time: `GET/PATCH/DELETE /channels/:id` ungated. The fix is literally 3 lines. `CHANNEL_DELETE` ordering and `CHANNEL_CREATE` reachability are new but important for the feature to work end-to-end. After these, this should finally be ✅ Ready.
