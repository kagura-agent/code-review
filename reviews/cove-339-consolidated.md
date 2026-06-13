# Consolidated Review — PR #339 Round 2 (Re-review)

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Overall Verdict: ✅ Ready** (2-1 split; Stella ⚠️, Nova ✅, Vega ✅)

---

## Round 1 Critical Issues — All Fixed ✅

| R1 Issue | Status | Consensus |
|----------|--------|-----------|
| C1: `replaceAll` substring corruption | ✅ Fixed | All 3 confirm — regex + `(?!\w)` + length sort + channel-switch clear |
| Stella-1: Webhook messages skip mention resolution | ✅ Fixed | All 3 confirm — `createFromWebhook` now calls `resolveMentions()` + increments `mention_count` |
| Stella-2: MESSAGE_UPDATE active-channel badge | ✅ Fixed (2/3) | Nova & Vega: active-channel guard `msg.channel_id !== activeChannelId` + `mentionedMessageIds` dedupe added. Stella disagrees — see §Disagreement below |
| Vega-1: No onBlur → dangling autocomplete | ✅ Fixed | All 3 confirm — 150ms delayed close |
| S2: Badge 99+ cap | ✅ Fixed | All 3 confirm |
| Self-mention highlight | ✅ Fixed | All 3 confirm — `message.author.id !== currentUserId` guard |
| mentionMapRef channel switch | ✅ Fixed | All 3 confirm — `useEffect([channelId])` |

---

## Disagreement: Stella's Remaining Blockers

### Stella N1 — Non-numeric user IDs cannot be mentioned

Stella notes `parseMentionIds()` only matches `<@(\d+)>`, so non-numeric bot/custom IDs would fail. **Nova and Vega did not flag this.** This is likely valid only if Cove still creates non-snowflake IDs — if the project has fully moved to numeric snowflake IDs, this is a non-issue. **Recommend: verify whether non-numeric user IDs still exist in practice.** If yes, widen the regex; if no, this is informational.

### Stella N2 — MESSAGE_UPDATE active-channel badge (escalation from R1)

Stella says this is still broken. However, Nova specifically confirmed the fix: `msg.channel_id !== activeChannelId` guard on the client + server-side set-diff (`existingMentionIds`) prevents double-counting. Vega also confirms fixed. **2-1 in favor of fixed.** The active-channel guard appears to correctly prevent badge increment for messages in the currently viewed channel.

---

## Remaining Non-Blocking Issues (consensus or escalated)

| Issue | Flagged By | Priority |
|-------|-----------|----------|
| a11y: autocomplete lacks ARIA bindings | All 3 (escalated from R1) | Follow-up issue |
| Trigger regex `/@\w*$/` fires inside emails | Nova + Vega (escalated) | Follow-up |
| No new tests for mentions | Nova + Stella (escalated) | Follow-up |
| `MessageItem` new Map() every render | Nova + Vega | Follow-up (useMemo) |
| `mentionedMessageIds` Set unbounded | Nova + Vega | Follow-up (LRU cap) |
| Left-side word boundary missing on `@` regex | Nova | Low — `bob@alice` edge case |
| Stale mentionMapRef after deleting mention text | Nova | Low |

---

## New Observations (Round 2 only)

- Nova: `resolveMentions` assumes single-channel batch (`channelIds[0]`) — fragile for future callers, consider asserting `channelIds.size === 1`
- Nova: "Unknown User" fallback in ChatMarkdown could flash during transitional renders (unlikely in practice)
- Nova: Client/server mention_count can briefly diverge on reconnect; READY resync papers over it

---

## Recommendation

**✅ Merge.** All R1 critical issues are resolved. The remaining items are quality-of-life improvements appropriate for a follow-up `mention-followups` tracking issue. Recommend filing that issue before merge to capture: a11y, trigger regex, tests, useMemo, Set cap.
