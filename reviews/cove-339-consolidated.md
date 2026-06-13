# Consolidated Review — PR #339: feat: @mention with autocomplete and highlight

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Overall Verdict: ⚠️ Needs Changes**
**Individual:** Stella ⚠️ · Nova ⚠️ · Vega ⚠️

---

## Consensus Issues (2+ reviewers agree — high confidence)

### 🔴 C1 — `replaceAll` substring replacement corrupts messages (all 3)

`MessageInput.handleSubmit` does `text.replaceAll(@${username}, <@${userId}>)` — a literal substring match with no word boundaries.

**Failure cases:**
- Autocomplete `@alice`, then type `@aliceWonderland` → produces `<@id>Wonderland`
- Autocomplete `@alice`, then type `email@alice.com` → corrupts to `email<@123>.com`
- Manually typed `@alice` after a real autocomplete → silently converted to a ping

**Fix:** Track mention insertions by position/range and apply replacements by index, or use word-boundary-aware regex. The descending-length sort is a good instinct but doesn't solve the fundamental issue.

### 🟡 S1 — Autocomplete lacks a11y bindings (all 3)

No `role="listbox"`, no `aria-activedescendant`, no `aria-expanded`/`aria-controls` on the textarea. Screen-reader users get nothing.

### 🟡 S2 — Badge overflow / no cap (Stella + Nova + Vega)

`{mentionCount}` printed raw — a user away for a while gets a `1234` badge breaking row layout. Use `count > 99 ? "99+" : count`.

### 🟡 S3 — Autocomplete trigger regex too broad (Nova + Vega)

`/@\w*$/` fires even when `@` is preceded by a word char (e.g. `email@gmail`). Pin to start-of-text or whitespace: `/(^|\s)@\w*$/`. Also `\w` excludes Unicode letters — non-ASCII usernames can't be filtered inline.

---

## Per-Reviewer Unique Findings

### 🌟 Stella

- **🔴 Webhook messages never resolve mentions** — `MessagesRepo.createFromWebhook()` returns `mentions: []` and never calls `resolveMentions()`. Agent/webhook messages with `<@userId>` won't render chips, highlight, or update badges.
- **🔴 MESSAGE_UPDATE mention counts for active channel users** — Server increments `mention_count` on edit, but client doesn't auto-ack `MESSAGE_UPDATE` for the active channel. Draft streaming that adds a mention while a user is reading leaves a stale badge.

### 🌠 Nova

- **🟡 Self-mentions render the yellow highlight bar on your own message** — Discord doesn't do this. Guard: `isMentioned = mentions.some(u => u.id === self) && message.author.id !== self`.
- **🟡 `mentionMapRef` not cleared on channel switch** — If `MessageInput` isn't remounted, a mention from channel A could fire in channel B. Add `useEffect(() => { mentionMapRef.current.clear() }, [channelId])`.
- **🟡 `MessageItem` creates `new Map()` every render** — Prop identity churn kills memoization. Wrap with `useMemo`.
- **🟡 `Message.mentions: User[]` type contract broken** — `resolveMentions` early-returns leaving `msg.mentions` undefined when no IDs found, but the type says required. Default-assign `[]`.
- **🟡 No new tests** — Strongly recommend at least server-side test for `resolveMentions` guild-scoping and a parser test for mixed formatting.

### 💫 Vega

- **🔴 No `onBlur` handler → dangling autocomplete steals keys globally** — If user types `@` then clicks away, the autocomplete stays open and the capturing `window` keydown listener silently steals Enter/Tab/Arrow keys app-wide. Fix: `onBlur={() => setShowMention(false)}`.
- **🟡 `mentionedMessageIds` Set grows indefinitely** — No eviction for long-lived sessions. Cap or scope-by-channel.

---

## What's Done Well (consensus)

- ✅ SQL is parameterized everywhere — no injection surface
- ✅ Guild-scoped JOIN closes the #337 info-leak cleanly
- ✅ `<@(\d+)>` is digit-bounded → no ReDoS risk
- ✅ Atomic `INSERT … ON CONFLICT … mention_count = mention_count + 1` handles concurrent writes correctly
- ✅ React rendering auto-escapes usernames — no XSS
- ✅ `stopImmediatePropagation` on Enter + `onHasResults` gate correctly prevents "Enter sent message while picking" bug from reverted #337
- ✅ Pre-fetching members on READY avoids racing the first `@` trigger
- ✅ Migration is small, additive, and idempotent

---

## Blocking Summary

| # | Issue | Severity |
|---|-------|----------|
| C1 | `replaceAll` substring corruption | 🔴 Critical |
| Stella-1 | Webhook messages skip mention resolution | 🔴 Critical |
| Stella-2 | MESSAGE_UPDATE badge accuracy for active readers | 🟡 Medium |
| Vega-1 | Dangling autocomplete steals global keys | 🔴 Critical |

**Recommend fixing C1, Stella-1, and Vega-1 before merge.** The rest are non-blocking improvements.
