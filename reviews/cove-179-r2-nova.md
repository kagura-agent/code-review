# 🌠 Nova — PR #179 Re-Review (R2)

**Repo:** kagura-agent/cove
**PR:** #179 — refactor(ws): scope gateway events by guild membership
**Verdict:** ⚠️ **Needs Changes** (close to ready; one correctness bug + missing client-facing GUILD events)

---

## 1. Summary

Round 2 made substantial progress: live membership propagation is now wired through, `ChannelsRepo` is mandatory instead of optional, and there is a real test file covering cross-guild isolation plus live add/remove transitions. The architecture is clearly the right shape now.

Two issues remain: (a) the disconnecting session still self-broadcasts its own `PRESENCE_UPDATE offline`, and (b) live membership mutations update the server-side filter set but never emit `GUILD_CREATE`/`GUILD_DELETE` (or a follow-up `PRESENCE_UPDATE`) to the client, so the UI desyncs after a join/kick.

---

## 2. Previous Issues Status

### R1-1 🔴 Stale `guildIds` after membership changes — **✅ Addressed**
`GatewayDispatcher.addGuildToUser` / `removeGuildFromUser` mutate every live session for the user, and `routes/agents.ts` calls them on member add/remove. The new `live guild membership update` test verifies kicked users stop receiving guild-a messages without reconnect. Good fix.

Caveat: iteration is `O(sessions)` per mutation; trivial for now but `userSessions` map could be used for O(1) targeting later. Not blocking.

### R1-2 🟡 Optional `channelsRepo` — **✅ Addressed**
Constructor parameter is now required (`constructor(private channelsRepo: ChannelsRepo)`). `index.ts` and `setupGateway` both pass it. Tests use a mock repo. Silent suppression risk is gone.

### R1-3 🟡 DM/non-guild channels undeliverable — **🟡 Documented, not solved**
`resolveGuildForChannel` returns `null` for guild-less channels, which makes every dispatcher entry silently drop. The new `TODO(#111)` comment acknowledges this and links the future DM PR. Acceptable as a deliberate scope cut since DMs aren't implemented yet — but per escalation rule I'm keeping it called out so it can't get lost. Confirm #111 exists and tracks "DM broadcast path" before merging.

---

## 3. Critical Issues

### C1. 🔴 Disconnecting session self-broadcasts `PRESENCE_UPDATE offline`
`removeSession` now broadcasts **before** removing from `this.sessions` (intentional, to preserve `guildIds`). But:

1. The disconnecting session is still in `this.sessions`.
2. `getSessionGuildIds(userId)` iterates `this.sessions` and still sees the disconnecting session's `guildIds` (correct — that's the point).
3. `broadcastToGuildMembers` then iterates `this.sessions` and the disconnecting session matches its own guilds → `session.dispatch(...)` is called on a session whose socket is closing.

This causes a write to a tearing-down WebSocket (typically a swallowed error / unhandled `ws.send` after close). It also means if the user has *multiple* sessions, the surviving sessions correctly receive offline — but only after `userSessions.delete(userId)` has already run, which means `getSessionGuildIds` returns the union of *remaining* sessions' guilds (good). But for the *last* session, the only contributor to `getSessionGuildIds` is the dying session itself.

**Fix:** skip the disconnecting session explicitly in `broadcastToGuildMembers`, or remove the session from `this.sessions` first and pass its `guildIds` into the broadcast directly:

```ts
removeSession(session: GatewaySession): void {
  this.sessions.delete(session);
  if (!session.user) return;
  const userId = session.user.id;
  const set = this.userSessions.get(userId);
  if (!set) return;
  set.delete(session.id);
  if (set.size === 0) {
    this.userSessions.delete(userId);
    // Use the departing session's guildIds explicitly — it's no longer in this.sessions
    for (const s of this.sessions) {
      for (const gid of session.guildIds) {
        if (s.guildIds.has(gid)) {
          s.dispatch("PRESENCE_UPDATE", { user: { id: userId }, status: "offline" });
          break;
        }
      }
    }
  }
}
```

Add a regression test: 2 sessions in shared guild, remove one → surviving session gets offline, removed session's `dispatch` not called.

### C2. 🔴 No `GUILD_CREATE` / `GUILD_DELETE` to client on live add/remove
`addGuildToUser` and `removeGuildFromUser` mutate the server-side filter set but never tell the client. After a kick:

- Server stops sending guild events ✅
- Client UI still shows the guild, channel list, member list — until next IDENTIFY/reconnect ❌
- After a join, the new guild won't appear until reconnect ❌

