# Stella R2 Review — kagura-agent/cove PR #278

## Verdict

**Request changes.** The R1 first-visit listener bug is fixed, and the old `channelSwitchRef` dead guard has been removed, but scroll restore is still not reliable in stale/deep-history cases. Also, the client lint gate currently fails on the PR code.

## R1 issue check

### R1 Must Fix 1 — Scroll listener never attached on first channel visit
**Status: Addressed.**

The scroll listener effect now depends on `[channelId, hasMessages]`, so when the initial spinner/no-container render transitions to a message list, the effect re-runs and attaches the listener.

### R1 Must Fix 2 — Scroll restore breaks for deep history
**Status: Partially addressed, still blocking. Severity remains Critical.**

`LazyMessageItem` now persists revealed message IDs in a module-level `Set`, which fixes the specific “visible state resets on channel switch” failure for messages that were already revealed. However, the broader deep-history restore problem is still present because restore still depends on a fixed `60px` placeholder for unrevealed items. Any unrevealed content between the restored viewport and the bottom can still make `distanceFromBottom` diverge from the real layout.

There is also a new stale-cache restore regression: revisiting a cached but stale channel first restores the saved position, then the fetch path unconditionally sets `pendingScrollToBottomRef.current = true`, causing the next layout effect to scroll to bottom and overwrite the restored position. This means position restore works only for fresh cache, not for cached channels older than 5 minutes.

Relevant code:
- `packages/client/src/components/MessageList.tsx:205-233`
- `packages/client/src/components/MessageList.tsx:258-269`
- `packages/client/src/components/LazyMessageItem.tsx:3`

### R1 Must Fix 3 — `channelSwitchRef` RAF guard is dead code
**Status: Addressed for the exact R1 issue.**

The old `channelSwitchRef` approach is gone. The new `restoringRef` is used directly by the scroll handler around programmatic scroll changes, so the exact “RAF fires before passive effects and the effect always sees false” issue no longer applies.

There is still a smaller race risk from uncleared RAF callbacks if channel switches happen rapidly, but I would treat that separately from the R1 blocker.

## New / remaining blocking findings

### Critical — Client lint fails on this PR

The PR violates the configured React hooks lint rules by mutating a ref during render:

```ts
const channelIdRef = useRef(channelId);
channelIdRef.current = channelId;
```

I ran:

```bash
node /home/kagura/.cache/node/corepack/v1/pnpm/10.11.0/bin/pnpm.cjs -C /home/kagura/.openclaw/workspace/cove -F @cove/client lint
```

Result:

```text
packages/client/src/components/MessageList.tsx
119:3  error  Error: Cannot access refs during render
react-hooks/refs
```

This will block CI if lint is part of the required checks. Move the ref update into an effect/layout effect, or avoid the ref by making the scroll listener close over the `channelId` from its own effect instance.

### Critical — Stale cached channels lose restored scroll position after fetch

For cached channels older than `STALE_MS`, the flow is:

1. `useLayoutEffect([channelId])` restores the cached channel’s saved position.
2. The fetch effect sees `hasCached && isStale`, so it fetches anyway.
3. When fetch resolves, it always sets `pendingScrollToBottomRef.current = true`.
4. The no-deps layout effect scrolls to bottom.

That makes “restore position across channel switches” fail after the cache becomes stale, which is a core behavior of this PR.

Suggested direction: distinguish first-time load from stale refresh. Only force bottom after an uncached initial load, or only if the saved/restored state says the user was already at bottom.

### Critical — Deep-history distance restore still depends on fixed placeholder heights

The PR summary says distance-from-bottom is stable because older messages are lazy placeholders, but that is only true if placeholder heights match real heights or all relevant items below the viewport have already been revealed. In real message history, message heights vary significantly: grouped messages, multi-line content, attachments, reactions, edits, etc.

Persisting `revealedIds` helps revisits to already-seen items, but it does not solve unrevealed items. A fixed `60px` placeholder can still compress or expand the DOM between the viewport and bottom, so restoring a deep-history `distanceFromBottom` can land at the wrong message.

Suggested direction: store/measure per-message heights once revealed and use those as placeholders, or restore by anchored message ID + offset instead of total distance from bottom.

## R1 Suggestions status — escalated per R2 rule

Per the requested R2 escalation rule, unaddressed R1 suggestions are now treated as Critical.

### Critical — Unbounded module-level caches remain unbounded

R1 noted unbounded `Map`s. This PR still has unbounded module-level state, and now adds another unbounded structure:

- `scrollMemory`
- `lastFetchTime`
- `lastAckedIds`
- `revealedIds`

There is no eviction, no cleanup on channel removal, and no bound by workspace/server/session. This can grow for the lifetime of the tab.

### Critical — Date parsing overhead remains in render

`new Date(...).getTime()` still runs during every render for each adjacent message pair:

```ts
new Date(msg.timestamp).getTime() - new Date(prev.timestamp).getTime()
```

This was called out in R1 and remains unchanged.

### Critical — Fixed placeholder height remains

`PLACEHOLDER_HEIGHT = 60` remains unchanged. This is both the unaddressed R1 suggestion and part of the remaining deep-history correctness issue above.

### Critical — No tests added for the scroll rewrite

No tests were added for the new scroll architecture or lazy rendering behavior. Given the number of effects, refs, timing-sensitive layout behavior, and previous regressions, this needs coverage for at least:

- first visit spinner → messages attaches scroll listener
- cached channel switch restores position before paint
- stale cached channel refresh does not force bottom unless appropriate
- deep-history lazy items do not reset to placeholders on revisit
- programmatic restore does not overwrite saved scroll memory

### Critical — User-visible fetch failure handling remains weak

Fetch errors still only log to console:

```ts
.catch((err) => console.error("loadMessages:", err));
```

The UI remains stuck in the loading/old-cache state with no user-visible error or retry path. Ack failures are also swallowed. This was called out in R1 and remains effectively unaddressed.

## Non-blocking notes

- `LazyMessageItem` uses a module-level `Set`, which is pragmatic for remount persistence but makes behavior global to the JS module. If message IDs are not globally unique across all channels/servers, this can cross-contaminate reveal state.
- The no-deps `useLayoutEffect` is intentional here, but it makes the scroll timing harder to reason about. Tests would help prevent future regressions.
