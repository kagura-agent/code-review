# Review: PR #371 — fix(plugin): inject cove.md as GroupSystemPrompt instead of UntrustedStructuredContext

## Summary

This PR changes Cove channel context injection so `cove.md` is passed as `GroupSystemPrompt` instead of `UntrustedStructuredContext`, aligning Cove with the stated behavior of other OpenClaw group/chat plugins and making channel-level rules actually binding for model turns. The implementation is mechanically small and appears type-compatible with the existing dispatch path, but it materially changes the trust boundary: channel-editable file content is now elevated from reference context into system-level instruction context.

## Critical Issues

- **[Blocking] Trust boundary for editable `cove.md` needs an explicit product/security decision or guardrail before merge.** Channel files appear to be writable by authenticated channel members/bots with channel access, not by a narrower “manage channel/system prompt” permission. With this PR, anyone able to edit `cove.md` can persistently inject high-priority instructions into every agent turn in that channel. That may be the intended feature, but it should be made explicit and protected accordingly. Recommended minimum before shipping: document that `cove.md` is authoritative system-prompt material in the UI/API/docs, and either restrict editing of `cove.md` to trusted roles/admins or add a clear warning/confirmation around edits. If the product decision is that all channel file editors are trusted to author system instructions, this should be recorded in the PR and covered by tests/docs.

## Product Impact

Users should see cove.md rules followed much more reliably; channel conventions, language preferences, and behavior policies will move from “reference metadata the model may ignore” to “binding group instructions.” The downside is that edits to cove.md become much higher impact: a mistaken or malicious edit can change agent behavior for the whole channel until corrected, and cached content may continue for up to the existing cache/error fallback behavior.

## Suggestions

- Add a focused test around `dispatchMessage` verifying that non-empty cove.md populates `extraContext.GroupSystemPrompt` and no longer emits `UntrustedStructuredContext`.
- Add a regression/security test or API-level assertion for the intended edit permissions of `cove.md` specifically, especially if it should differ from ordinary channel files.
- Consider wrapping the injected content with a short provenance boundary, e.g. “Channel cove.md instructions:” plus content. This preserves authority while making source/debugging clearer in assembled prompts and logs.
- Consider logging when cove.md is omitted because it exceeds the plugin’s 8KB injection cap; otherwise users may not understand why a valid 100KB channel file is not influencing the agent.

## Positive Notes

- The code change is minimal and uses the same `GroupSystemPrompt` mechanism already used by other OpenClaw group integrations.
- The existing cache invalidation and 8KB injection cap are good safeguards against stale or oversized context dominating turns.
- The change directly addresses the reported product issue: cove.md rules being treated as optional metadata rather than channel policy.

## Rating

⚠️ Needs Changes
