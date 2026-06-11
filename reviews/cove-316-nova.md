# 🌠 Nova — Round 2 Review: cove#316

**PR:** feat: channel permission overwrites — bot visibility control (closes #315)
**Round:** 2 (re-review after author claimed fixes for C1–C5)
**Verdict:** ⚠️ **Needs Changes** — three of five R1 findings are fully fixed, C2 is only **partially** fixed (escalates), and a previously-missed gap in `READY`/identify weakens the feature end-to-end.

---

## 1. Summary

Author addressed the obvious R1 items: permission management is humans-only (C1), dispatcher filtering covers messages/typing/reactions (C4), BigInt parsing is wrapped in try/catch (C5), and a real negative-test suite landed (C3). The new `permissions.test.ts` is the most valuable addition — clear positive/negative coverage for the routes themselves and for the message read/send gate.

However, the REST gate (C2) is only applied to **2 of ~10** routes that a bot can hit with a channel id. A denied bot can still fetch single messages, edit/delete its own messages, ack, type, add reactions, and read channel metadata. The READY payload also still ships the full channel list (with permission overwrites) to every bot at identify time, so the "default deny" promise in the PR description is leaky regardless of dispatcher-side filtering.

Per the re-review protocol's escalation rule, C2's partial fix stays Critical.

---

## 2. Status of R1 findings

| ID | Finding | R2 status | Notes |
|----|---------|-----------|-------|
| C1 | Permission routes lack admin auth | ✅ Fixed | `permissions.ts` rejects `user.bot` with 403/50013; covered by two negative tests. See §4 nit about naming (it's "humans-only", not "admin"). |
| C2 | REST not gated by VIEW_CHANNEL | ⚠️ **Partially fixed — escalates** | Only `GET/POST /channels/:id/messages` + `GET/POST /channels/:channelId/webhooks` were gated. See §3.1. |
| C3 | Missing negative auth tests | ✅ Fixed | Four solid negative tests in `permissions.test.ts`. Could add more (see §3.1) but the gap is addressed. |
| C4 | Dispatcher only filters 3 event types | 🟡 Mostly fixed | Messages, typing, reactions are now channel-filtered. `CHANNEL_CREATE/UPDATE/DELETE` and `GUILD_MEMBER_ADD/REMOVE` still use the unfiltered `broadcastToGuild`. See §3.3. |
| C5 | BigInt validation missing | ✅ Fixed | `routes/permissions.ts:32–36` wraps `BigInt(allow)`/`BigInt(deny)` in try/catch and returns 400. Acceptable as written; see §4 for hardening. |

---

## 3. Critical Issues

### 3.1 [C2 — escalated] REST gating is incomplete; bots without VIEW_CHANNEL still leak data

The fix touched `messages.ts:11/48` and `webhooks.ts:21/46` but the following routes still call only `requireGuildMember` and skip `requireBotChannelPermission`:

- `GET /channels/:id` (`channels.ts:29`) — returns channel object **including `permission_overwrites`**. A denied bot can enumerate which users have access.
- `GET /channels/:id/messages/:msgId` (`messages.ts:32`) — single-message read; leaks the same content `GET …/messages` was patched to block.
- `PATCH /channels/:id/messages/:msgId` (`messages.ts:97`) — a bot whose VIEW_CHANNEL was revoked can still edit its old messages.
- `DELETE /channels/:id/messages/:msgId` (`messages.ts:132`) — same.
- `POST /channels/:id/messages/bulk-delete` (`messages.ts:164`)
- `DELETE /channels/:id/messages` (`messages.ts:198`)
- `PUT /channels/:id/messages/:msgId/ack` (`messages.ts:214`)
- `POST /channels/:id/typing` (`messages.ts:233`) — denied bot can still broadcast typing to humans (dispatcher filtering protects other bots, but humans still see it).
- `PUT/DELETE /channels/:channelId/messages/:messageId/reactions/:emoji/@me` (`reactions.ts:11/37`)
- `GET /channels/:channelId/messages/:messageId/reactions/:emoji` (`reactions.ts:63`)

Because the dispatcher does filter MESSAGE_CREATE etc., a revoked bot can't *receive* new messages — but it can still actively *poll* (`GET single message`), *post reactions*, and *delete its own backlog*. That's exactly the scenario VIEW_CHANNEL is supposed to prevent.

**Fix:** add one `requireBotChannelPermission(repos, channelId, user.id, user.bot)` guard to each of the above. The helper already exists; this is one line per route plus tests. Recommend extracting a small middleware to apply to all `/channels/:id/...` routes mounted under the same router rather than copy-pasting.

Also missing negative tests for these — at minimum add one for `GET single message` and one for reactions so the gap doesn't re-open silently.

### 3.2 [NEW] READY/identify ships the full channel list (with overwrites) to every bot

`ws/session.ts:48–50` builds `guildsWithChannels` via `channelsRepo.list(g.id)` with no per-bot filtering. The list now includes `permission_overwrites` (via the enrichment in `channels.ts:enrichOverwrites`). So a bot that has zero VIEW_CHANNEL on every channel still:

1. Learns the channel ids, names, topics, and types of every channel in every guild it's a member of at connect time.
2. Sees the full overwrite table for every channel, including which other bots are allowed.

This directly contradicts the PR description's "default: no overwrites = bot cannot see the channel" promise and undoes most of the dispatcher-side filtering work for the connect/reconnect window.

**Fix:** mirror the filter that was just added to `GET /guilds/:guildId/channels` (`channels.ts:20–25`) inside `identify()` for `user.bot === true`. Either filter `channels` in the READY payload, or skip channels in `g.channels` that the bot lacks VIEW_CHANNEL for. Strip `permission_overwrites` from the response for bots too — leaking the overwrite table is itself a (minor) info disclosure.

This should also have a test in `permissions.test.ts` that calls `session.identify(...)` for a bot with no overwrites and asserts `READY.d.guilds[*].channels` is empty / filtered.

### 3.3 [C4 follow-up] CHANNEL_CREATE / CHANNEL_UPDATE / CHANNEL_DELETE still unfiltered

`dispatcher.ts:99–107` still uses `broadcastToGuild` for channel lifecycle events. Combined with §3.2, a bot without any overwrites still gets pushed every new/updated channel object (with overwrites) live. Not as severe as §3.2 because it only affects post-connect lifecycle, but it's the same class of bug.

Acceptable workaround: gate `CHANNEL_CREATE/UPDATE/DELETE` to bots only when they have VIEW_CHANNEL on that specific channel. (For DELETE you'll need to read perms before the cascade fires, or short-circuit with "if bot had perm" via a snapshot.)

---

## 4. Suggestions (non-blocking)

- **Naming / future-proofing of the auth gate in `routes/permissions.ts`:** the check is `if (user.bot) return 403`, but the PR talks about "admin" auth. In a multi-tenant Cove this should become a real `MANAGE_CHANNELS` check on the user. Today no human user has any meaningful elevated state, so "any human guild member can rewrite overwrites" is the de-facto behaviour. Leave a `TODO` referencing #113 (consistent with the existing TODOs in `messages.ts:148/162`) so this isn't forgotten.
- **Duplicate VIEW_CHANNEL constant:** `1n << 10n` is defined inline in three places (`helpers.ts:38`, `dispatcher.ts:5`, plus the shared `PermissionFlags`). Import from `@cove/shared` instead so the bit can't drift.
- **`PermissionsRepo.hasPermission` semantics:** currently `(allow & bit) !== 0n && (deny & bit) === 0n`. Discord semantics layer multiple overwrites with role+everyone+member precedence; here there's no @everyone overwrite, so "no row = denied" is fine for the MVP, but document it on the method — otherwise a future contributor will assume Discord-style layering.
- **BigInt hardening:** `BigInt("-1")` and `BigInt("99999999999999999999999")` both succeed. Add a `>= 0n` and `< (1n << 64n)` check after parsing in `routes/permissions.ts:32–36`. Cheap, prevents weird overwrite rows.
- **N+1 in channel enrichment:** `ChannelsRepo.list` now calls `permissionsRepo.listByChannel` once per channel. For guilds with many channels that's 1 + N queries. A single `WHERE channel_id IN (...)` would fix it. Not urgent at current scale.
- **`channels.ts:20–25` `requireBotChannelPermission(... true)`:** the `true` is redundant because the caller is already inside `if (user.bot)`. Either drop the param or pass `user.bot` for consistency with how `messages.ts` uses the helper.
- **Test cleanup:** the existing `api.test.ts` had to sprinkle ~10 `grantViewChannel(generalId, "kagura")` calls. Consider moving "general grants VIEW_CHANNEL to all bots in the test guild" into the `beforeEach` so the diff is smaller and unrelated route tests aren't coupled to the permission system.
- **Client `handleToggleBotPermission`:** on error the optimistic state isn't reverted — `setOverwrites` is only called inside the `try` block, but the loading state ends in `finally`. If the PUT throws (e.g. 403, network), the UI Switch flips back via `hasAccess` recomputation only because state wasn't mutated… actually that's fine. But the user gets no error feedback (only `console.error`). Add an `antd` `message.error()` toast for parity with the rest of ChannelSettings.

---

## 5. Positive Notes

- `permissions.test.ts` is genuinely good: it covers CRUD, negative auth on both routes, denied-read and denied-send, dispatcher-included and dispatcher-excluded bots, **and** the "humans always pass" invariant. Three of four negative cases assert the Discord-style error code `50013`, not just the status — nice.
- CASCADE on `channel_permission_overwrites.channel_id` with a real test (`permissions.test.ts:121–136`) is the kind of migration that usually ships untested. Good.
- Repo wiring (`createRepos`) deferring `setPermissionsRepo` keeps `ChannelsRepo` from a circular import — clean.
- The shared `PermissionOverwrite` interface + typed `permission_overwrites: PermissionOverwrite[]` in `Channel` makes the client code typesafe; the bigint-as-string convention is the right Discord-compatible choice.
- All test admin users were correctly downgraded from `bot=1` to `bot=0`; the `Bot` → `Bearer` header switch in existing tests was done consistently. That's tedious work the author actually finished.

---

## Verdict

⚠️ **Needs Changes** — block on §3.1 (complete the REST gate, with negative tests) and §3.2 (filter the READY channel list for bots). §3.3 and the suggestions in §4 are follow-ups but should be at least filed.

The core design is sound and the test scaffolding is in place; this is finish-the-job work, not a redesign.

`/home/kagura/.openclaw/workspace/code-review/reviews/cove-316-nova.md`
