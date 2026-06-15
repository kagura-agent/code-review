# Vega PR Re-Review: #357 (Round 2)

## 1. R1 Issues Status

### Blocking Issues
- ✅ **Thread-member routes missing requireBotChannelPermission**: Fixed. `parent_id` is now checked for permissions in all thread-member routes.
- ✅ **No tests**: Fixed. `packages/server/src/__tests__/threads.test.ts` added with comprehensive coverage.
- ✅ **auto_archive_duration unvalidated**: Fixed. Values are strictly validated against allowed durations.
- ✅ **Thread indicator state sync**: Fixed. Frontend store is now properly updated via `THREAD_CREATE` subscription.

### Non-Blocking Suggestions (Now Escalated per Protocol)
- ❌ **Nested thread prevention**: Not Fixed. `POST /channels/:channelId/threads` still does not check if `channelId` is already a thread (`channel.type === 11`).
- ✅ **timestamp type mismatch**: Fixed. Now using `new Date().toISOString()`.
- ❌ **N+1 thread fetch**: Not Fixed. `setupGatewaySubscriptions` loops over every channel and triggers an API fetch, which will spam the backend.
- ✅ **archive/lock fallthrough**: Fixed. The `PATCH` route logic has been refactored correctly.
- ❌ **name truncation**: Not Fixed. `content.slice(0, 40)` still risks splitting surrogate pairs/emojis.
- ✅ **unused props**: Fixed.
- ❌ **drag handler leak**: Not Fixed. Drag listeners added to `document` lack `useEffect` cleanup.
- ❌ **moderator removal route**: Not Fixed. Missing `DELETE /channels/:threadId/thread-members/:userId`.
- ❌ **json_extract perf**: Not Fixed. No index or generated column added for `json_extract(thread_metadata, '$.archived')`.

## 2. New & Escalated Issues

1. **[ESCALATED - SEVERITY: HIGH] N+1 Request Spam on Connection**
   `setupGatewaySubscriptions` blindly iterates over `guild.channels` and calls `api.fetchActiveThreads(ch.id)` for each non-thread channel. A user in a guild with 100 channels will fire 100 parallel HTTP requests on boot. This must be batched or handled via the gateway payload itself.

2. **[ESCALATED - SEVERITY: HIGH] Infinite Thread Nesting**
   Thread routes lack `if (channel.type === 11)` prevention, allowing threads to be created inside threads indefinitely.

3. **[ESCALATED - SEVERITY: MEDIUM] Drag Event Listener Leak**
   In `App.tsx`, `handleResizeMouseDown` binds to `document.addEventListener`. If the panel unmounts while dragging (e.g. user hits Escape, or route changes), those listeners are orphaned, causing state mutations on unmounted components and memory leaks.

4. **[ESCALATED - SEVERITY: LOW] Emoji Corruption on Thread Auto-Naming**
   `content.slice(0, 40)` breaks multibyte unicode characters. Use `Array.from(content).slice(0, 40).join('')` or similar.

5. **[ESCALATED - SEVERITY: LOW] Missing Moderator Removal Route**
   We have `PUT /channels/:threadId/thread-members/:userId` to add a member, but we lack the equivalent `DELETE` route for moderators to kick members out.

## 3. Summary + Verdict

**Verdict**: ❌ Major Issues

While the core authorization and test coverage gaps from Round 1 were addressed nicely, the unaddressed performance issue (N+1 fetches on socket boot) will take down the backend on production loads. Furthermore, allowing infinite thread nesting fundamentally breaks channel hierarchy. These escalated issues must be fixed before merging.
