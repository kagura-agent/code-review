# 🌠 Nova — Round 2 Re-Review · cove#384

**PR:** fix(client): mention follow-ups — a11y, word boundary, memo, Set cap (#341)
**Branch:** `fix/mention-followups-341` → `main`
**Size:** +150 / −25, 7 files
**Verdict:** ⚠️ **Needs Changes** (minor but material — perf claim doesn't hold, set-cap test is hollow)

---

## Round 1 fix verification

| # | R1 Ask | Status | Notes |
|---|--------|--------|-------|
| 1 | 10 tests | ✅ | 9 in `mention-trigger.test.ts` + 1 in `mention-set-cap.test.ts` = 10. Trigger tests cover both `@`/`#`, mid-word negatives, hyphenated channels, empty query. |
| 2 | Shared helper `detectMentionTrigger` | ✅ | New `packages/client/src/lib/mention-trigger.ts`; consumed by both `MentionAutocomplete`, `ChannelMentionAutocomplete`, and `MessageInput`. Single source of truth — clean. |
| 3 | `aria-activedescendant` | ✅ (with nit, see L1 below) | Added on both listbox containers with matching `id`s on options. |
| 4 | Word boundary unified | ✅ | Single check inside `detectMentionTrigger`: `if (triggerIndex > 0 && /\w/.test(before[triggerIndex-1])) return null;`. `MessageInput` no longer duplicates the regex — calls the helper. |

All four R1 items genuinely resolved.

---

## New findings (Round 2)

### 🔶 M1 — `useMemo` deps reference new arrays every render → memo is a no-op

In both `MentionAutocomplete` and `ChannelMentionAutocomplete`:

```ts
const members = activeGuildId ? getMembers(activeGuildId) : [];
// ...
const filtered = useMemo(() => { ... }, [members, query]);
```

`getMembers` in `useMemberStore` returns `Object.values(...)` — a **fresh array on every call**. Same shape for `useChannelStore.getChannels` and the subsequent `channels.filter(c => c.type !== 11)`. Because the dependency reference changes every render, `useMemo` re-runs every render — exactly the behavior it was supposed to prevent.

This contradicts the PR's “useMemo optimization — prevents re-filtering on every render” claim.

**Fix options** (pick one):
1. Memoize the source list inside the store selector (Zustand `useShallow` / `subscribeWithSelector`).
2. Switch the dep to a stable proxy: `[activeGuildId, members.length, query]` — accepts a small staleness risk on member edits but actually skips work.
3. Drop `useMemo` entirely and document that filtering ≤10 of a small in-memory list is cheap (honest).

Option 1 is the right call; option 3 is acceptable if perf isn't actually a concern.

### 🔶 M2 — `mention-set-cap.test.ts` doesn't test production code

```ts
// test re-implements the pruning inline:
if (set.size > 1000) {
  const entries = [...set];
  set.clear();
  for (let i = Math.floor(entries.length / 2); i < entries.length; i++) set.add(entries[i]);
}
```

This only verifies that the *test's own copy* of the algorithm works. If someone changes the cap or the eviction rule in `gateway-subscriptions.ts`, this test keeps passing. It satisfies the "add a test" ask but provides ~zero regression value.

**Fix:** extract pruning into an exported helper (see L2 below) and unit-test that helper.

### 🔵 L1 — `aria-activedescendant` defensive logic is redundant/fragile

```tsx
<div ... aria-activedescendant={filtered.length > 0 ? 'mention-option-' + filtered[activeIndex]?.user?.id : undefined}>
```

- The component already early-returns `null` when `filtered.length === 0`, so `filtered.length > 0` here is always true.
- If `activeIndex` is briefly stale after the list shrinks (before the reset effect fires), `filtered[activeIndex]?.user?.id` is `undefined` and the attribute becomes `"mention-option-undefined"` — pointing at nothing, which screen readers may announce oddly.

**Fix:**
```tsx
const active = filtered[activeIndex];
// ...
<div ... aria-activedescendant={active ? `mention-option-${active.user.id}` : undefined}>
```
Same simplification applies to `ChannelMentionAutocomplete`.

### 🔵 L2 — Set-cap pruning duplicated in two handlers (DRY)

The same ~7-line eviction block is pasted into both `MESSAGE_CREATE` and `MESSAGE_UPDATE` in `gateway-subscriptions.ts`. The whole spirit of this PR is "extract shared helpers" (R1 ask #2). Extract:

```ts
function trackMention(id: string) {
  mentionedMessageIds.add(id);
  if (mentionedMessageIds.size > MENTION_CAP) {
    const entries = [...mentionedMessageIds];
    mentionedMessageIds.clear();
    for (let i = Math.floor(entries.length / 2); i < entries.length; i++) mentionedMessageIds.add(entries[i]);
  }
}
```

Then test *this* function (resolves M2 too).

### 🔵 L3 — Trigger regex asymmetry between `@` and `#`

`@(\w*)` vs `#([\w-]*)` — hyphens allowed only for channels. This is intentional (PR body), and channel slugs typically allow hyphens while usernames typically don't. Fine to keep, but worth a short comment in `mention-trigger.ts` so the next reader doesn't "fix" the asymmetry.

### ℹ️ N1 — Coverage gap: `MessageInput` integration

`MessageInput` now also calls `detectMentionTrigger` to set `showMention` / `showChannelMention`. No test exercises that integration — the helper is tested in isolation, but the wiring in `handleChange` (e.g., that `email@gmail` no longer pops the menu in the actual input flow) isn't covered. Optional, but a small RTL test would close the loop on the user-visible bug being fixed.

---

## What I like

- Helper extraction is clean, tightly scoped, properly typed (`'@' | '#'` literal union).
- Word-boundary check is in **one** place — fixes the "two regexes drifting" smell from #339.
- a11y additions (`role=listbox` / `role=option` / `aria-selected` / `aria-activedescendant`) are the right shape — combobox pattern done correctly.
- Channel hyphen fix (`[\w-]*`) is a real bug fix with a test.
- Set cap solves a genuine long-session memory leak; eviction policy (keep newest half) is reasonable.

---

## Recommendation

⚠️ **Needs Changes** — small but worth a quick second push:

1. **M1**: make `useMemo` actually memoize OR drop it honestly.
2. **M2 + L2**: extract `trackMention()` helper, test the helper instead of duplicating logic in the test.
3. **L1**: tidy the `aria-activedescendant` expression (drop redundant guard, handle stale-index case).

L3 / N1 are optional. Once M1 + M2/L2 land, this is ✅ ready to merge.
