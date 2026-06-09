# Stella R4 Re-review — kagura-agent/cove#278

**PR:** fix: rewrite MessageList scroll — position restore, no flash, lazy rendering  
**Round:** 4  
**Verdict:** ❌ Request changes

The Round 3 cleanup item was addressed: the unused `cappedSetAdd` / `SET_CAP` / `SET_EVICT` dead code in `MessageList.tsx` is gone.

However, the latest update introduced a new lint-blocking React refs violation in `MessageList.tsx`. This is a must-fix before merge because the branch no longer passes the client lint gate.

## Verification performed

- Fetched latest PR metadata with `gh pr view 278 --repo kagura-agent/cove --json title,body,headRefName,baseRefName,headRepositoryOwner,commits`.
- Saved latest PR diff to `code-review/reviews/cove-278-r4-current.diff` via `gh pr diff 278 --repo kagura-agent/cove`.
- Checked out the latest PR head locally at `975f259`.
- Inspected:
  - `packages/client/src/components/MessageList.tsx`
  - `packages/client/src/components/LazyMessageItem.tsx`
- Ran `pnpm -F @cove/client lint`: ❌ failed.
- Ran `pnpm -F @cove/client exec tsc --noEmit`: ✅ passed.

## R3 issue follow-up

### 1. Dead code: unused `cappedSetAdd` / `SET_CAP` / `SET_EVICT` — ✅ addressed

R3 cleanup item: `MessageList.tsx` had unused capped-set helper code while `LazyMessageItem.tsx` had its own revealed-id eviction.

Latest code no longer contains the unused `cappedSetAdd`, `SET_CAP`, or `SET_EVICT` definitions in `MessageList.tsx`. No escalation needed; this was fixed.

## New must-fix finding

### 🔴 Blocking: `MessageList` reads `scrollContainerRef.current` during render

`MessageList.tsx` now passes the scroll root into each lazy item during render:

```tsx
<LazyMessageItem
  key={msg.id}
  messageId={msg.id}
  eager={eager}
  scrollRoot={scrollContainerRef.current}
>
```

This violates React's refs rule: refs are mutable values that should not be read during render unless using a safe initialization pattern. ESLint catches it as an error:

```text
/home/kagura/.openclaw/workspace/cove/packages/client/src/components/MessageList.tsx
  354:23  error  Error: Cannot access refs during render

React refs are values that are not needed for rendering. Refs should only be accessed outside of render, such as in event handlers or effects. Accessing a ref value (the `current` property) during render can cause your component not to update as expected.
react-hooks/refs
```

This is not just cosmetic. On first load, `scrollContainerRef.current` is still `null` during the render that creates the scroll container, so lazy items initially register against the document viewport rather than the intended scroll container. The code is trying to address the R3 IntersectionObserver-root follow-up, but the current implementation does it through a render-time ref read and fails lint.

**Suggested fixes:**

Option A — use a callback ref and state for the scroll root:

```tsx
const [scrollRoot, setScrollRoot] = useState<HTMLDivElement | null>(null);

<div ref={setScrollRoot} ...>
  {messages.map(...
    <LazyMessageItem scrollRoot={scrollRoot} ...>
```

This makes the root a real render dependency and avoids direct `ref.current` reads in render.

Option B — keep the root lookup inside `LazyMessageItem`'s effect by passing a stable getter or parent ref object, but avoid reading `.current` during parent render. A callback-ref/state approach is simpler and clearer here.

## Follow-up observations

- The shared `IntersectionObserver` implementation is a good direction and addresses the R3 performance suggestion of avoiding one observer per item.
- Passing an explicit root is also the right direction, but it needs to be wired in a React-safe way as above.
- The remaining R3 follow-ups are still valid but non-blocking: targeted scroll regression tests, Date parsing overhead, fixed 60px placeholder height, and user-visible fetch failure/retry state.

## Overall assessment

Round 4 fixes the R3 dead-code cleanup, and the shared observer/root work is conceptually useful. But the branch currently fails `pnpm -F @cove/client lint` due to reading `scrollContainerRef.current` during render. Please fix that before merge, then re-run lint/typecheck.
