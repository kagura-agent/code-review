# PR #179 R3 Review — Nova 🌠

**Repo:** kagura-agent/cove
**PR:** #179 — refactor(ws): scope gateway events by guild membership
**Round:** 3 (re-review)
**Reviewer:** Nova
**Verdict:** ✅ Ready (with minor follow-ups)

---

## 1. Summary

Round 3 directly addresses both R2 critical issues and one of the two performance/UX concerns. The dispatcher now:

- Broadcasts presence-offline **before** removing the session from `this.sessions`, and **excludes the dying session** via `excludeSessionId` in `broadcastToGuildMembers`.
- Emits `GUILD_CREATE` / `GUILD_DELETE` to the affected user's sessions, wired from `routes/agents.ts` member add/remove and from `dispatcher.addGuildToUser` / `removeGuildFromUser`.
- Replaces the O(N²) identify-presence path with `getSharedGuildPresences(guildIds)`, a single-pass O(sessions) scan.
- Documents DM behaviour with a `TODO(#111)` and a regression test asserting silent-drop semantics.

Test coverage: a brand-new `gateway.test.ts` with 9 well-scoped specs, including the exact regression that was missed in R1 (dying-session self-broadcast). All 144 tests reported green.

This is a clean, focused R3. Ship-worthy.

---

## 2. Previous Issues Status

| # | R2 Issue | Severity | R3 Status |
|---|----------|----------|-----------|
| 1 | Self-broadcast on disconnect (PRESENCE_UPDATE offline sent to dying ws) | 🔴 | ✅ **Fixed** — `removeSession` now broadcasts first with `excludeSessionId = session.id`, then deletes from `this.sessions`. Direct regression test: `"does not send the offline event to the dying session itself"`. |
| 2 | No GUILD_CREATE/GUILD_DELETE to client (UI desync until reconnect) | 🔴 | ✅ **Fixed** — `addGuildToUser` emits `GUILD_CREATE` (looked up via `guildsRepo.getById`); `removeGuildFromUser` emits `GUILD_DELETE` **before** mutating `session.guildIds` (correct order — otherwise the event would be filtered). Both hooked into `POST/DELETE /guilds/:id/members/:userId`. Test coverage present. |
| 3 | DM channels silently dropped | 🟡 | ✅ **Acknowledged** — `TODO(#111)` comment in `resolveGuildForChannel` and a regression test pinning current behaviour. Acceptable as deferred work since DM implementation is its own design. |
| 4 | O(N²) IDENTIFY presence calculation | 🟡 | ⚠️ **Partially fixed** — `getSharedGuildPresences` is the right shape for identify (single pass over sessions). However `broadcastToGuildMembers` still calls `getSessionGuildIds(userId)` which iterates `this.sessions`, then iterates `this.sessions` again to filter — so live presence broadcasts are still O(sessions²) in the worst case. Lower frequency than identify, so not blocking. See suggestion (1). |

No previous issue regressed. No downgrades.

---

## 3. Critical Issues

None. Both R2 🔴 issues have direct fixes plus tests that would have caught the original bugs.

---

## 4. Product Impact

**Positive deltas vs R2:**
- A dying browser tab no longer attempts a `ws.send` on its own closing socket → no more spurious "WebSocket is not open" errors in server logs at disconnect.
- Joining/leaving a guild now updates the client UI in real time without a forced gateway reconnect. This is the intended Discord-parity behaviour.
- New users coming online get a presence list scoped to guilds they actually share → smaller IDENTIFY payload, no privacy leak across guilds.

**Remaining minor product issues:**
- When user X joins guild G via `addGuildToUser`, sessions of *other* users in G don't receive a `PRESENCE_UPDATE { user: X, status: online }` — so existing members won't see X appear in their member list until next reconnect. Symmetric gap on leave. Not blocking but worth a follow-up issue.
- `addGuildToUser` silently no-ops the `GUILD_CREATE` if `guildsRepo` was not passed (it's optional in the constructor). In production it's always wired, but easy footgun if a future caller forgets — see suggestion (2).

---

## 5. Suggestions (non-blocking)

1. **Cache user→guildIds for the live-broadcast path.** `getSessionGuildIds` is called on every presence-offline. Since `session.guildIds` for the same user across multiple sessions are populated from the same `guildsRepo.listForUser(user.id)` call, you can simplify: pick any one session of that user and read `session.guildIds` directly — it's identical across the user's sessions. That collapses `broadcastToGuildMembers` from O(sessions²) to O(sessions). Even simpler: maintain `userGuildIds: Map<string, Set<string>>` alongside `userSessions`.

2. **Make `guildsRepo` required** in `GatewayDispatcher`'s constructor, or fall back to `dispatch("GUILD_CREATE", { id: guildId })` when the lookup is missing. Silently skipping the event is the more dangerous default — it's the same class of UI-desync bug R2 flagged.

3. **Add a REQUEST_TYPING rejection test** (carried over from R2). The non-member rejection path in `ws/index.ts` (`if (!session.guildIds.has(channel.guild_id)) break;`) is currently untested. One-line spec to lock it in.

4. **`addGuildToUser` / `removeGuildFromUser` should also emit PRESENCE_UPDATE** for newly-(in)visible online users. Without this, member lists go stale on live joins/leaves until reconnect. Could be a separate issue tracked alongside #111.

5. **DRY**: `sendToUser` and the dispatcher-side `userSessions` map duplicate intent. `sendToUser` could iterate `this.userSessions.get(userId)` instead of scanning all sessions, which is O(user-sessions) instead of O(all-sessions). Tiny win, but the map already exists.

6. **TestDispatcher in `api.test.ts`** now passes `{ getById: () => null } as any` — works, but consider exporting a `createNoopDispatcher()` helper from the dispatcher module to centralize the test seam.

---

## 6. Positive Notes ✨

- **The fix ordering is correct and intentional**: `broadcast → delete session` on disconnect, and `GUILD_DELETE → mutate guildIds` on leave. Both orderings are commented explaining *why*, which prevents future "cleanup" PRs from breaking them.
- **The `excludeSessionId` parameter is the right abstraction**, not an ad-hoc filter inside `removeSession`. It composes if other callers ever need self-exclusion.
- **The new `gateway.test.ts` is a model regression suite**: each previously-broken behaviour has a named spec that would have failed pre-fix. The "live guild membership update" test covers the entire join→message→kick→message lifecycle.
- **DM behaviour is now a spec, not an accident.** Future DM implementation will have to *break* a test, which forces a design conversation.
- **`getSharedGuildPresences` is a clean primitive** — easy to reuse for future "online members of guild G" queries.

---

## Verdict: ✅ Ready

Both R2 🔴 issues are fixed with regression tests; 🟡 issues are addressed or properly deferred. Remaining suggestions are non-blocking polish and follow-up issues, not merge gates. Merge.

— Nova 🌠
