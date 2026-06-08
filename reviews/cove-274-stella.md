# Stella Review — kagura-agent/cove#274

PR: feat: message-level unread indicators — NEW divider + banner (closes #193)
Reviewer: 🌟 Stella
Date: 2026-06-08

## Verdict

**Changes requested.** The UI direction is good and the client build/typecheck passes after wiring the worktree dependencies, but I found two correctness issues around live unread handling / cleanup that can make the banner misleading or disappear at the wrong time.

Validation performed:
- `gh pr diff 274 --repo kagura-agent/cove`
- Checked PR worktree at `31785f5`
- `pnpm -F @cove/client exec tsc -p tsconfig.json --noEmit --pretty false` ✅ after restoring the local workspace symlink for `@cove/shared` in the temporary worktree
- `pnpm -F @cove/client lint` ✅ existing warning only in `useWebSocketStore.ts`

## Findings

### 1. Live “new messages” banner has no divider target, so Jump can be a no-op

**Severity: High**

When the currently active channel receives messages while the user is scrolled up, the new-message effect sets `unreadInfo` and `showBanner`:

- `packages/client/src/components/MessageList.tsx:184-200`

But the divider is only rendered from `channelOpenReadId`, which is only snapshotted when the channel is already unread at open time:

- snapshot only on open unread: `MessageList.tsx:102-113`
- divider placement only from `channelOpenReadId`: `MessageList.tsx:250-254`
- banner click only scrolls to `dividerRef`: `MessageList.tsx:226-228`

For the live active-channel case, there is usually no `channelOpenReadId`, so `dividerBeforeIndex === -1`, `dividerRef.current` is null, and clicking “Jump” hides the banner without scrolling anywhere.

This is especially visible because the code explicitly creates the banner for this scenario (`wasNearBottomRef.current === false`), but does not create the corresponding divider anchor.

Suggested fix:
- Track a local `liveFirstUnreadId` / `firstUnseenMessageId` when the first message arrives while scrolled up.
- Render the divider before that message when there is no channel-open snapshot.
- Have banner click scroll to that divider; only hide the banner after a successful scroll / after reaching bottom.

### 2. Auto-hide timer is not cleaned up and can hide the next channel’s banner after rapid switching

**Severity: Medium**

The initial unread-open path schedules a 5s timer inside `requestAnimationFrame`:

- `packages/client/src/components/MessageList.tsx:138-146`

That timeout is never stored or cleared. If a user opens unread channel A, the timeout is scheduled, then quickly switches to unread channel B, the old timer can still call `setShowBanner(false)` on the reused `MessageList` component instance and hide B’s banner.

The fetch effect’s `cancelled` flag only protects the fetch continuation; it does not protect the later timeout callback after it has already been scheduled.

Suggested fix:
- Store the timeout id in a ref and clear it in the `[channelId]` cleanup.
- Also guard the callback with the channel id / a generation token before mutating state.

### 3. First visit to an unread/non-empty channel does not show the divider/banner

**Severity: Medium**

`initReadStates` marks a channel unread when it has `last_message_id` and `last_read_message_id !== last_message_id`, including the first-visit case where `last_read_message_id` is null:

- `packages/client/src/stores/useReadStateStore.ts:24-36`

But `snapshotChannelOpen` only writes a snapshot if `readStates[channelId]` exists:

- `useReadStateStore.ts:55-60`

So first visit to an unread channel with existing messages has `unreadChannels[channelId] === true` but no snapshot. The fetch path then sees no `openReadId`, scrolls to bottom, auto-acks the last message, and never shows the NEW divider/banner.

If this is intentional (“no prior read boundary means no divider”), it should be made explicit. If not, use a sentinel for “before first loaded message” or compute the first-visit divider as index 0.

### 4. Scroll-to-bottom hides the banner but does not clear the divider snapshot

**Severity: Low / UX**

The scroll handler comment says:

> If user scrolled to bottom, hide banner and clear divider

But it only hides the banner:

- `packages/client/src/components/MessageList.tsx:173-178`

The divider snapshot remains in `channelOpenReadIds` until unmount or “Mark as Read”. If the intended behavior is “divider remains as a session marker”, the comment should be corrected. If the intended behavior is to clear after the user reaches bottom, also call `clearChannelOpenSnapshot(channelId)` and clear `unreadInfo` when near-bottom.

## Non-blocking notes

- The O(n) `findIndex` during render is fine with the current `limit=50`; no performance concern unless message windows grow substantially.
- The banner `div role="button" tabIndex={0}` is not keyboard-activatable. Add `onKeyDown` for Enter/Space or make it a real `<button>` if accessibility matters for this pass.
- The gateway comment says “MessageList handles ack on scroll-to-bottom”, but current `MessageList` only acks after initial load, and gateway still acks every incoming active-channel message immediately. That may be acceptable for current Cove semantics, but it conflicts with unread UX for users who are scrolled up.
