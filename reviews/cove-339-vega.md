# Code Review - PR #339 (Round 2)
**Reviewer:** Vega
**Status:** ✅ Ready (with minor suggestions)

## 1. Summary
Round 2 addresses all critical bugs from Round 1. The `@mention` logic now uses safe regex with word boundaries, resolving substring collisions. Webhook mentions and notification states are correctly resolved, and the 99+ badge cap and active channel exclusion prevent state bloat/stale badges. The PR is solid and ready to merge, with only minor non-blocking issues remaining.

## 2. Previous Issues Status
### Critical Issues
* ✅ **[Fixed] C1: replaceAll substring collision:** Handled perfectly. You now sort by username length and use `new RegExp(\`@${escaped}(?!\\w)\`, "g")` ensuring word boundaries.
* ✅ **[Fixed] Stella-1: Webhook messages never resolve mentions:** `resolveMentions` is now correctly invoked in `createFromWebhook`.
* ✅ **[Fixed] Stella-2: MESSAGE_UPDATE mention counts for active channel users:** The active channel exclusion `msg.channel_id !== activeChannelId` prevents stale badges when receiving edits in the focused channel.
* ✅ **[Fixed] Vega-1: No onBlur → dangling autocomplete:** `onBlur` with a 150ms timeout gives ample time for click-selection while preventing dangling lists.
* ✅ **[Fixed] Self-mention highlights:** Current user mentioning themselves no longer triggers a highlight.
* ✅ **[Fixed] Badge 99+ cap:** Appropriately implemented in `Sidebar.tsx`.
* ✅ **[Fixed] Nova: mentionMapRef not cleared on channel switch:** Cleaned up safely in `useEffect`.

### Remaining Suggestions (Escalated per protocol)
* ❌ **[Not Fixed] Autocomplete trigger regex too broad (S3):** `/@\w*$/` still triggers inside email addresses like `test@gmail.com`. Escalate to **Minor Issue**. Suggested fix: `/(?:^|\s)@\w*$/`.
* ⚠️ **[Partially Fixed] mentionedMessageIds Set grows indefinitely:** `teardownGatewaySubscriptions` clears the set, but in a long-lived session, the Set still grows linearly with every mentioned message edit. Escalate to **Minor Issue**. (Consider an LRU cache or max size limit).
* ❌ **[Not Fixed] Message.mentions type contract:** The `Message` interface declares `mentions: User[]`, but `resolveMentions()` early-returns when `allIds.size === 0`, leaving it `undefined` for webhooks/new messages. Safe at runtime due to `if (message.mentions)` checks, but breaks the TS contract.
* ❌ **[Not Fixed] MessageItem Map creation:** Still creating a `new Map()` on every render in `MessageItem.tsx`.

## 3. New Issues
* None introduced. The event propagation and key interception fix between React Synthetic events and Native Capture events is well implemented.

## 4. Remaining Suggestions
* **S1: Accessibility:** `MentionAutocomplete` still lacks `aria-` bindings for screen readers.

## 5. Positive Notes
* Excellent use of native event capture (`true` on `addEventListener`) in `MentionAutocomplete.tsx` to stop `Enter` propagation before React sees it.
* Sorting usernames by length before replacement correctly prevents subset matching bugs (e.g. `@alice` vs `@aliceWonderland`).

**Final Verdict:** ✅ Ready. The blocking functionality bugs are solved. The remaining issues are minor and can be addressed in a follow-up optimization PR.