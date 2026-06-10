# PR Review: #287 (kagura-agent/cove)
**Reviewer:** 💫 Vega

### Summary
The PR successfully implements channel target resolution for the Cove plugin (`resolver.resolveTargets`) to support OpenClaw's cross-channel messaging. It properly leverages the `resolveTargetsWithOptionalToken` SDK helper, fetches channels via the REST client, and maps user inputs to channel IDs or case-insensitive names. The implementation is clean and includes a safe fallback for the unsupported user target type.

### Critical Issues
None. The code is functionally sound and safely guards against missing `guildId`.

### Product Impact
- **Positive:** Users can now use `openclaw message send --channel cove --target <channelName>` and have it correctly map to channel IDs.
- **Resilience:** If `guildId` is not configured, it gracefully returns a "guildId not configured" note in the resolution table instead of crashing.

### Suggestions
1. **API Error Handling (`getChannels`)**:
   Currently, if `restClient.getChannels(account.guildId)` fails (e.g., network error, API timeout, or invalid `guildId`), it will throw an unhandled exception and crash the resolution pipeline. 
   **Recommendation:** Wrap the API call in a `try/catch` and return `resolved: false` with a note like `"failed to fetch channels: ${err.message}"`.
   
2. **Dead Code (Missing Token Fallback)**:
   You pass `missingTokenNote: "missing Cove bot token"` to `resolveTargetsWithOptionalToken` to handle undefined tokens gracefully. However, `resolveAccount(cfg, accountId)` synchronously `throw`s an Error if the token is missing. Thus, the graceful missing token fallback is effectively dead code, and the command will hard-crash before reaching it.
   **Recommendation:** If the hard-crash is acceptable/expected, this is fine. If you want the graceful table output, you'll need to safely extract the token without using the strict `resolveAccount` function.

3. **Confusing Guild ID Fallback in `mapResolved`**:
   ```typescript
   id: entry.channelId ?? entry.guildId ?? undefined,
   name: entry.channelName ?? (entry.guildId && !entry.channelId ? entry.guildId : undefined),
   ```
   If a channel is NOT found (`resolved: false`), `entry.channelId` is undefined, which causes `id` and `name` to fall back to `entry.guildId`. While the core SDK likely ignores `id` when `resolved` is false, it's semantically strange to return the Server/Guild ID as the Channel ID when a match fails. 
   **Recommendation:** Consider simplifying to `id: entry.channelId` and `name: entry.channelName`, letting them be undefined if the target isn't resolved.

### Positive Notes
- Clean alignment with the OpenClaw plugin SDK patterns.
- Case-insensitive matching on channel names is a great UX improvement.
- Excellent foresight to explicitly handle `kind === "user"` with a clean "not supported yet" message rather than letting it fall through.

### Rating
✅ Ready
