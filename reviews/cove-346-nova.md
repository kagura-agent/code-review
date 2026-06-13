# 🌠 Nova — Round 2 Re-Review · PR #346 (cove)

**PR:** feat: NEW separator line and unread banner (closes #193, closes #275)
**Branch:** `feat/unread-experience`
**Diff size:** +237 / −11 (2 files: `docs/unread-spec.md`, `packages/client/src/components/MessageList.tsx`)

---

## 1. Summary — what changed since R1

The author landed a focused rewrite of the unread‑indicator block in `MessageList.tsx` and shipped a spec document (`docs/unread-spec.md`) that pins the contract. The key structural changes vs. R1:

- A separate `useEffect` now **computes the unread count once per channel entry** (`unreadComputedForRef`), independent of the inline render path. This is where the C1/C2 corrections live.
- The NEW‑separator render path now has **three explicit cases (A/B/C)** instead of a single `prev.id === lastReadId` check, so the line can now render at the top of the list when `lastReadIdx === -1` or `lastReadId == null`.
- `Mark as Read` now calls `useReadStateStore.markRead(...)` **and** `api.ackMessage(...)` directly, not via a side effect.
- Sending an own message (`pending-…`) now explicitly clears the NEW line.
- Scroll-to-bottom in the scroll handler clears banner + pill (matches spec rule).

Overall the implementation now matches the spec the author committed in `docs/unread-spec.md`. The remaining concerns are mostly cosmetic, plus one **moderate accuracy bug** in the unread count for Case B/C (counts loaded messages instead of true unread).

**Verdict: ⚠️ Needs Changes (small)** — ready to land after one count‑accuracy tweak and a positioning fix. None of the R1 *critical* issues are still live.

---

## 2. Previous Issues Status (Round 1)

### Critical

| # | Issue | Status | Evidence |
|---|-------|--------|----------|
| **C1** | NEW line unreachable when `lastReadIdx === -1` (snapshot id no longer in window) | ✅ Fixed | Render path now has explicit **Case B/C** branch: `(i === 0 && (!lastReadId || !lastReadIdInMessages))` (MessageList.tsx ~L630). Effect also sets `showNewLine=true` in the `lastReadIdx === -1` and `!lastReadId` branches (~L208/L217). Manually traced: when snapshot is stale, `lastReadIdInMessages=false`, so `isFirstUnread` is true at `i===0` and the red bar renders above message 0. |
| **C2** | No indicators for never‑read channels (`lastReadId == null`) | ✅ Fixed | Dedicated branch in the compute effect (~L196–L204): `if (!lastReadId) { setEntryUnreadCount(messages.length); setShowNewLine(true); setShowTopBanner(true); }`. Render path treats `!lastReadId` the same as Case B. |
| **C3** | Top banner persists forever on bottom-entry (scroll restore suppresses scroll events) | ✅ Fixed *per spec* | The author chose to **redefine the rule** in `docs/unread-spec.md`: banner only dismisses on (a) user scroll‑to‑bottom or (b) `Mark as Read`. The restoring path sets `restoringRef.current=true` so the programmatic `scrollToBottomImmediate` does not fire the scroll handler — meaning if the user lands at bottom and never moves, the banner persists. That is now **documented behavior**, not a bug. I am downgrading from critical to acceptable; see §4 for a UX nit. |
| **Nova‑1** | `Mark as Read` only worked coincidentally via auto‑ack | ✅ Fixed | New `onClick` (MessageList.tsx L585–L596) explicitly: (1) calls `useReadStateStore.getState().markRead(channelId, lastMsg.id)`, (2) calls `api.ackMessage(...)`, (3) `scrollToBottom()`, (4) clears local banner + NEW line. Correctly guards against `pending-` ids before calling ack. |

### Non‑blocking suggestions (R1)

| Suggestion | Status |
|------------|--------|
| Wrapper `<div key={msg.id}>` instead of Fragment | ❌ Not fixed (still a wrapping `<div>`; extra DOM nodes for every row) |
| Bottom pill positioning ancestor | ❌ Not fixed (pill is in the outer `<>` Fragment, *outside* the `position:relative` container — see Issue N1 below) |
| Batch pill counter | ⚠️ Partial — counter increments per `messages.length` change; throttling via batched RAF would be cheaper |
| a11y on banner/pill buttons | ❌ Not fixed (`<span onClick>` with no `role="button"`, no keyboard handler, no `aria-live`) |
| Channel‑switch race | ⚠️ Partial — channel‑switch effect resets state, but the compute effect depends on `messages` and can run with **stale messages from the old channel** if the new channel hasn't fetched yet. The early‑return `unreadComputedForRef.current === channelId` plus the channel‑switch reset cover this; still a bit subtle |
| `isOwnMessage` via `id.startsWith("pending-")` | ❌ Not fixed (heuristic only; once the server confirms and the id is rewritten, the next post‑confirm render won't be considered "own", which is harmless here but still smelly) |
| Scroll handler throttling | ❌ Not fixed |
| Missing tests | ❌ Not fixed — no new tests for the NEW separator, banner timing, ack call, or pill |

---

## 3. New Issues introduced by the fix commits

### N1. (Moderate) — `entryUnreadCount` lies for Case B and Case C

In both `!lastReadId` and `lastReadIdx === -1` branches the count is set to `messages.length`:

```ts
// MessageList.tsx ~L198 and ~L210
setEntryUnreadCount(messages.length);
```

`messages` is only the loaded window (`PAGE_SIZE = 50` per fetch). A channel with 800 truly‑unread messages will display **"50 new messages"** in the blue banner. The store already has `last_message_id` and `last_read_message_id` from `initReadStates` — true unread can be derived without a server round‑trip for *most* channels (count by id ordering once you have both endpoints), or at least the banner copy should degrade to "50+ new messages" when `hasMore && lastReadIdInMessages === false`.

**Impact:** misleading badge for any user returning to a long‑neglected or never‑visited channel. Caught the eye fast in manual review. Worth fixing before ship.

**Suggested patch (minimum):**
```ts
const more = hasMoreHistory.get(channelId) !== false;
const count = messages.length;
setEntryUnreadCount(count);
// In banner JSX:
<span>{entryUnreadCount}{more && !lastReadIdInMessages ? "+" : ""} new …</span>
```

### N2. (Low) — Bottom pill is positioned against the wrong ancestor

```tsx
return (
  <>
    <div style={{ position: "relative", flex: 1, ... }}>{/* list */}</div>
    {newMessagesBelowCount > 0 && (
      <div style={{ position: "absolute", bottom: 48, left: "50%", ... }}>…</div>
    )}
    <TypingIndicator />
    …
  </>
);
```

The pill has `position: absolute` but its parent in the DOM is whatever wraps `<MessageList />` in the page layout, **not** the `position:relative` div that owns the list. Result: in any layout where the MessageList parent is not itself positioned, the pill snaps to the document body (or whatever positioned ancestor exists) — `bottom: 48` is no longer measured from the message viewport. R1 raised this; still unfixed.

**Fix:** move the pill inside the existing `<div style={{ position: "relative", flex: 1, ... }}>` (next to the banner) OR move it into a wrapping `<div style={{ position: "relative" }}>` that surrounds both the list and the pill.

### N3. (Low) — Render‑path `messages.some(...)` is O(N²) per render

```tsx
{messages.map((msg, i) => {
  …
  const lastReadIdInMessages = lastReadId
    ? messages.some((m) => m.id === lastReadId)   // ← per-row O(N) scan
    : false;
  …
})}
```

For each row the code scans the entire array. With 500 messages that's 250k id comparisons per render. The compute effect already knows whether `lastReadIdx === -1`; hoist a single `lastReadIdInMessages` constant (or `lastReadIdx`) **outside** the `.map`, or store it in state alongside `showNewLine`.

### N4. (Low) — `Mark as Read` silently no‑ops on a `pending-` last message

```tsx
if (lastMsg && !lastMsg.id.startsWith("pending-")) {
  useReadStateStore.getState().markRead(channelId, lastMsg.id);
  api.ackMessage(channelId, lastMsg.id).catch(() => {});
}
scrollToBottom();
setShowTopBanner(false);
setShowNewLine(false);
```

When the very last visible row is the user's own optimistic message (`pending-…`), we *still* clear local banner/NEW state but neither ack nor markRead is sent. The next channel switch will compute against a stale `lastReadId` from the store, and the NEW line will jump back to where it was. Two safe options:

1. Walk backwards to find the last non‑pending message and ack that.
2. Defer the ack: keep banner cleared locally, set a "pendingAck" flag, and let effect #5 perform the ack once the pending id flips.

### N5. (Low) — `Mark as Read` does not respect order

`api.ackMessage(channelId, lastMsg.id)` is fire‑and‑forget with `.catch(() => {})`. If the network fails the local store is already updated (`markRead`) and the user sees no error, but the server still thinks the channel is unread. On next session refresh / `initReadStates` the unread badge reappears. At minimum: swap order — ack first, then markRead on success. Or surface the failure (toast).

### N6. (Very low) — `<div key={msg.id}>` wrapper changes the rendered DOM tree

Previously `LazyMessageItem` was a direct child of the scroll container; now every row gets an extra `<div>`. Any CSS rule relying on `.scroll-container > [data-message-id]` direct‑descendant selectors will silently break. Scanned the repo: no such selectors today, but worth a note in the PR description.

### N7. (Trivial / pedantic) — Bottom pill calls `scrollToBottom()` but does not ack

The blue banner's `Mark as Read` calls `markRead + ackMessage`; the bottom pill only `scrollToBottom()`s. Once the user lands at bottom, the `onScroll` handler clears the pill state but **no ack is sent** (auto‑ack effects #3/#5 only run on initial fetch and own‑send paths). So the channel stays "unread" in the store/sidebar until the next channel‑switch refetch hits effect #3. Either:
- Ack inside the pill `onClick`, or
- Add an ack inside `onScroll` when `atBottom && !lastAckedIds.get(channelId) === lastMsg.id`.

This was implicit in the spec ("scroll to bottom → clear top banner / clear bottom pill") but the spec doesn't say *and ack* — yet without ack the unread badge in the sidebar stays lit. Worth clarifying with the author before ship.

### N8. (Spec drift) — PR description vs. implementation

The PR body still shows the **old** banner copy: *"{count} new messages — Jump ↑"*. The actual code (and the spec doc) shows *"{N} new messages … Mark as Read"*. Update the PR description so reviewers / future archaeology match the code.

---

## 4. Remaining Suggestions (already on the table, restated)

- **Accessibility** — both clickable `<span>`s should be `<button type="button">` with focus styles + `aria-live="polite"` on the banner so screen readers announce arrival.
- **Tests** — the spec doc is a great test outline. At minimum:
  - never‑visited channel renders NEW line + banner
  - returning channel with lastReadId in window renders separator between read/unread
  - returning channel with stale lastReadId renders separator at top
  - sending own message clears NEW line
  - scroll-to-bottom clears banner+pill, does NOT clear NEW line
  - `Mark as Read` calls `ackMessage` exactly once
- **Scroll handler throttling** — `setShowTopBanner(false)` fires on every scroll event past threshold; once already false the setState is a no‑op but the handler still runs id comparisons + `cappedMapSet` every frame. RAF‑throttle as a follow-up.
- **Bottom pill semantics** — Discord shows the pill in *addition* to the bottom auto‑scroll arrow. Worth verifying the pill doesn't overlap an existing scroll arrow / typing indicator at `bottom: 48`.

---

## 5. Positive Notes

- 👏 **Committing `docs/unread-spec.md` is excellent** — it converts the previous fuzzy review thread into a testable contract and is the right way to resolve cross-reviewer disagreement on banner timing.
- 👏 **Effect separation is clean** — the channel-switch reset (`useEffect` on `channelId`) and the compute-once effect (`unreadComputedForRef`) cleanly decouple "what is the snapshot" from "have I computed indicators for this entry". This eliminates the rerender hazards from R1.
- 👏 **Case A/B/C is explicit and commented** — no longer requires the reader to derive the dead branch.
- 👏 **Mark-as-Read now writes to the source of truth** — both store update and server ack. The earlier "works by accident" path is gone.
- 👏 **Sending message clears NEW line** — matches spec rule "user is engaged", removes the awkward red bar after typing a reply.
- 👏 **`restoringRef` guard prevents spurious banner dismissal during channel switch** — the right primitive was reused instead of inventing a new flag.

---

## Verdict

**⚠️ Needs Changes** — small. Critical R1 blockers are all gone; the remaining issues are one **moderate count-accuracy bug** (N1), one **positioning regression that was already noted in R1** (N2), and a handful of polish items (N3–N8). After fixing N1 (or at least appending "+") and N2, this is mergeable. The new spec doc is a meaningful quality bump and should stay.
