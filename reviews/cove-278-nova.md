# PR #278 Review — `fix: rewrite MessageList scroll` (kagura-agent/cove)

Reviewer: 🌠 Nova
Verdict: **⚠️ Needs Changes** (one logic concern worth verifying + one UX edge case; everything else is non-blocking)

---

## 1. Summary

This PR rewrites `MessageList.tsx` to fix scroll flash, position-restore, and large-channel render cost. The design — module-level `scrollMemory`, distance-from-bottom as the stable metric, eager bottom-30 + `IntersectionObserver` lazy placeholders, and a `restoringRef` flag to silence the scroll listener during programmatic scrolls — is well-reasoned and the comments do an excellent job documenting the invariants. The core idea (rely on the scroll listener as the sole writer to memory; let `useLayoutEffect` only restore) is correct.

The implementation is mostly solid, but two issues are worth resolving before merge: (a) the `channelSwitchRef` guard relies on RAF ordering that doesn't actually protect the passive effects it claims to, and (b) scroll restoration into older-than-eager-zone history is fragile because `LazyMessageItem` re-mounts with `visible=eager` whenever the channel switches.

---

## 2. Critical Issues

### C1. `channelSwitchRef` RAF clearing likely fires *before* the effects it guards
`MessageList.tsx`, effect #1 (useLayoutEffect):

```ts
channelSwitchRef.current = true;
requestAnimationFrame(() => {
  channelSwitchRef.current = false;
});
```

Effects #5/#6/#7 are passive `useEffect`s and read `channelSwitchRef.current` to bail out. Standard browser ordering is:

```
layout effects (sync) → microtasks → rAF callbacks → paint → passive effects
```

React 18 flushes passive effects after paint (via `MessageChannel`/scheduler), so the RAF callback clearing `channelSwitchRef` runs **before** effects #5/#6/#7 see it. The guard is effectively a no-op in those effects.

In practice, the bug is partially masked:
- Effect #5 is also gated by `messages.length > prevCountRef.current`, and `prevCountRef.current` is updated to `messages.length` inside the layout effect — so this one is safe.
- Effects #6/#7 are additionally gated by `wasNearBottomRef.current`, which the layout effect also sets correctly from `mem.wasAtBottom`. So on a mid-scroll restore, they won't fire either.

So the guard is **dead code** but *probably* not breaking anything today. Still worth fixing because:
- The comment promises behaviour that the code does not actually deliver — future maintainers will rely on this.
- If anyone later adds an effect that doesn't have a secondary gate, the restore-undo will silently regress.

