# Review: kagura-agent/cove PR #287 — feat: add resolver.resolveTargets to Cove plugin

## Summary

This PR adds the expected `resolver.resolveTargets` surface for Cove group targets and follows the shared OpenClaw target resolver helper pattern. The channel lookup logic itself is straightforward and generally aligned with the existing REST client API, but there is a correctness bug in the configuration handling: the resolver calls the existing `resolveAccount()` helper before invoking `resolveTargetsWithOptionalToken()`, and `resolveAccount()` throws when the bot token or agent ID is missing. That means the new resolver does not actually provide the advertised graceful unresolved results for missing tokens, and it may fail in target-resolution contexts that should not need an agent ID. I would address that before merge and add tests for the resolver paths.

## Critical Issues

1. **Missing token handling is unreachable**

   `resolveTargets` begins with:

   ```ts
   const account = resolveAccount(cfg, accountId);
   ```

   But `resolveAccount()` throws if no Cove token is configured:

   ```ts
   if (!token) {
     throw new Error("cove: bot token is required ...");
   }
   ```

   As a result, this code never reaches `resolveTargetsWithOptionalToken({ missingTokenNote: "missing Cove bot token", ... })` when the token is missing. The PR body says missing token is handled gracefully, but the runtime behavior will be a thrown exception instead of per-input unresolved results.

   **Recommendation:** split account resolution for resolver use from strict runtime account validation. For example, introduce a lightweight resolver config reader that returns `{ token, baseUrl, guildId }` without throwing, then let `resolveTargetsWithOptionalToken()` produce unresolved results when `token` is absent. Keep the strict `resolveAccount()` behavior for gateway/outbound startup if those paths require it.

2. **Target resolution unnecessarily requires `agentId`**

   `resolveAccount()` also throws when `agentId` is missing. Resolving a channel name/ID via Cove REST does not use `agentId`, so this can make `openclaw message send --channel cove --target ...` fail during target resolution even when `baseUrl`, `token`, and `guildId` are sufficient to resolve the channel.

   **Recommendation:** the resolver should only validate fields it needs for resolution. If `agentId` is required later for session routing or gateway dispatch, validate it there rather than in the target resolver.

## Product Impact

The intended user-facing improvement is important: users should be able to send to Cove channels by target through OpenClaw. However, on partially configured installations, target resolution may currently fail with a thrown configuration error instead of returning helpful unresolved entries like `missing Cove bot token` or `guildId not configured`. That creates a rough CLI experience and can make setup/debugging misleading, especially because the new helper is explicitly designed to return structured unresolved target results.

## Suggestions

- Add focused tests for `resolver.resolveTargets` covering:
  - missing token returns unresolved results with `missing Cove bot token`;
  - missing `guildId` returns unresolved results with `guildId not configured`;
  - channel ID match resolves;
  - case-insensitive channel name match resolves;
  - unknown channel returns `channel not found`;
  - `kind: "user"` returns `user target resolution not supported`.
- Consider normalizing common user input forms such as `#channel-name` if OpenClaw users are likely to enter channel-style names. Not required for the MVP if the intended contract is exact ID or bare name only, but documenting/handling it would reduce friction.
- Consider whether duplicate channel names should produce an ambiguity note rather than silently selecting the first match. If Cove channel names are globally unique per guild, this is fine; otherwise it may send messages to an unexpected channel.
- The inline comment `// User target resolution — not supported yet` is useful, but a small test for that branch would prevent it from regressing into accidental success/failure behavior.

## Positive Notes

- The implementation reuses `resolveTargetsWithOptionalToken`, which is the right shared abstraction for token-gated channel target resolution.
- The group resolver performs one `getChannels(guildId)` call per batch and maps all inputs locally, avoiding an obvious N+1 request pattern.
- Matching by both channel ID and case-insensitive channel name is a good MVP for CLI ergonomics.
- Unsupported user resolution is explicit and returns a clear note rather than pretending to resolve users.

Rate: ⚠️ Needs Changes
