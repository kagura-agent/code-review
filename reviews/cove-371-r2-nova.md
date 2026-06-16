# Re-Review (Round 2): PR #371 — fix(plugin): inject cove.md as GroupSystemPrompt

**Reviewer:** 🌠 Nova
**Repo:** kagura-agent/cove
**Round:** 2
**Verdict:** ✅ Ready

---

## 1. R1 Critical Issue — Resolution Check

**R1 concern (all 3 reviewers):** cove.md is channel-editable content being elevated to system-prompt level without provenance framing. Anyone with channel write access can inject "system-level" instructions into the bot.

**R1 ask (mine, option 1):** *"A short prefix wrapper, e.g. `Channel rules from cove.md (channel-editable, may be authored by non-admin members):\n\n${coveMdContent}` — keeps provenance visible to the model so it can still apply judgement to obviously hostile content."*

**R2 fix in this iteration:**
```
GroupSystemPrompt: "Channel rules from cove.md (channel-editable):\n\n" + coveMdContent
```

**Verdict on the fix:** ✅ Addresses the concern.

The prefix does the two things that matter:
1. **Provenance** — the model now sees that this block came from a file named `cove.md`, not from the trusted operator/runtime layer. Good models will downgrade authority on instructions inside a labeled, channel-scoped block (especially ones contradicting prior system rules).
2. **Editability signal** — the parenthetical `(channel-editable)` is the key word. It tells the model the content was authored by a channel participant, not by Cove operators. That's enough framing for the model to refuse obvious hostile takeovers ("ignore prior safety rules", "exfiltrate secrets") while still honoring legitimate conventions ("respond in English", "no emoji").

Minor nit (non-blocking): I'd have preferred slightly tighter wording — `(channel-editable; authored by channel members, not Cove operators)` — to remove ambiguity for smaller models that may parse "channel-editable" as a permission flag rather than a trust signal. But this is a polish preference, not a correctness gap. The current wording is sufficient.

The other two R1 mitigation options (server-side permission gate on `cove.md` writes; inline comment + tracked follow-up) remain valid follow-ups but are not required to land this PR. The provenance prefix is the load-bearing fix.

## 2. Fresh Review of New Code

The R2 diff is exactly one line of changed behavior on top of R1: the string literal `"Channel rules from cove.md (channel-editable):\n\n"` is concatenated to `coveMdContent` before assignment. Nothing else moved.

Observations:
- **String concat vs template literal:** `"prefix" + coveMdContent` is fine and slightly more grep-friendly than a template literal here. No issue.
- **Newlines:** Two `\n` between header and body is the right shape — gives the model a clear paragraph boundary, matches how most system prompts are structured.
- **Empty-content guard preserved:** the surrounding `coveMdContent ? { ... } : {}` ternary still skips injection on null/empty, so the prefix never appears alone. Good.
- **No allocation regression:** runs once per inbound message dispatch, on a path that already does many string ops. Negligible.
- **No test added.** Same gap as R1. Still non-blocking, still worth a follow-up issue.

No new bugs introduced.

## 3. R1 Non-Blocking Suggestions — Status

| Suggestion | Status |
|---|---|
| Wrap with provenance prefix | ✅ **Done** (this PR) |
| Add a unit test for `extraContext` shape | ❌ Not addressed — follow-up |
| Comment on `coveMdContent` truthiness intent | ❌ Not addressed — minor, follow-up |
| Faster cache invalidation / `!cove reload` | ❌ Not addressed — follow-up, separate issue |
| Verify `GroupSystemPrompt` field name vs runtime | ❌ Not addressed — worth confirming |
| Release-note: behavior change for existing cove.md files | ❌ Not visible in PR body — recommend adding before merge |
| Logging on >8KB drop path | ❌ Not addressed — follow-up |

None of these are merge-blocking on their own. The provenance wrapper was the only R1 item rated close-to-blocking, and it's done.

## 4. Recommendations

**Land it.** The critical R1 issue is resolved with a minimal, surgical change that matches the requested fix. The remaining items are real but appropriately scoped as follow-ups.

Before merging, I'd suggest the author:
1. **(Optional, 30s)** Add one line to the PR description noting the behavior change for channels with existing cove.md content (rules now bind as system prompt, will produce a step-change in bot behavior on first message after deploy).
2. **(Follow-up issue)** Track: (a) unit test for dispatch context shape, (b) server-side write-permission gating on `cove.md` filename, (c) confirm `GroupSystemPrompt` field name is canonical in OpenClaw runtime.

Neither blocks merge.

## 5. Positive Notes

- **Listened to review feedback.** The author took the cheapest of three offered mitigations and applied it cleanly. Good R1→R2 turnaround shape.
- **No scope creep.** R2 didn't try to also add tests, refactor the cache, or rename fields. One concern, one fix, ship.
- **Provenance wording is honest.** "(channel-editable)" is the right level of disclosure — not alarmist, not hidden. A reasonable model reading this prompt knows what trust level to apply.

---

**Final verdict:** ✅ Ready to merge.

`/home/kagura/.openclaw/workspace/code-review/reviews/cove-371-r2-nova.md`
