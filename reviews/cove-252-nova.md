# 🌠 Nova — Review of cove#252

**PR**: feat: emit missing Gateway events and add client cascade cleanup
**Size**: 57+/3- across 9 files · Closes #225, #234

## 1. Summary

Fills two gaps in the Gateway event surface:
- **Server**: dispatcher gains `guildMemberAdd`/`guildMemberRemove`, called from `POST/DELETE /guilds/:id/members/:userId`; `MESSAGE_DELETE` payload now carries `guild_id`.
- **Client**: `CHANNEL_DELETE` cascades to message/read-state/typing stores; new `GUILD_MEMBER_ADD/REMOVE` handlers update presence; unknown DISPATCH events warn in dev.

Mechanically small, surgical, and well-scoped. Tests adjusted for the new `guild_id` field.

## 2. Critical Issues

None blocking. Subscription/broadcast ordering in `agents.ts` is correct (subscribe-then-broadcast on add; broadcast-then-unsubscribe on remove), so the affected user does receive their own event.

## 3. Suggestions

### S1 — `GUILD_MEMBER_REMOVE` ⇒ `setOffline` is incorrect semantically *(medium)*
`gateway-subscriptions.ts`:
```ts
subscribe("GUILD_MEMBER_REMOVE", (data) => {
  usePresenceStore.getState().setOffline(data.user.id);
});
```
A user being removed from **one** guild does not mean they are offline globally. If the same user is still a member of another guild that the current client also belongs to, this flips their indicator to offline incorrectly across the whole UI (presence store is keyed by `userId`, not `(guildId, userId)`).

Mirror symptom on `GUILD_MEMBER_ADD` → `setOnline`: a newly added member may actually be offline; we'd be lying until the next `PRESENCE_UPDATE`.

Safer behavior:
- On ADD: do **not** force online. Leave presence alone (server can follow with PRESENCE_UPDATE), or add them to a "known members" set without setting status.
- On REMOVE: only clear presence if the user is no longer visible in any shared guild; otherwise leave intact.

Worth at least a TODO and an issue if not fixed in this PR.

### S2 — `MESSAGE_DELETE.guild_id` typed as optional but always sent *(low)*
Server now always emits `guild_id` (early-returns when no guild resolved). The client type `guild_id?: string` understates the contract; making it required (or documenting why it's optional, e.g. future DM channels) prevents downstream `if (guild_id)` guards that won't be needed for guild messages. Given the `TODO(#111)` for DM channels just below, optional is defensible — a one-line comment in the type would close the gap.

### S3 — Cascade cleanup loses unread-on-close state intentionally — confirm UX *(low)*
`removeChannel` on read-state store discards `readStates[channelId]` and `unreadChannels[channelId]`. Correct for a permanently deleted channel. Sanity check: this code path is *only* reached on server `CHANNEL_DELETE`, not on local channel-list reordering, right? A quick grep confirms it's only wired into the gateway subscription — good.

### S4 — Dev warning placement *(nit)*
```ts
if (payload.t && gatewayEvents.has(payload.t)) { ... }
else if (payload.t && payload.op === GatewayOpcode.DISPATCH) { ... }
```
The `payload.t && gatewayEvents.has(payload.t)` branch doesn't check `op === DISPATCH`, but registered events should only ever arrive as DISPATCH. Minor consistency tweak: gate both branches on `op === DISPATCH`, or factor it out. Not blocking.

### S5 — `removeChannelMessages` uses `delete` via destructure — fine, but inconsistent with `removeMessage` *(nit)*
Other reducers in `useMessageStore` use shallow spread + filter. The destructure-omit pattern here works (and is arguably cleaner), just noting the stylistic delta for future readers.

### S6 — No client-side test for cascade *(low)*
The README mentions `npm test` 152 passing; nothing exercises `CHANNEL_DELETE` cascading into the three stores, nor `GUILD_MEMBER_ADD/REMOVE` → presence side effects. A small test in the client package would lock in the behavior (especially valuable given S1).

## 4. Positive Notes

- 👏 **Symmetric server API**: `guildMemberAdd/Remove` parallels existing `channelCreate/Delete` style; payload shape matches Discord's Gateway docs (`guild_id`, `user`, `nick`, `roles`, `joined_at`).
- 👏 **Typing-store cleanup clears timeouts AND removes from `typingTimeoutIds`** — exactly the kind of detail that's easy to miss and leaks listeners. Nice.
- 👏 **Test updated alongside payload change** (`gateway.test.ts`) instead of after-the-fact.
- 👏 **Dev-only unknown-event warning** is a great low-friction observability win; will catch future server/client drift fast.
- 👏 Subscribe-before-broadcast on add / broadcast-before-unsubscribe on remove is the right sequencing for self-notification.

## 5. Verdict

**⚠️ Approve with one follow-up**

The PR is correct and well-executed for what it claims. The only thing I'd want before merge — or as an immediate follow-up issue — is **S1**: `GUILD_MEMBER_ADD/REMOVE` should not unconditionally flip global presence, since the presence store is user-scoped, not guild-scoped. Everything else is nit-level.

If S1 is filed as a follow-up issue with a TODO comment in `gateway-subscriptions.ts`, this is a clean ✅.

— 🌠 Nova
