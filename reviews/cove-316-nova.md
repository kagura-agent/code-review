# PR #316 Round 3 Re-review — 🌠 Nova

**PR:** feat: channel permission overwrites — bot visibility control (closes #315)
**Round:** 3 (re-review after author claimed all R2 findings fixed)

## Summary

R3 closes most of R2's gaps — the permissions repo is wired into the dispatcher, READY payload filters channels for bots, and the negative-test matrix is now genuinely broad (8 new 403 tests covering messages, reactions, typing, permission management). However, the author's claim that **"ALL channel-scoped REST routes check VIEW_CHANNEL for bots"** is still not true: three routes in `channels.ts` remain ungated, and the channel-delete dispatch path has a CASCADE ordering bug that means bots never receive `CHANNEL_DELETE`. Per the escalation rule, the second time the same gating gap recurs raises severity.

**Verdict:** ⚠️ Needs Changes

---

## Critical Issues

### C1 (re-escalated). REST gating still incomplete — `GET/PATCH/DELETE /channels/:id`
**File:** `packages/server/src/routes/channels.ts:29–37, 74–119, 121–134`

These three routes were not touched by R3. A bot member of the guild can:
- `GET /channels/:id` — read channel metadata for channels it has no VIEW_CHANNEL on. The response is also enriched with `permission_overwrites` (`channels.ts` `enrichOverwrites`), so a denied bot learns the full list of which other users/bots have access. Information disclosure.
- `PATCH /channels/:id` — rename/retopic any channel in the guild.
- `DELETE /channels/:id` — delete any channel in the guild.

This is the *same* class of issue as R2 (only 2/10 routes gated). Author claim "ALL channel-scoped REST routes" is materially wrong. Per the re-review escalation rule, this is escalated severity, not a "missed minor route."

Fix: gate all three with `requireBotChannelPermission(repos, id, user.id, user.bot)` exactly like `messages.ts`/`reactions.ts`/`webhooks.ts` do. Mutating routes (PATCH/DELETE channel) should also long-term be MANAGE_CHANNELS, but at minimum VIEW_CHANNEL must be enforced now.

### C2 (new). `CHANNEL_DELETE` event never delivered to bots
**Files:** `packages/server/src/routes/channels.ts:127–131`, `packages/server/src/ws/dispatcher.ts:106–108, 180–190`

`routes/channels.ts` DELETE handler:
```
repos.channels.delete(id);         // CASCADE → overwrites row removed
dispatcher?.channelDelete(...);    // now broadcastToGuildWithChannelFilter
```
`broadcastToGuildWithChannelFilter` then calls `permissionsRepo.hasPermission(channelId, ...)`. Because the cascade already removed every overwrite for that channel, `hasPermission` returns `false` for every bot session → **no bot ever receives `CHANNEL_DELETE`**. Bots that had VIEW_CHANNEL keep the deleted channel in their in-memory state until they reconnect, and any subsequent `MESSAGE_CREATE`/`channels.list` will silently 404 in their UI.

Fixes (pick one):
- Dispatch `CHANNEL_DELETE` *before* deleting the row, or snapshot the eligible session set first.
- Special-case `channelDelete` to use unfiltered `broadcastToGuild` (since being told a channel disappeared is not a confidentiality leak; the channel id was already public to those who could see it).
- Capture the recipient list pre-delete and pass it explicitly.

Add a regression test: bot with VIEW_CHANNEL, delete channel, assert `CHANNEL_DELETE` is received.

### C3 (new). `CHANNEL_CREATE` is unreachable for bots
**File:** `packages/server/src/ws/dispatcher.ts:97–100`

`channelCreate(channel)` runs `broadcastToGuildWithChannelFilter(channel.guild_id, channel.id, "CHANNEL_CREATE", channel)`. A brand-new channel has *no* overwrites by construction (default-deny), so the filter excludes every bot session. There is also no event emitted by `PUT /channels/:channelId/permissions/:targetId`, so a bot is effectively **blind to every new channel until it reconnects**, even after an admin explicitly grants it VIEW_CHANNEL.

This is a product-correctness break of the stated MVP behavior ("explicit opt-in required"). Suggested resolution: either
1. Emit `CHANNEL_CREATE` (and `CHANNEL_UPDATE`) to bots once a permission is granted (via permission-grant → emit `CHANNEL_CREATE`/`CHANNEL_UPDATE` to that bot session), and don't filter `CHANNEL_CREATE` itself (admin-side admins still see the create), **or**
2. After `permissions.upsert` toggles VIEW_CHANNEL from absent/denied → allowed for a target, push a synthetic `CHANNEL_CREATE` to that target's sessions; on the reverse transition push `CHANNEL_DELETE`.

Pair the fix with tests; today this gap is invisible because no test exercises "grant permission after channel exists, expect bot to learn about the channel live."

---

## Product Impact

- Combined with C2/C3, a bot installed today only ever sees the channel set it was granted access to **at the moment of IDENTIFY**. New channels post-IDENTIFY → invisible. Deleted channels post-IDENTIFY → stale. This breaks the natural workflow ("install bot, then go add it to channel X") and will look like "the agent isn't responding."
- Information disclosure via `GET /channels/:id` returning `permission_overwrites` to denied bots reveals the entire bot-access matrix to any bot in the guild. Low blast-radius in single-tenant deployments, but it's a real leak.

---

## Suggestions

1. **Webhook routes don't enforce VIEW_CHANNEL on the parent channel.** `GET /webhooks/:webhookId`, `PATCH /webhooks/:webhookId`, `DELETE /webhooks/:webhookId`, and `GET /guilds/:guildId/webhooks` allow a bot to enumerate / mutate webhooks attached to channels it can't see. `listByGuild` also returns `channel_id` for hidden channels — channel-id enumeration. Recommend filtering by VIEW_CHANNEL on the webhook's parent channel. (Out of strict scope, but the PR moved adjacent webhook routes; the asymmetry is glaring.)
2. **`PUT /channels/:channelId/permissions/:targetId` does not validate that `targetId` corresponds to a real user/role.** You can write overwrites for arbitrary ids. Minor data hygiene (admin-only path).
3. **`BigInt` validation accepts negative values** (`BigInt("-1")` succeeds). Add a `>= 0n` check or use unsigned mask validation, otherwise `allow = "-1"` would behave as "all permissions on" depending on consumer.
4. **`requireBotChannelPermission`** redefines `VIEW_CHANNEL = 1n << 10n` locally; `session.ts` also has its own `VIEW_CHANNEL_BIT`; `dispatcher.ts` has another. Three copies of the same magic. Move to one constant (e.g. `PermissionFlags.VIEW_CHANNEL_BIT` in shared) and reuse.
5. **`api.test.ts` change `bot: 1 → 0` for admin** combined with `Bot → Bearer` swap is correct and consistent with the new rule "only humans manage permissions," but please add an inline comment so future readers don't think it's accidental.
6. **`reactions.test.ts` directly inserts into `channel_permission_overwrites`** to bypass the new auth. Acceptable as a test hack, but prefer reusing `grantViewChannel`-style helpers or marking admin as human (`bot=0`) like the other suites — keeps test setup uniform.
7. **READY filtering uses `channelsRepo.list(g.id).filter(hasPermission)`** — two round trips per channel for bots in large guilds. Consider a single `listByGuildForBot(guildId, userId)` query joining the overwrites table. Not a blocker at current scale.
8. **`enrichOverwrites` is invoked on `list`/`getById` unconditionally** — humans get the full overwrite list, which is fine, but you may want to consider whether bots that *do* have VIEW should also see other bots' overwrites. Currently they do.
9. **`PermissionsRepo.hasPermission`** lacks an index on `(channel_id, target_id)`; the PRIMARY KEY covers it, so fine — just confirming.

---

## Positive Notes

- **Negative-test coverage is now genuinely strong.** Eight `code === 50013` tests covering GET/POST messages, PATCH/DELETE messages, reactions add/remove, typing, plus the dispatcher-filter pair (with vs without VIEW_CHANNEL) and a human-bypass test. This is exactly what R2 was missing.
- **READY payload filtering** (`session.ts:48–54`) is implemented correctly: humans get all channels, bots get only the ones they have VIEW_CHANNEL on. Good factoring with `permissionsRepo?` optional to keep the test setup ergonomic.
- **Dispatcher channel-scoped filter** (`broadcastToGuildWithChannelFilter`) is a clean refactor — message, reaction, typing, and channel-lifecycle paths all funnel through one filter helper. Easy to audit. (The bug is upstream ordering, not the filter itself.)
- **READY/dispatcher filtering for humans** correctly bypassed; admins always see everything.
- **Admin-only PUT/DELETE permissions** (`permissions.ts:11–14, 43–46`) cleanly reject `user.bot` with the right Discord error code.
- **CASCADE delete** on `channel_permission_overwrites` is correct DB hygiene.
- **BigInt validation** (`permissions.ts:32–36`) catches malformed strings — fixes R2 C5.

---

## R2 Status Recheck

| R2 finding | R3 status |
|---|---|
| C1 admin auth | ✅ Fixed |
| C2 REST gating (2/10) | ⚠️ **Still incomplete (escalated)** — GET/PATCH/DELETE `/channels/:id` ungated |
| C3 negative tests | ✅ Now solid |
| C4 dispatcher channel lifecycle | ⚠️ Filter is in place, but `CHANNEL_DELETE`/`CHANNEL_CREATE` are unreachable for bots (new C2/C3 above) |
| C5 BigInt validation | ✅ Fixed |
| NEW: READY leak | ✅ Fixed |

**Verdict:** ⚠️ Needs Changes — fix `GET/PATCH/DELETE /channels/:id` gating, fix the `CHANNEL_DELETE` cascade-vs-broadcast ordering, and decide on a story for `CHANNEL_CREATE`/permission-grant notifications so bots aren't blind until reconnect.

`/home/kagura/.openclaw/workspace/code-review/reviews/cove-316-nova.md`