**Recommended fix:** drop `channelSwitchRef` entirely and rely on the existing secondary gates (they're sufficient and clearer), OR clear it inside a passive effect with `[channelId]`, e.g.:

```ts
useEffect(() => {
  channelSwitchRef.current = false;
}, [channelId]);
```

…and set it synchronously inside the layout effect as today. That gives the right "true during the current commit, false by the time later passives in *future* renders see it" semantics, though even this is brittle. Removing the ref is cleaner.

### C2. Scroll restore for "scrolled up past the eager 30" is fragile
`distanceFromBottom` is correctly invariant **as long as the bottom 30 messages are eager and fully rendered** — but `LazyMessageItem` is a fresh component instance on every channel switch, so `visible` resets to `eager` (i.e. only the bottom 30). If a user was reading message #100 of 500 in channel A (well above the eager zone), `scrollMemory[A].distanceFromBottom` is large. On return:

- New `MessageList` render → 470 placeholders (60 px each) + 30 eager messages
- `scrollHeight` may be smaller than the saved `distance + clientHeight`
- `restoreDistanceFromBottom` computes `scrollTop = scrollHeight - dist - clientHeight`, which can be **negative** → clamped to 0 → user lands at top of the placeholder stack, not at message #100.

`IntersectionObserver` with the 2000 px rootMargin will then chain-render upward, but the user sees a jump (top of list, then content fills in) — the exact "no flash" outcome this PR is trying to deliver.

This is a real edge case for any channel where the user has scrolled meaningfully into history. For small/recently-active channels it never trips.

**Recommended fix (pick one):**
- Cheap: save `visibleCountAtSave` (or the topmost-rendered index) alongside `distanceFromBottom`, and pass it to the new render as the initial eager range so the prior rendered region is preserved.
- Cleaner: persist the `visible` state of `LazyMessageItem` by channel + message id, e.g. a `Set<channelId:msgId>` in a module-level map, and seed `useState(eager || hasBeenVisible(channelId, id))`.
- Pragmatic compromise: bump `EAGER_COUNT` (e.g. 50) and accept the perf cost — most channels won't have users >50 messages back.

Worth at minimum a TODO comment in the file so the limitation is visible to future readers.

---

## 3. Product Impact

**Positive (user-visible wins):**
- No more scroll flash on revisits — this is the headline win and the architecture genuinely delivers it for the common case (bottom-anchored or near-bottom revisits).
- 5-minute cache-staleness cuts perceived load time on rapid channel switching.
- Lazy rendering should noticeably reduce CPU/memory on long channels at mount time.

**Risks:**
- **Mid-scroll restore in long channels** (see C2) may regress — users who scroll way back and switch away might land at the top instead of where they left off. Test by scrolling ≥50 messages up in a busy channel, switching, and switching back.
- **WebSocket-added messages won't refresh `lastFetchTime`**, so the 5-minute staleness window is anchored to the last full fetch, not last message arrival. This is correct (WebSocket is the source of truth for liveness) but worth verifying that WebSocket subscription is unconditionally active and never relies on the fetch path to "kick" it.
- **Bottom-of-pinned auto-scroll** for content edits/reactions is now gated on `wasNearBottomRef` which is set in the restore path — if a streaming message lands exactly during a channel switch, the new behavior could be slightly different from before (probably fine, but a regression vector).

---

## 4. Suggestions (non-blocking)

- **S1 — Effect #2 can be `[]`-dep.** The scroll listener uses `channelIdRef`, so there's no reason to detach/reattach on every channel switch. Make the effect mount-once.
- **S2 — `scrollMemory` / `lastFetchTime` / `lastAckedIds` grow unbounded.** Per-tab in a long-running SPA with many channels (DM list etc.), this is a minor leak. Consider an LRU cap (e.g. last 100 channels) or a cleanup on channel-delete events.
- **S3 — `pendingScrollToBottomRef` flag pattern.** The "effect with no deps that fires every render" (effect #4) works but is a footgun. Consider folding it into the fetch `.then` with `flushSync` + immediate scrollTop assignment, or a state-based marker reset in the same effect. Current code is fine but unusual enough to deserve a clearer comment.
- **S4 — `PLACEHOLDER_HEIGHT = 60`.** Real message heights vary widely (one-line vs. attachments vs. embeds). For tall messages outside the eager zone, the placeholder→real transition will shift surrounding content. With 2000 px rootMargin it usually pre-renders before the user sees it, but on fast scroll up you'll see jumps. Not blocking.
- **S5 — `restoringRef` is cleared in RAF.** Same ordering caveat as C1 — RAF fires before paint, but the next scroll event a user fires won't happen mid-frame, so this is safe in practice. Worth a one-line comment noting why a single RAF is enough.
- **S6 — No tests added.** This module now has 7 distinct effects coordinating via 6 refs and 3 module Maps. A handful of jsdom-level tests for the channel-switch matrix (cached/uncached × bottom/mid-scroll × first-visit/return) would pay for themselves the first time someone touches this code.
- **S7 — `console.error("loadMessages:", err)`** is the only error surfacing — silent failure for the user. Consider an `antd` notification or at least a retry surface.

---

## 5. Positive Notes

- **Comments are excellent.** The block comment at the top genuinely explains the architecture and the *why* behind each subtle choice (why distance-from-bottom, why cleanup doesn't save, why `restoringRef`). This is rare and valuable.
- **Distance-from-bottom over `scrollTop`** is the correct insight for a lazy-rendered list. Most attempts get this wrong.
- **Single-writer principle for `scrollMemory`** (scroll listener only) is the right call and is clearly stated.
- **`restoringRef` to suppress the listener during programmatic scrolls** is the standard correct fix for the "save-during-restore overwrites memory" race — good to see it done explicitly rather than via timing hacks.
- **`channelIdRef` mirror** so the scroll handler is never stale is a clean pattern.
- **`LazyMessageItem`** is small, focused, and self-cleans its observer. The `eager` prop as the initial state correctly avoids a flash for the bottom region.
- **Smart-cache + ack split** in effect #3 is a nice touch — preserves read-state semantics without a redundant fetch.

---

### Verdict: ⚠️ Needs Changes

Recommend addressing **C1** (delete or correctly schedule `channelSwitchRef`; current implementation is misleading dead code) and at least acknowledging **C2** with a TODO + manual test of the deep-scroll-and-return path. Everything else is polish.
