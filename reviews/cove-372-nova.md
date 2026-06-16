# 🌠 Nova Review — PR #372: Discord-style empty channel welcome screen

**Repo:** kagura-agent/cove
**PR:** [#372](https://github.com/kagura-agent/kagura-agent/cove/pull/372) — feat(client): Discord-style empty channel welcome screen (#284)
**Scope:** 1 file, +51/-6 (`packages/client/src/components/MessageList.tsx`)
**Verdict:** ⚠️ **Needs Changes** — small but real cleanup items before merge.

---

## 1. Summary

Replaces the `<Empty>` placeholder shown when a channel has no messages with a Discord-style welcome layout: `# channel-name` heading, a "This is the beginning of the #name channel." subtitle, and the channel topic (when present). Channel data is read from `useChannelStore.channelsByGuildId` via a linear scan inside `MessageList`. The change is contained, theme-aware (uses CSS vars), and lines up well with #284's intent. There are no logic regressions, but there is dead-code import, a slightly noisy store subscription, and a couple of polish items (heading semantics, hardcoded English) worth tightening.

---

## 2. Critical Issues

None blocking correctness. The two items below are blocking on cleanliness/lint:

### 🔸 C1 — `Empty` import is now unused
`import { Spin, Empty } from "antd";` is left intact, but `Empty` is no longer referenced anywhere in the file. Any project with `noUnusedLocals` / `@typescript-eslint/no-unused-vars` strict will flag this. Author says `tsc --noEmit` passed, so the strict flag may be off, but this is still dead code.
**Fix:** drop `Empty` from the import: `import { Spin } from "antd";`.

### 🔸 C2 — `channelsByGuildId` selector causes broad re-renders
```ts
const channelsByGuildId = useChannelStore((s) => s.channelsByGuildId);
```
This subscribes `MessageList` to the entire guild→channels map. Any add/update/remove anywhere — including in guilds the user isn't viewing — re-renders the message list. `MessageList` is the hot path; this is a small but real perf regression.
**Fix:** select only what's needed, e.g.
```ts
const currentChannel = useChannelStore((s) => {
  for (const list of Object.values(s.channelsByGuildId)) {
    const found = list.find((c) => c.id === channelId);
    if (found) return found;
  }
  return null;
});
```
or, even cleaner, expose a `getChannelById(id)` selector on the store and use it. The IIFE-on-every-render pattern (`const currentChannel = (() => { ... })()`) also goes away.

---

## 3. Product Impact

- **First-impression upgrade.** The 🌊 + "No messages yet — be the first!" placeholder always read like a half-finished UI. The new layout is recognizably "channel intro" and matches Discord's mental model — users will stop wondering whether something is broken.
- **Empty-channel UX only.** Behavior for channels with messages is unchanged (the early-return branch is hit only when `messages.length === 0` and not loading). Loading state still shows the `Spin`. No risk to existing channels.
- **Topic is now visible at empty state.** If users have set sensitive/internal topics, they'll be surfaced more prominently than before. Probably desired — but worth a heads-up.
- **Brief "# channel" flash possible.** On hard reload of a deep link, `channelsByGuildId` may not be hydrated by the time `MessageList` renders an empty channel; the fallback `channelName = "channel"` will show "# channel / This is the beginning of the #channel channel." for a frame or two. Mostly invisible in practice, but see S2.

---

## 4. Suggestions (non-blocking)

### S1 — Heading level
A page-level `<h1>` inside a sub-region usually competes with whatever heading already labels the page (guild name, app title). Consider `<h2>` (or scope by section) so screen readers and document outlines stay coherent. Visual size is controlled by inline `fontSize: 32` anyway.

### S2 — Hide welcome screen until channel is known
Right now, while `currentChannel == null`, the UI renders "# channel / This is the beginning of the #channel channel." That's harmless but a little embarrassing. Two options:
- Render the existing `Spin` while `currentChannel == null` (treat unknown channel as still loading), or
- Render `null` for that frame.

### S3 — i18n / copy
"This is the beginning of the #X channel." is hardcoded English. If the codebase has any i18n layer (or plans one), wrap this string. If not, fine — but worth a TODO.

### S4 — `# {channelName}` rendering
Using `# {name}` as plaintext inside `<h1>` is fine; just be aware that it can be selected/copied with the leading `#` and may collide with hash-routing patterns in browsers' Quick Find. Cosmetic.

### S5 — `var(--text-secondary, #949ba4)` fallback
`#949ba4` is Discord's exact muted color. Make sure the project has `--text-secondary` defined for both light and dark themes; otherwise dark mode gets Discord muted-grey on Cove dark-grey, which is muddy. (If the var is already defined globally, the literal fallback is just defensive — fine.)

### S6 — Memoize the channel lookup
Even after C2, wrapping the lookup in `useMemo([channelsByGuildId, channelId])` (or doing it inside a selector) avoids re-running the loop on unrelated state changes that *do* re-render the component.

### S7 — Test coverage
A small RTL test (`renders heading "# general" when messages array is empty and channel is in store`) would prevent silent regressions if this branch is touched again.

---

## 5. Positive Notes

- ✅ Clean, contained change — only the empty-state branch is touched.
- ✅ Uses CSS variables (`--text-primary`, `--text-secondary`) instead of hardcoded colors. Falls back gracefully.
- ✅ `maxWidth: 480` + left-aligned inner column matches Discord's actual layout proportions; not a copy-paste of CSS.
- ✅ Conditional rendering of `channelTopic` is clean — no empty `<p>` when topic is null.
- ✅ Build, typecheck, and full test suite (374) all pass per author note.
- ✅ Closes #284 with a faithful interpretation of the Discord pattern; product polish is real and worth the diff.

---

## Final Rating

⚠️ **Needs Changes** — fix C1 (drop `Empty` import) and C2 (narrow the store subscription). Once those land, this is a clean ship. Suggestions S1–S7 are improvements but not gating.

— 🌠 Nova
