# Consolidated Review — cove#252: emit missing Gateway events + client cascade cleanup

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

## Summary

Small, surgical PR (57+/3-, 9 files) filling Gateway event gaps. Server adds `guildMemberAdd`/`guildMemberRemove` + `guild_id` on `MESSAGE_DELETE`. Client cascades cleanup on `CHANNEL_DELETE` and handles the new member events. Build + 152 tests pass.

## Critical / Blocking

### 🟡 `GUILD_MEMBER_ADD/REMOVE` incorrectly mutates global presence (Stella, Nova)

Current code:
```ts
subscribe("GUILD_MEMBER_ADD", (data) => {
  usePresenceStore.getState().setOnline(data.user.id);  // ← wrong
});
subscribe("GUILD_MEMBER_REMOVE", (data) => {
  usePresenceStore.getState().setOffline(data.user.id); // ← wrong
});
```

**Problem:** Guild membership ≠ online status.
- **ADD**: A newly added member may be offline (e.g., bot added via API). Every client shows them as Online until a real `PRESENCE_UPDATE` corrects it.
- **REMOVE**: Removing from one guild doesn't mean offline globally — user may still be in other shared guilds.

The presence store is keyed by `userId`, not `(guildId, userId)`, so these mutations affect the user across the entire UI.

**Fix options:**
1. Don't update presence from member events at all (let `PRESENCE_UPDATE` be the sole source of truth) — safest
2. Add a TODO comment + file follow-up issue — acceptable for merge

### 🟡 `GUILD_CREATE`/`GUILD_DELETE` still silently dropped (Stella)

Server already emits these when users are added/removed from guilds, but client doesn't handle them. The affected user's connected client keeps stale guild state. Directly in the lifecycle surface this PR addresses.

**Recommendation:** At minimum, add to `gatewayEvents` set so the dev warning fires in development. Full handling can be a follow-up.

## Suggestions (non-blocking)

1. **No tests for new event paths** (Stella, Nova) — `guildMemberAdd`/`guildMemberRemove` dispatch payloads untested. Client cascade cleanup untested. Add at least dispatcher-level assertions.

2. **`MESSAGE_DELETE_BULK` client type drift** (Stella) — Server sends `guild_id` but client type is `{ ids; channel_id }` without it. Same category of fix as this PR.

3. **Dev warning consistency** (Nova) — The `gatewayEvents.has()` branch doesn't check `op === DISPATCH`, but the else branch does. Minor consistency nit.

4. **Typing-aware derived allowlist** (Stella) — `const gatewayEvents = [...] as const satisfies Array<keyof GatewayEventMap>` would prevent future type/runtime drift.

## Positive Notes

- `CHANNEL_DELETE` cascade cleans up messages, read states, AND typing timeouts — prevents memory leaks ✅
- `useTypingStore.removeChannel()` clears timeouts AND removes from `typingTimeoutIds` — detail-oriented ✅
- Subscribe-before-broadcast on add / broadcast-before-unsubscribe on remove — correct sequencing ✅
- Dev-mode unknown event warning — great observability win ✅
- `MESSAGE_DELETE.guild_id` addition uses existing `resolveGuildForChannel()` — guild isolation preserved ✅
- Test updated alongside payload change ✅

## Verdict

**⚠️ Needs Minor Changes**

The cascade cleanup and server-side events are solid. The one real issue: **don't conflate guild membership with presence**. Either remove the `setOnline`/`setOffline` calls (safest) or file a follow-up issue with a TODO. After that → ✅ Ready.
