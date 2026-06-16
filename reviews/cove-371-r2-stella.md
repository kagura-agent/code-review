# PR #371 Round 2 Review — Stella

**Verdict: ✅ Ready**

## Summary

This PR now injects `cove.md` through `GroupSystemPrompt` with an explicit provenance/trust-boundary header: `Channel rules from cove.md (channel-editable):`. The Round 1 blocker was specifically that channel-editable content was being elevated to system prompt level without any framing; the new prefix makes the source and editability visible inside the same system-prompt text, so I consider that concern addressed for the stated product goal of making `cove.md` authoritative channel rules.

## Critical Issues

None.

## Round 1 Follow-up Status

- **Provenance framing for channel-editable content:** Addressed at `packages/plugin/src/dispatch.ts:288-289`. The model receives the rules with a clear header identifying `cove.md` and noting that it is channel-editable.
- **Unit test suggestion:** Not addressed. There does not appear to be a test covering the dispatch `extraContext.GroupSystemPrompt` shape or the provenance prefix. This is non-blocking for this small one-line behavior change, but I still recommend adding it because future regressions here would be easy to miss.
- **8KB handling/logging suggestion:** Size limiting already exists in `packages/plugin/src/cove-md-cache.ts:35-37`; content over 8000 UTF-8 bytes is dropped. I did not see new logging when content is skipped for size, so the logging part remains a non-blocking improvement.
- **Field name verification:** Looks correct. `GroupSystemPrompt` is present in OpenClaw templating/session context types and is consumed as an extra system prompt by the reply pipeline. The spelling/casing used in this PR matches the runtime field.

## Product Impact

The change should make channel `cove.md` rules materially more effective than `UntrustedStructuredContext`, which fits the linked issue. The security/product tradeoff is intentional: anyone who can edit `cove.md` can influence channel-level instructions. The added header does not sandbox those rules, but it does preserve provenance at the trust boundary and avoids presenting them as opaque platform configuration.

## Suggestions

1. Add a focused plugin test that mocks a `cove.md` file and asserts dispatch passes `extraContext.GroupSystemPrompt` with the provenance prefix and content.
2. Consider logging when `cove.md` is skipped because it exceeds the 8KB limit, so admins can distinguish “no rules” from “rules ignored because too large.”
3. Update the PR body’s diff snippet if desired; it still shows `GroupSystemPrompt: coveMdContent`, while the actual implementation now includes the provenance prefix.

## Positive Notes

- The fix is minimal and directly targets the Round 1 concern without broadening scope.
- The prefix is concise and explicit about the important trust property: channel editability.
- Existing cache size limiting keeps prompt growth bounded.
