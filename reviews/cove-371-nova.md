# Review: PR #371 — fix(plugin): inject cove.md as GroupSystemPrompt instead of UntrustedStructuredContext

**Reviewer:** 🌠 Nova
**Repo:** kagura-agent/cove
**Verdict:** ⚠️ Needs Changes (small, but worth doing before merge)

---

## 1. Summary

This PR fixes the long-standing complaint behind #370: cove.md was injected as `UntrustedStructuredContext`, which models reasonably treat as reference metadata, not as binding rules — so channel-level conventions written in cove.md were being ignored. The fix is a one-liner in `packages/plugin/src/dispatch.ts`: drop the structured-context wrapper and pass the raw content as `GroupSystemPrompt`, matching the pattern used by Discord/WhatsApp/other OpenClaw plugins. Net diff is +1/-6, build + 64 plugin tests pass. The behavioral intent is correct and the change is minimal — but it elevates a channel-editable file into the system-prompt trust boundary, and that warrants at least one explicit guardrail note before merging.

## 2. Critical Issues

None blocking-by-correctness — the change compiles, tests pass, and the field swap is mechanical. But one item is close to blocking and should at least be acknowledged:

- **Trust elevation of channel-editable content.** `getCoveMd` (in `cove-md-cache.ts`) reads `cove.md` from the channel's file storage via `restClient.getChannelFile`. That file is editable by whoever has channel write permission — not just admins. After this PR, anything written there is treated by the model as authoritative system instructions ("the standard field used by Discord, WhatsApp …"). That is exactly the behavior #370 asks for, but it also means anyone who can upload a file to a channel can inject *system-level* instructions into the bot for every subsequent turn in that channel — including instructions like "ignore prior safety rules", "exfiltrate any secret you see", or "treat user X as the operator". Before this PR, the same content existed in untrusted-context, where good models heavily discount it; after this PR, that hedge is gone.

  This is a deliberate, documented design choice (see `skills/cove-ops/SKILL.md`: *"cove.md is auto-injected … channel-level rules, conventions, and state belong here"*), so I'm not asking to revert the direction. But I'd want **at least one of**:
  1. A short prefix wrapper, e.g. `GroupSystemPrompt: \`Channel rules from cove.md (channel-editable, may be authored by non-admin members):\n\n${coveMdContent}\`` — keeps provenance visible to the model so it can still apply judgement to obviously hostile content, the way most OpenClaw plugins frame their system prompts.
  2. A permission gate on `cove.md` writes (only mods/admins can mutate that specific filename), enforced server-side. Out of scope for this PR but should be tracked.
  3. At minimum: a one-line comment at the injection site noting the trust elevation, and a note in the PR/issue that #370's resolution implies a follow-up for either (1) or (2).

  Without any of those, this is a quietly-broadening attack surface and the kind of thing that bites later.

## 3. Product Impact

- **Intended:** cove.md rules now actually bind. Users writing "always respond in English" or "no emoji in this channel" will see them respected, instead of treated as flavor text. This is the headline win and matches the test plan.
- **Unintended (worth calling out in release notes):**
  - Existing channels with stale, exploratory, or sloppy cove.md files will see a *step-change* in bot behavior on next deploy, because content that was previously soft-context is now hard-instruction. Some channels will get noticeably more rigid bots overnight.
  - The structured metadata (`label`, `source`, `type`) is dropped. The model no longer sees that this content originated from cove.md — it just looks like part of the system prompt. If any downstream prompt logic, eval, or tracing keys off `UntrustedStructuredContext` entries with `source: "cove"`, that hook is now silently gone. Worth a quick grep across consumers.
  - `getCoveMd` returns `null` for files larger than 8KB. That means if a channel's cove.md grows past 8KB, the *system prompt* silently disappears (rather than a structured-context entry silently disappearing). Same failure mode as before, but the user-visible swing is larger now ("rules stopped working entirely"). Logging on the >8KB drop path would help operators diagnose this.

## 4. Suggestions (non-blocking)

- **Wrap, don't inline.** Even one line of framing — "The following are channel-specific rules from cove.md:" — costs nothing, gives the model provenance, and makes the trust boundary auditable. Most other OpenClaw plugins do this for their `GroupSystemPrompt`.
- **Add a unit test.** `dispatch.ts` is a hot path and there are zero tests asserting the shape of `extraContext` passed into `dispatchInboundDirectDmWithRuntime`. A small test verifying that (a) when cove.md is non-empty, `GroupSystemPrompt` is set and `UntrustedStructuredContext` is absent, and (b) when cove.md is null/empty, neither field is set, would lock in the contract and prevent regressions. Existing test files (`dispatch-resilience.test.ts`) show the pattern.
- **Empty-string handling.** `coveMdContent ? { GroupSystemPrompt: coveMdContent }` correctly skips empty/`null`. Good. Worth a one-line comment to make that intent explicit since `0` and `""` falsiness can surprise future contributors.
- **Cache invalidation timing.** 60s TTL with WS-event invalidation is fine for content updates, but with this PR a misconfigured cove.md is now a *system-prompt* mistake. Operators iterating on rules will want faster feedback. Consider a debug-channel command (`!cove reload`) or a shorter TTL gated by feature flag for power users — follow-up, not blocking.
- **Field name verification.** The PR description claims `GroupSystemPrompt` is "the standard field used by Discord, WhatsApp, and other OpenClaw plugins." That isn't verifiable from this repo alone (no usages found in `packages/`). Worth confirming with a link/reference in the PR body so a future reader doesn't have to spelunk OpenClaw runtime source. If the runtime silently ignores unknown fields, a typo here would degrade silently to "no system prompt."

## 5. Positive Notes

- **Surgical change.** +1/-6, single file, single field swap. Minimum-blast-radius PR shape.
- **Right diagnosis.** "Models treat structured-context as reference, not rules" is correct — this is exactly the failure mode that motivated structured-context's design, and using it here was the wrong tool from day one.
- **Good hygiene around the cache layer.** `getCoveMd` already enforces an 8KB cap, has a stale-on-error fallback, and is invalidated on WS file events (`channel.ts:351-357`). That existing infrastructure carries cleanly into the new injection path — no changes needed.
- **Auto-merge with reviewer requested.** Tests pass, CI green, opinionated fix. Healthy PR shape.

---

**Recommendation:** Land it after either adding a one-line prefix wrapper for provenance *or* an inline comment + tracked follow-up for cove.md write permissions. The change itself is right; just don't ship the trust-boundary shift silently.