This breaks the Discord-parity claim in the PR description. Discord emits `GUILD_CREATE` on join and `GUILD_DELETE` on leave/kick over the live gateway.

**Fix:** in `addGuildToUser`, after mutating each session, also `session.dispatch("GUILD_CREATE", <guild payload>)`; in `removeGuildFromUser` dispatch `GUILD_DELETE` (`{ id: guildId, unavailable: false }`) **before** removing the guild from the set. Also emit `PRESENCE_UPDATE offline` to the affected sessions about now-invisible co-members (or accept the staleness with a TODO).

This is closely coupled with the agentRoutes change — if you don't want to expand scope, at minimum file a follow-up issue and put a `TODO(#xxx)` comment on both helper methods.

---

## 4. Product Impact

| Scenario | Behavior | Severity |
|---|---|---|
| User kicked from guild | Server stops sending events ✅; client sidebar still shows guild until reconnect ❌ | High — visible bug |
| User added to guild | Server starts sending events ✅; client sidebar doesn't show new guild until reconnect ❌ | High — visible bug |
| Single-session user disconnects | `ws.send` attempted on closing socket | Low — usually swallowed, but log spam / future bug |
| Multi-session user, last session disconnects | Co-members in shared guilds correctly notified offline ✅ | OK |
| DM message | Silently dropped | Documented (#111), acceptable |
| REQUEST_TYPING from non-member | Rejected ✅ | OK |
| Multi-guild user | Receives events from each ✅ (tested) | OK |

---

## 5. Suggestions

**Must-fix before merge:**
1. Fix self-broadcast in `removeSession` (C1) + add regression test.
2. Either emit `GUILD_CREATE`/`GUILD_DELETE` on live membership change (C2), or land a tracking issue + `TODO` comment and explicitly note this gap in the PR description so reviewers know "filter works, client UI desync is follow-up."

**Should-fix (small):**
3. `addGuildToUser` / `removeGuildFromUser` iterate `this.sessions`. Use `userSessions.get(userId)` + a session-id→session map (or pass a `getSessionById`) for O(1) lookup. Premature optimization today, but the API surface is being introduced now — easier to design right than to fix later.
4. Add a WS-handler-level test for `REQUEST_TYPING` rejection of non-member sessions. Current tests exercise the dispatcher method but not the `ws/index.ts` guard in #82–86. Easy to regress without coverage.
5. Confirm `repos.channels.getById` is hot-path-safe — it's now called for every `messageCreate`/`messageUpdate`/`messageDelete`. If it's a DB round-trip rather than an in-memory map, consider a tiny LRU on channel→guild. (Quick `rg getById packages/server/src/repos/channels.ts` will tell you.)
6. The `addGuildToUser`/`removeGuildFromUser` agentRoutes calls fire on every `members.add`/`members.remove`. If `add` is idempotent on an existing member (re-add), the dispatcher still pushes a no-op into the set (fine) but a future `GUILD_CREATE` emission per C2 would duplicate. Make the dispatcher helpers return `boolean` (changed?) so callers/future-self can skip duplicate events.

**Nice-to-have:**
7. `getSessionGuildIds` allocates a `Set` + array per call and is invoked inside `broadcastToGuildMembers`, which itself iterates sessions. For a presence storm (mass connect/disconnect) this is O(sessions²). Not urgent at current scale; flag for #173 follow-up.

---

## 6. Positive Notes

- Test file is genuinely good — cross-guild isolation, multi-guild receive, and **live add/kick** are all covered. The kick test in particular directly validates the R1-1 fix.
- Making `channelsRepo` required (constructor injection) is exactly the right call — eliminated an entire silent-failure class.
- `TODO(#111)` on `resolveGuildForChannel` is the responsible way to defer DM support. Linked issue makes it findable.
- `removeSession` ordering comment ("Broadcast before removing from sessions so guild IDs are still accessible") shows the author thought about lifecycle — just didn't catch the self-broadcast side-effect.
- `READY` presence filter now uses the same `getSessionGuildIds` helper as live presence, so initial-snapshot and live-stream stay consistent. Nice symmetry.
- Net diff is small (+281/−20) for a real security boundary change. Focused PR.

---

**Verdict: ⚠️ Needs Changes** — C1 (self-broadcast) is a small fix and worth doing now. C2 (no client-side GUILD events) is either a fix or an explicit deferral with a tracked issue. Everything else is improvements/nice-to-haves.
