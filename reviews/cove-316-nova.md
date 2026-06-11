# 🌠 Nova — Round 4 Re-Review · PR #316 (cove)

**PR:** feat: channel permission overwrites — bot visibility control (#316)
**State:** OPEN · +997 / −97 · 27 files · 219 tests pass
**Round:** R4 (re-review after R3 fixes)
**Reviewer:** Nova (anti-confirmation bias mode)

---

## TL;DR

R3’s two unresolved items (C2 REST gating + C4 CHANNEL_CREATE/DELETE filtering) were addressed **as the author described**:

- ✅ `GET/PATCH/DELETE /channels/:id` now call `requireBotChannelPermission` → 403 `Missing Access` for bots without VIEW_CHANNEL.
- ✅ A shared helper `requireBotChannelPermission()` was extracted into `routes/helpers.ts` (no copy-paste; humans bypass via `isBotUser=false`).
- ✅ `GET /guilds/:id/channels` now filters the list for bots (was not gated before; this is a small bonus fix).
- ⚠️ `CHANNEL_CREATE` / `CHANNEL_DELETE` are **intentionally** unfiltered (`broadcastToGuild`). Documented intent confirmed in dispatcher.ts but **no negative tests and no comment in source** explaining why.

Net: C2 is finally closed. C4 is partially closed (CHANNEL_UPDATE filtered, CHANNEL_CREATE/DELETE deliberately not) and should be downgraded to a **documentation/test gap**, not a blocker.

**Verdict: APPROVE with two non-blocking nits.**

---

## 1. Verify C2 fix — REST gating on `/channels/:id`

`packages/server/src/routes/channels.ts` (post-fix):

```ts
app.get("/channels/:id", (c) => {
  const user = c.get("botUser");
  const channel = requireGuildMember(repos, id, user.id);
  if (!channel) return unknownChannel(c);
  if (!requireBotChannelPermission(repos, id, user.id, user.bot)) {
    return c.json({ message: "Missing Access", code: 50001 }, 403);
  }
  return c.json(channel);
});
```

Same pattern applied to `PATCH /channels/:id` and `DELETE /channels/:id`. ✅

`routes/helpers.ts`:
```ts
export function requireBotChannelPermission(repos, channelId, userId, isBotUser) {
  if (!isBotUser) return true;
  const VIEW_CHANNEL = 1n << 10n;
  return repos.permissions.hasPermission(channelId, userId, VIEW_CHANNEL);
}
```

Clean, centralized, humans bypass. **C2 closed (3rd-time charm).** ✅

Bonus: `GET /guilds/:guildId/channels` list now also filters per-channel for bots — addresses a related leak I would have flagged on fresh review.

### Nit C2.1 — Magic bit literal repeated 3×
`1n << 10n` is now redeclared in:
- `routes/helpers.ts`
- `ws/dispatcher.ts` (`VIEW_CHANNEL_BIT`)
- `ws/session.ts` (`VIEW_CHANNEL_BIT`)
- `shared/src/types.ts` (`PermissionFlags.VIEW_CHANNEL` as string)

`PermissionFlags.VIEW_CHANNEL` already exists in `@cove/shared` as the canonical source — but it’s a `string`, not a `bigint`, so callers can’t cleanly reuse it for bitfield math. **Suggestion (follow-up, not blocking):** export a `PermissionBits = { VIEW_CHANNEL: 1n << 10n, … }` const from shared so the bit lives in exactly one place. Low risk of drift now (3 copies), but the next perm bit (SEND_MESSAGES gating on send routes?) will tempt more duplication.

---

## 2. Verify C4 — CHANNEL_CREATE / CHANNEL_DELETE dispatch

Confirmed in `ws/dispatcher.ts`:

```ts
channelCreate(channel: Channel): void {
  this.broadcastToGuild(channel.guild_id, "CHANNEL_CREATE", channel);
}
channelUpdate(channel: Channel): void {
  this.broadcastToGuildWithChannelFilter(channel.guild_id, channel.id, "CHANNEL_UPDATE", channel);
}
channelDelete(guildId: string, channelId: string): void {
  this.broadcastToGuild(guildId, "CHANNEL_DELETE", { id: channelId, guild_id: guildId });
}
```

Author’s claim: this is **intentional** — at create time the new channel has no overwrites so every bot would be filtered out (unreachable); at delete time the bot may need the event to clean local state.

Fresh-eyes evaluation:

- **CHANNEL_CREATE unfiltered is defensible but leaks metadata.** A brand-new channel has no overwrites, so under the current “default deny” rule no bot has access. Broadcasting CHANNEL_CREATE to all bots therefore tells every bot the channel `name`, `topic`, `id`, `nsfw` flag, etc. — for a channel they cannot subsequently access via REST or WS. The cleaner Discord-parity behavior is: *don’t emit CHANNEL_CREATE to a bot until that bot is granted VIEW_CHANNEL*, then emit it on the PUT-overwrite path. That’s out of scope for this PR though, and the leak is minor (name + topic).
- **CHANNEL_DELETE unfiltered is the right call.** Even a bot that lost access still needs to know the channel is gone so its cache stops referencing it. Discord does ship CHANNEL_DELETE broadly. ✅
- **CHANNEL_UPDATE filtered is correct** — matches Discord. ✅

### Findings on C4

**M1 (medium, documentation):** No source comment in `dispatcher.ts` explaining why `channelCreate` and `channelDelete` deliberately bypass the filter while `channelUpdate` doesn’t. The asymmetry will look like a bug to the next maintainer (and it tripped two rounds of review already). Add a 2-line comment.

**M2 (medium, test gap):** No negative test asserting the new REST gates:
- `denied bot GET /channels/:id → 403`
- `denied bot PATCH /channels/:id → 403`
- `denied bot DELETE /channels/:id → 403`
- `denied bot GET /guilds/:id/channels → channel filtered out of list`

The test file has parallel coverage for messages/reactions/typing (good) but skips the channel routes that were the entire C2 regression. Given C2 regressed twice (R1→R2→R3), a regression test is the right hedge.

---

## 3. Fresh review of new/changed code

### 3.1 `permissions.ts` repo — solid

`hasPermission` correctly checks `(allow & bit) !== 0n && (deny & bit) === 0n`. BigInt arithmetic, no number coercion. ✅

Default deny on missing row is the documented behavior. ✅

### 3.2 `routes/permissions.ts` — solid, two nits

- PUT/DELETE correctly reject bots (`50013`). ✅
- Validates `BigInt(allow)` / `BigInt(deny)` parseability. ✅
- **Nit P1:** Negative bigint strings (`"-1"`) parse successfully but make no semantic sense for a bitfield. Not a security issue (bit-ops still defined) but worth a `>= 0n` check.
- **Nit P2:** No upper bound on `allow`/`deny` — a client could store `"9999999999999999999999999"`. Harmless (TEXT column), but a sanity cap matches Discord (which uses 64-bit).
- **Nit P3:** `targetId` is not validated to exist as a user or role. A bot is created with overwrites for `target_id="ghost"` and the row sits there forever. Cleanup relies on FK CASCADE only on the channel side, not the target side. Out of scope for MVP but flagging.

### 3.3 `ws/dispatcher.ts` — `broadcastToGuildWithChannelFilter` — solid

```ts
private broadcastToGuildWithChannelFilter(guildId, channelId, event, data) {
  for (const session of this.sessions) {
    if (!session.guildIds.has(guildId)) continue;
    if (session.user?.bot && this.permissionsRepo) {
      if (!this.permissionsRepo.hasPermission(channelId, session.user.id, VIEW_CHANNEL_BIT)) {
        continue;
      }
    }
    session.dispatch(event, data);
  }
}
```

- Humans bypass ✅
- `permissionsRepo == null` (test/init race) → falls through to broadcast → in production this can never be null since `index.ts` wires it before `setupGateway`. Acceptable defensive fallback. ✅
- **Perf nit D1:** Every dispatched event now does N DB queries (one per matching session) instead of one in-memory check. For a hot channel with many bots, that’s a synchronous SQLite hit per message per bot. Consider memoizing per-call (compute the allowed-bot-set once, then filter sessions). Not a blocker — better-sqlite3 is fast and chats aren’t Twitter-scale — but worth a TODO.

### 3.4 `ws/session.ts` — READY filtering

`identify()` filters channels per bot for the READY payload using `permissionsRepo.hasPermission(...)`. Matches the REST list filter behavior. ✅

**Nit S1:** If `permissionsRepo` is omitted (the optional parameter), bots get **all** channels in READY (`user.bot && permissionsRepo` short-circuits to else branch → `allChannels`). The `setupGateway` signature also makes it optional. In practice `index.ts` always passes it, but a test or future caller that forgets it silently regresses the leak. **Suggest:** make `permissionsRepo` required (non-optional) in both `setupGateway` and `identify`. Type-system fence against the regression that motivated this whole PR.

### 3.5 Migrations — `v9-permissions.ts`

- `IF NOT EXISTS` + composite PK + FK CASCADE ✅
- Stores `allow`/`deny` as TEXT (correct for >53-bit bitfields) ✅
- **Nit Mig1:** No index on `target_id`. `hasPermission` queries by `(channel_id, target_id)` which hits the PK — fine. But `listByChannel(channel_id)` also uses the PK prefix → also fine. ✅ No index needed.

### 3.6 Client — `ChannelSettings.tsx`

Did not deep-review (out of security scope), but spot-check shows:
- Permission toggle PUTs `{ type: 1, allow: VIEW_CHANNEL, deny: "0" }` and DELETEs to remove. Matches server contract. ✅
- Renders a list of bot members with a switch. Reasonable MVP UX.

---

## 4. Status of previous findings

| ID | R3 status | R4 status | Notes |
|----|-----------|-----------|-------|
| C1 admin auth | ✅ | ✅ | unchanged |
| **C2 REST gating** | ⚠️ re-escalated | ✅ **fixed** | helper extracted, all 3 routes gated, list also filtered |
| C3 negative tests | ✅ | ✅ | still missing for channel routes (see M2) |
| C4 CHANNEL_CREATE/DELETE | ⚠️ ordering + unreachable | ⚖️ intentional | downgrade to M1 (comment) + M2 (tests) |
| C5 BigInt | ✅ | ✅ | unchanged |
| READY leak | ✅ | ✅ | unchanged (but see S1) |

---

## 5. New findings this round

| ID | Severity | Where | Issue |
|----|----------|-------|-------|
| M1 | medium | `ws/dispatcher.ts` channelCreate/Delete | No comment explaining intentional asymmetry with channelUpdate |
| M2 | medium | `__tests__/permissions.test.ts` | No negative tests for GET/PATCH/DELETE `/channels/:id` (the regressed-twice routes) |
| S1 | low | `ws/index.ts`, `ws/session.ts` | `permissionsRepo` optional → silent regression vector |
| D1 | low | `ws/dispatcher.ts` filter | N synchronous DB queries per broadcast; consider memoizing per call |
| P1 | nit | `routes/permissions.ts` | No `>=0n` check on allow/deny |
| P2 | nit | `routes/permissions.ts` | No upper-bound on allow/deny |
| P3 | nit | `routes/permissions.ts` | targetId existence not verified |
| C2.1 | nit | shared/types.ts vs 3× redeclares | Export bigint constants from `@cove/shared` to dedup |

No high/critical findings.

---

## 6. Recommendation

**APPROVE.**

R3’s outstanding C2 (gating regression) is definitively fixed with a clean helper that prevents future copy-paste drift. C4’s remaining asymmetry is a defensible design choice with minor metadata leak that should be tracked as a follow-up, not a blocker.

**Before merge (cheap, ~10 min):**
1. Add the 2-line comment in `dispatcher.ts` explaining channelCreate/Delete intentional broadcast (M1).
2. Add 3–4 negative tests for `/channels/:id` REST gates (M2) — same pattern as existing `denied bot cannot read messages` test.

**Follow-up issue (next PR):**
- Make `permissionsRepo` required in gateway wiring (S1).
- File issue for CHANNEL_CREATE metadata leak to bots-without-VIEW_CHANNEL (low priority).
- Consider extracting `PermissionBits` bigint const from `@cove/shared` (C2.1).

Ship it. 🌠
