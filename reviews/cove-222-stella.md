# Stella Review — kagura-agent/cove PR #222 Round 3

## R2 Issue Status

1. **MESSAGE_DELETE_BULK not in client allowlist — ✅ Fixed**
   - `MESSAGE_DELETE_BULK` is now present in the WebSocket receive allowlist (`packages/client/src/stores/useWebSocketStore.ts:86-91`), so the existing subscription can be reached.
   - The handler still removes each ID from the local message store (`packages/client/src/lib/gateway-subscriptions.ts:47-51`).

2. **Message DELETE has no author check — ❌ Not Fixed, escalated**
   - Single-message delete still only validates channel/guild membership, then explicitly allows any guild member to delete any message (`packages/server/src/routes/messages.ts:114-130`).
   - This remains inconsistent with the edit path, which enforces self-ownership (`packages/server/src/routes/messages.ts:88-96`).
   - Existing coverage still only checks that a non-member cannot delete (`packages/server/src/__tests__/api.test.ts:953-959`); there is no same-guild non-author denial test.

3. **Bulk-delete: no age limit, no dedup — ❌ Not Fixed, escalated**
   - The endpoint still validates the raw `body.messages.length` before any uniqueness normalization (`packages/server/src/routes/messages.ts:154-161`), so duplicate IDs can satisfy the 2-item minimum.
   - The delete loop still iterates the raw submitted IDs without deduplication (`packages/server/src/routes/messages.ts:163-170`).
   - There is still no Discord-style age check before deleting messages (`packages/server/src/routes/messages.ts:145-176`). The new TODO only documents the missing permission model; it does not address age-limit or dedup semantics.

4. **Clear-all route doesn't broadcast deletions — ❌ Not Fixed, escalated**
   - `DELETE /channels/:id/messages` still deletes all rows and recomputes `last_message_id`, but emits no gateway event (`packages/server/src/routes/messages.ts:179-193`).
   - The initiating client clears its local store manually (`packages/client/src/components/ChatArea.tsx:26-31`), while other connected clients remain stale until refresh.

5. **R2 regression fixes untested — ❌ Not Fixed**
   - I still do not see coverage for bulk-delete endpoint behavior, bulk-delete dedup/age validation, same-guild non-author delete denial, clear-all broadcast behavior, or the `MESSAGE_DELETE_BULK` path through `useWebSocketStore`.
   - The only newly fixed R2 item (`MESSAGE_DELETE_BULK` allowlist) is not accompanied by a regression test.
   - I attempted `pnpm -r test` in a fresh PR worktree, but it could not run because that worktree had no `node_modules`; this does not change the static coverage gap above.

## New Issues

1. **Clear-all lets any guild member wipe a channel.**
   - The compatibility route has the same authorization gap as single delete, but with much higher blast radius: after `requireGuildMember`, any member can delete every message in the channel (`packages/server/src/routes/messages.ts:179-189`).
   - The UI exposes this operation through the clear button (`packages/client/src/components/ChatArea.tsx:52-54`). Without a permission system, this should be constrained or removed rather than left as a member-wide destructive operation.

## Summary & Verdict

Round 3 fixes one R2 blocker: `MESSAGE_DELETE_BULK` is now in the client allowlist. However, the higher-risk server-side deletion issues remain unresolved and should not be downgraded:

- Any guild member can still delete another member's message.
- Bulk-delete still lacks deduplication and age-limit semantics.
- Clear-all still does not broadcast deletions, and it also allows any guild member to wipe the entire channel.
- The important regression paths remain untested.

**Rating: ❌ Major Issues**
