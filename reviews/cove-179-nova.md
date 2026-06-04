# PR #179 Review — scope gateway events by guild membership

**Reviewer:** 🌠 Nova
**Repo:** kagura-agent/cove
**Rating:** ⚠️ Needs Changes

## 1. Summary
Closes a real security gap: WebSocket gateway previously fanned every event to every authed session. PR introduces guild-scoped broadcast via `session.guildIds` (snapshotted at IDENTIFY) and channel→guild resolution in the dispatcher. Coverage matches REST isolation from #168, and 8 new tests cover the happy paths. The model is correct, but membership is captured once-per-connect and never refreshed, which leaves a kick-then-still-receiving window. Plus a few smaller correctness/robustness issues.

## 2. Critical Issues

### C1. Stale `guildIds` after membership changes — security regression on kicks/bans
`session.ts:42-44` populates `guildIds` only inside `identify()`. There is no observer for guild join/leave/kick/ban. Consequences:
- **Kicked/banned user keeps receiving MESSAGE_CREATE / TYPING_START / PRESENCE_UPDATE for the guild** until they reconnect. This is exactly the leak the PR is trying to fix, just narrowed to a smaller window.
- New guild joins don't deliver events until reconnect (functional bug, less severe).

REST side (#168) presumably re-checks membership per request; the gateway needs an equivalent. Options:
- Have `guilds.addMember` / `removeMember` notify the dispatcher to mutate live `session.guildIds` sets for matching userId.
- Or look up membership lazily per broadcast (slower but stateless).

At minimum, document this as a known gap and file a follow-up issue; ideally fix before merge since it's the same threat model as the closing issue.

### C2. `channelsRepo` constructor param is optional → silent broadcast suppression
`dispatcher.ts:9` makes `channelsRepo` optional. If a future caller forgets it, `resolveGuildForChannel` returns `null` for every channel and `messageCreate / messageUpdate / messageDelete` silently drop all events with no log. This is a debugging trap.

Make it required (`constructor(private channelsRepo: ChannelsRepo)`), or throw/log when it's missing and a broadcast is attempted. `index.ts:21` already passes it, so just require it.

### C3. DM / non-guild channels are now undeliverable
Every message broadcast goes through `resolveGuildForChannel`. If/when DM channels (`guild_id` null) are added — or already exist in any code path — `messageCreate` returns early and the message is never dispatched. There's no test for `guild_id == null`. Confirm Cove has no DM-style channels today and add a TODO, or add a `broadcastToRecipients` path for DMs.

## 3. Product Impact
- Closes a real privacy bug: cross-guild event leakage. ✅
- Behaviour now matches Discord — users only see typing/presence/messages in guilds they're in.
- Presence list at READY is now smaller and more relevant (only co-guild members), which is a noticeable UX/perf win for users in few guilds.
- Risk: if C1 isn't fixed, removed members continue to see live activity until they disconnect. For trust/safety contexts (kicks, bans) this matters.

## 4. Suggestions

### S1. `removeSession` still iterates the leaving session
`dispatcher.ts:33-44`: order was flipped so `broadcastToGuildMembers` runs before `this.sessions.delete(session)`. The leaving session is therefore included in the iteration and gets dispatched its own `PRESENCE_UPDATE offline`. Harmless (socket is closing) but wasteful and confusing. Either delete first and pass a snapshot of guildIds, or explicitly skip `session` in the loop.

### S2. `getSessionGuildIds` is O(N sessions) per call, called per presence event
`dispatcher.ts:48-57` scans **all** sessions to build a userId→guildIds set. Then `broadcastToGuildMembers` (`dispatcher.ts:111-118`) does another `O(sessions × userGuildIds)` filter. For each PRESENCE_UPDATE that's effectively `O(sessions²)` worst case. Cheap today; will bite at a few thousand sockets.

Maintain `userGuildIds: Map<string, Set<string>>` incrementally in `addSession` / `removeSession` and use `Set.intersection`-style check. The data is already de-facto cached on each session — just hoist it.

### S3. `READY` presence filter calls `getSessionGuildIds` per online user
`session.ts:47-50`: `onlineUserIds.filter(... dispatcher.getSessionGuildIds(id) ...)` is O(online × sessions). Fix together with S2.

### S4. Test mocks duplicate types via `as any`
`gateway.test.ts` casts `{...} as any` for messages and `as unknown as GatewaySession` for sessions. Works, but a small `makeMessage` helper returning a typed partial would catch shape drift. Optional.

### S5. Missing test cases
- Channel with falsy/missing `guild_id` (DM-like) — confirms intended drop behavior (C3).
- Multi-guild user receives events from **both** guilds (PR description claims this is tested; the test file only covers cross-guild isolation between two single-guild users, not the multi-guild case).
- `REQUEST_TYPING` from a non-member is rejected — `ws/index.ts:82-90` has new guard logic but no test in `gateway.test.ts` exercises the WS handler.
- `removeSession` for a user with multiple connections only emits offline when the last one closes — existing behaviour preserved, but worth a regression test now that ordering changed.

### S6. `typingStart` signature change is a soft API break
`dispatcher.ts:81` now requires `guildId`. Other call sites or downstream consumers (plugins) would silently miscompile if they typed it loosely. The test in `api.test.ts:30` shows you already had to update an override — good. Worth a one-line comment on the method documenting that `guildId` is mandatory.

### S7. `broadcastToGuild` doesn't gate by `isIdentified`
`dispatcher.ts:104-108`: pre-identify sessions have `guildIds` empty, so they naturally won't receive anything. But the original `broadcast` also fired before identify (per the test setup that clears mocks after `addSession`). Confirm no event types must reach pre-identify sessions; if so, fine — otherwise add an explicit `if (!session.isIdentified) continue`.

## 5. Positive Notes
- Clean, contained refactor — the dispatcher's surface stays small.
- `broadcastToGuildMembers` is a nice abstraction for presence and reads naturally.
- The reorder in `removeSession` to broadcast before deleting (so guildIds are still queryable) is exactly the right instinct, even if S1 polishes it further.
- Good test coverage for the new positive and negative paths; cross-guild isolation test is the right shape.
- Discord-parity framing in the PR description is helpful — gives reviewers an external spec to check against.
- Typing now requires explicit `guild_id` at the call site (`messages.ts:130`, `ws/index.ts:85-87`) — makes accidental cross-guild typing structurally hard.

---

**Recommendation:** Address **C1** (membership freshness on kick/ban — security-critical), tighten **C2** (drop the optional `?`), and confirm/handle **C3** (DM channels) before merge. S1–S7 are polish and can land in a follow-up.
