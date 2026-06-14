# 🌠 Nova Code Review — PR #356

**Repo:** kagura-agent/cove
**Title:** feat: WS events for channel files + cove.md plugin cache (closes #354, closes #353)
**Stats:** 10 files, +146/-13
**Verdict:** ⚠️ **Needs Changes** (small, non-blocking-ish — mostly a missing-tests + a couple of low-severity correctness fixes)

---

## 1. Summary

A clean, small, well-scoped two-part change. Part 1 plumbs three new WS events (`CHANNEL_FILE_CREATE/UPDATE/DELETE`) through the existing dispatcher → guild+channel-filter broadcast → client subscription path, with the client refreshing the files sidebar and re-fetching content when the open file changes. Part 2 adds a 60s in-memory TTL cache for `cove.md` in the plugin and wires the new WS events to invalidate the cache on changes. The diff is consistent with existing patterns (mirrors `messageCreate/Update/Delete`, mirrors `reactionAdd/Remove`), `tsc` is clean, and all 275 existing tests pass. The main gap is **no new tests** for either the dispatcher's three new methods or the new `cove-md-cache.ts` module, plus a few small correctness/perf points around the create-vs-update race, unbounded cache growth, and no in-flight dedup.

---

## 2. Critical Issues

None that block merge. The closest to blocking is **#1 (no new tests)** — for a feature that crosses three packages and introduces a new shared event surface, the test coverage gap is real.

---

## 3. Product Impact

Net positive, user-facing:

- **Realtime sidebar updates** — when a bot (or another client) writes `cove.md` or any channel file, every connected client in the guild that can see the channel will refresh their file list within ~one RTT instead of needing a manual reload. Big UX win for multi-agent / multi-user workflows.
- **Open file auto-refresh** — `CHANNEL_FILE_UPDATE` re-fetches the *currently selected* file content only, which is the right balance between freshness and bandwidth.
- **Faster bot dispatch** — `cove.md` is now cached for 60s instead of being re-fetched on every inbound message. For a chatty channel this removes one round-trip from every dispatch path. Stale-on-error fallback means transient server hiccups won't blank out `cove.md` context.
- **Cache coherence across cove.md writers** — when a bot (or the user) edits `cove.md`, the WS event invalidates the cache immediately, so the next dispatch sees fresh content well inside the 60s TTL.

Behavioral subtleties users may notice:
- A no-op PUT (same content) still emits `CHANNEL_FILE_UPDATE` and triggers a refresh + sidebar redraw for every client. Mostly harmless, but a tight loop of identical writes will fan out.
- DM channels (guild_id null) silently drop file events — `resolveGuildForChannel` returns null. Matches the existing `messageCreate` behavior and the existing `TODO(#111)` comment, so this is consistent.

---

## 4. Suggestions (non-blocking)

### a. Create-vs-update race in PUT
```ts
const existing = repos.channelFiles.get(channelId, filename);
const file = repos.channelFiles.upsert(...);
// dispatch CREATE or UPDATE based on `existing`
```
Two concurrent PUTs for the same brand-new filename can both observe `existing === null` and both emit `CHANNEL_FILE_CREATE`. Subscribers double-refresh — mostly cosmetic, but the second event is semantically wrong (it should be an update). If `repos.channelFiles.upsert` can return a flag like `{ file, created: boolean }`, prefer using that instead of a separate read. Low priority.

### b. `cove-md-cache.ts` — unbounded `Map` growth
The module-level `Map<channelId, CacheEntry>` is never pruned; stale entries past TTL remain until the next access for that channel. A bot living in many channels accumulates entries forever. Options:
- Add a tiny LRU cap (e.g., 256 channels) — `lru-cache` is already in the workspace ecosystem.
- Or, on read, opportunistically delete the entry if `Date.now() - fetchedAt > TTL_MS * 10` and no hit. Lightweight.

### c. No in-flight dedup
If 5 messages arrive for the same channel within the same millisecond after TTL expiry, all 5 dispatch paths fire `restClient.getChannelFile` in parallel. A `Map<channelId, Promise<string | null>>` of in-flight requests would coalesce — easy win for cold-cache bursts.

### d. Filename-match for invalidation is exact
```ts
if (payload.filename === "cove.md") invalidateCoveMd(payload.channel_id);
```
The route's `FILENAME_RE` is case-sensitive, so `Cove.md`/`COVE.MD` are *different* files. Probably fine since the producer always writes lowercase `cove.md`, but worth a one-line constant + comment to make the contract explicit (e.g., `const COVE_MD_FILENAME = "cove.md"`).

### e. Cache shutdown / multi-account isolation
`cache` is module-scoped. If two `coveChannelPlugin` instances ever run in the same Node process (different accounts), they share the cache keyed only by `channelId`. Across distinct Cove servers a channel ID collision is unlikely (snowflakes), but the cleanest fix is to scope the cache per account/REST client — e.g., a `WeakMap<CoveRestClient, Map<channelId, CacheEntry>>` or stash the cache on the plugin context. Optional.

### f. Event payload `as` casts in `gateway-client.ts`
```ts
this.emit("channelFileCreate", payload.d as { ... });
```
No runtime validation of the payload shape. Matches existing patterns in the same file (typing/reaction events do the same), so it's consistent — but if you ever add a tiny `validateChannelFilePayload(d)` helper, sprinkling it on `case "CHANNEL_FILE_*"` would catch a malformed server early without throwing inside subscribers.

### g. Tests — please add at minimum:
1. `packages/server/src/__tests__/channel-files.test.ts`: extend the existing PUT/DELETE tests to assert the dispatcher receives `channelFileCreate`/`channelFileUpdate`/`channelFileDelete` calls. The `GatewayDispatcher` is already imported in that file — perfect spot.
2. `packages/server/src/__tests__/gateway.test.ts` (or a new one): assert `CHANNEL_FILE_*` events are filtered out for bots without `VIEW_CHANNEL` (you already test this for messages — copy the pattern).
3. `packages/plugin/src/cove-md-cache.test.ts` (new): TTL hit, TTL miss, stale-on-error, `invalidateCoveMd`, size-limit (>8000B → null).
4. `packages/client/src/lib/gateway-subscriptions.test.ts`: assert `CHANNEL_FILE_*` subscribers only fetch when `filesOpen === true`.

### h. Minor: `getCoveMd` log signature
```ts
log?: { warn?: (...a: any[]) => void }
```
Inline shape is fine, but if the project already has a `Logger` interface, prefer that for consistency. Minor.

### i. Wasted broadcasts on no-op PUTs
Consider short-circuiting in the route if `existing?.content === body.content && existing?.content_type === body.content_type` — skip both the `upsert` write *and* the dispatch. Mostly a polish issue; matters more if any client ever polls-and-rewrites.

---

## 5. Positive Notes

- 🎯 **Perfect pattern mirroring.** The three new dispatcher methods (`channelFileCreate/Update/Delete`) are line-for-line consistent with `messageCreate/Update/Delete`, which makes the diff trivial to review and keeps the permission-filter path (`broadcastToGuildWithChannelFilter`) unified — no new permission code paths, no new ways to leak a private channel.
- 🛡️ **Permission filtering correctly reused.** Channel-level VIEW_CHANNEL filtering for bot sessions is automatic via `broadcastToGuildWithChannelFilter`; no bespoke ACL logic was reinvented for files.
- 🧠 **Stale-on-error in the cache is the right call.** A flaky network shouldn't blank out the bot's channel context mid-conversation. Subtle but very thoughtful.
- 📐 **Clean cache API surface** — `getCoveMd`, `invalidateCoveMd`, `invalidateAllCoveMd`. Three functions, one responsibility each.
- ✂️ **Dispatch.ts is leaner.** 11 lines of inline fetch+try/catch replaced by a 1-line cached call. The fetch policy (timeout, size cap, error swallowing) is centralized in one place where it belongs.
- 🔁 **End-to-end cache coherence.** WS event → plugin invalidate → next dispatch is fresh. This closes the obvious "stale cove.md after an edit" footgun before it could ever ship.
- 🪶 **Tiny dispatcher payload.** `CHANNEL_FILE_DELETE` is just `{channel_id, guild_id, filename}` — no over-fetching, no leaking file content or size on delete.
- ✅ **Backward compatible.** `dispatcher` is `dispatcher?` in `channelFilesRoutes` — tests and any other caller without WS still compile and work.
- 🔌 **Client `filesOpen` guard** avoids gratuitous network refreshes for users who don't have the sidebar open. Nice touch.

---

**Bottom line:** Ship after tests are added (or land it now and fast-follow with the test PR if the merge window matters). The runtime behavior is correct and consistent; the gaps are testability and a couple of small polish items around the cache.

— 🌠 Nova
