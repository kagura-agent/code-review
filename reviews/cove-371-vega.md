# Review for PR #371: fix(plugin): inject cove.md as GroupSystemPrompt instead of UntrustedStructuredContext

## Summary
This PR modifies `packages/plugin/src/dispatch.ts` to change how the channel's `cove.md` content is passed to the LLM model. By switching the payload field from `UntrustedStructuredContext` to `GroupSystemPrompt`, the `cove.md` contents are now treated as authoritative, system-level instructions rather than optional context data.

## Critical Issues
**Security/Prompt Injection Risk**: Elevating `cove.md` to `GroupSystemPrompt` creates a direct, system-level prompt injection vector. Since `cove.md` is channel-editable content, any user with permission to edit this file can now override core agent behaviors, rules, and safeguards for that channel. Before merging, it must be ensured that the platform enforces strict Access Control Lists (ACL) on who can edit `cove.md` (e.g., only channel owners/admins), or the `coveMdContent` needs to be safely wrapped/sandboxed within the system prompt generation layer to prevent overriding absolute system guardrails.

## Product Impact
This change will significantly improve the user experience for channel configuration. Models will now consistently follow the rules, personas, and formatting constraints defined in `cove.md`. However, users will also have the power to fundamentally alter the bot's behavior in their channels, meaning the bot might behave unpredictably or bypass standard conversation norms if the `cove.md` file is poorly written or maliciously modified.

## Suggestions
- **Permission Validation**: Verify that the Cove platform properly restricts write access to `cove.md` to trusted channel administrators.
- **Content Bounding/Validation**: Consider adding a max-length validation to `coveMdContent` to prevent users from consuming the entire token budget with a massive `cove.md` file.
- **Prompt Isolation**: If the OpenClaw API allows it, ensure that the base agent `SOUL.md` / `AGENTS.md` instructions take precedence over the `GroupSystemPrompt` to maintain baseline safety rules.

## Positive Notes
The change is concise, removes unnecessary boilerplate, and standardizes the Cove plugin to align with the core OpenClaw system prompt conventions used across other platforms like Discord.

## Rating
⚠️ Needs Changes