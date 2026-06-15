# 🌠 Nova — Final Review (R5) — PR #357 `feat: Discord-style message threads`

Repo: `kagura-agent/cove` · PR #357 · Round 5 (Final)
Scope: focus on R5 additions; quick regression scan of R1–R4 surface.

---

## 1. New Changes Review (R5)

### 1.1 Discord schema alignment — `shared/src/types.ts`, repos, ws/dispatcher

✅ `ThreadMetadata.invitable?` added; `ThreadMember.flags: number` added (with `id?` / `user_id?` matching Discord's "partial" thread member shape). Both `repos/channels.ts` and `repos/threads.ts` `toChannel()` correctly map the new columns.

✅ `Message.thread?: Channel | null` — messages list and single-message GET both enrich via `repos.threads.getThreadForMessage(msg.id)`.

⚠️ **N+1 query in message list enrichment** (`routes/messages.ts:list`)
```ts
for (const msg of messages) {
  const threadInfo = repos.threads.getThreadForMessage(msg.id);  // 1 query per message
  ...
}
```
`getThreadForMessage` does up to two `SELECT` per call (id-equals-message lookup, then `message_id` column fallback). For a 50-message page that's 50–100 round-trips against SQLite. Personal project / SQLite → not a blocker, but worth a `WHERE id IN (...) OR message_id IN (...)` batched lookup as a follow-up.

⚠️ **Duplicate `toChannel()` / `ChannelRow` definitions** in `repos/channels.ts` and `repos/threads.ts`. They are identical today; if one drifts, list endpoints (using `repos/threads.ts:toChannel`) and `channelsRepo.getById` will produce different `Channel` shapes. Not a bug now — minor refactor opportunity (extract to a shared row mapper).

### 1.2 Migration v16 — `v16-thread-member-flags.ts`

✅ Idempotent: PRAGMAs the table, only ALTERs if `flags` is missing. Safe for envs that were ever on v15 (some staging DBs may have been created before v16 was authored).
✅ Fresh DBs get `flags` directly via `schema.ts`'s `CREATE TABLE thread_members` — no double-add.
✅ `migration.test.ts` updated to expect `user_version = 16`.

### 1.3 Thread delete / archive UI — `ThreadPanel.tsx`

✅ Header `⋯` menu, outside-click + Escape close handlers cleanly wired with proper `removeEventListener` in cleanup.
✅ 2-step delete (`confirmDelete` state), reset on menu close and dismissal.
✅ Optimistic local `removeThread(...)` + server PATCH/DELETE; server-broadcast `THREAD_UPDATE`/`THREAD_DELETE` later re-runs `removeThread` (idempotent in store).

⚠️ **UI/server permission mismatch — `Delete Thread` menu shown to non-owners**
- Server: `PATCH /channels/:id` archive enforces `channel.owner_id === user.id` (`routes/channels.ts:118`). ✅
- Server: `DELETE /channels/:id` for a thread inherits the **existing channel-delete permission gate** (typically `MANAGE_CHANNELS`), **not** an owner check.
- Client: the `⋯` menu unconditionally renders both `Archive Thread` and `Delete Thread` for every viewer. A non-owner / non-mod will see them and get a 403 toast (or silent `console.error`) on click.

Not blocking (UX-only), but worth gating the menu items behind `activeThread.owner_id === currentUserId || hasManageChannels` in a follow-up.

⚠️ **Silent failures** — `handleArchive` / `handleDelete` only `console.error(err)` on failure. The thread is closed regardless, so a user clicking Archive on a thread they don't own will see the panel disappear *visually*, then the gateway will not broadcast (because the server PATCH failed), and the next reload will show the thread is still active. Minor; add a user-visible toast in a follow-up.

### 1.4 Thread Browser — `ThreadBrowser.tsx`

✅ Loads Active + Archived in parallel on mount.
✅ Backdrop click closes; stops propagation on panel.
✅ Truncates long names (50 chars).

⚠️ **No Escape-key close handler** (the panel's `⋯` menu has Escape, but this modal does not). Minor UX inconsistency.

⚠️ **No refetch when threads change while open** — if a `THREAD_CREATE` arrives while the browser is open, the new thread won't appear until the user closes/reopens. The store has the data; could subscribe to `useThreadStore` instead of taking a one-shot snapshot. Not blocking.

### 1.5 Sidebar real-time updates — `Sidebar.tsx` + `gateway-subscriptions.ts`

✅ `THREAD_CREATE` → `addThread` (dedupes via id check). Also sets `message.thread` on the parent message in `useMessageStore`.
✅ `THREAD_UPDATE` with `archived: true` → `removeThread` (sidebar pruned immediately). Non-archived updates → `updateThread`.
✅ `THREAD_DELETE` → `removeThread`.
✅ Initial guild load now calls `fetchGuildActiveThreads` and seeds `useThreadStore` grouped by `parent_id`. Bot filtering is server-side via `requireBotChannelPermission`. ✅

ℹ️ **`useMessageStore.setMessageThread` no-ops when `messages[channelId]` isn't loaded** — i.e., the thread indicator on the parent message only appears if the user has already opened the parent channel. On a fresh visit the indicator does appear (REST `list` enriches via `getThreadForMessage`). Acceptable; matches Discord's lazy behavior.

### 1.6 Thread icon — `ThreadIcon.tsx`

✅ Single stroke-style SVG used consistently across `Sidebar`, `ChatArea` header, `ThreadPanel` header, `ThreadIndicator`, and `ThreadBrowser`. Good unification.

### 1.7 `requireBotChannelPermission` thread inheritance — `routes/helpers.ts`

✅ Falls back to `parent_id` permission check for `type === 11`. Correctly applied to: join, leave, add-member, list-members, list-active-by-channel, list-archived, guild-active list (via filter).

ℹ️ Note: only VIEW_CHANNEL is inherited here. Other gates in `messages.ts` (e.g. when checking permissions to send into a thread) currently come from the channel's own overwrites; threads have empty overwrites by repo construction (`permission_overwrites: []`). For a personal project this defers to the existing send-permission check which is parent-channel-based in practice. Not a R5 regression.

---

## 2. Regression Check (R1–R4 surface)

- **Owner archive check** still in place (`channel.owner_id && channel.owner_id !== user.id`). The pre-existing R4 follow-up note about `owner_id NULL guard` (`SET NULL` cascade) is honored here: if `owner_id` is `NULL`, the check is bypassed and anyone may archive. Documented as deferred. ✅
- **Archived/locked send-block** (`routes/messages.ts`) unchanged and still returns 403 with code 50083. ✅
- **`broadcastToGuildWithChannelFilter`** thread→parent permission resolution is unchanged and correct. ✅
- **Bulk delete** now decrements `message_count` by `deleted.length`. ✅ (R4 follow-up about emitting `THREAD_UPDATE` after bulk delete remains deferred per scope.)
- **Standalone thread creation** still requires `requireBotChannelPermission` on parent. ✅
- **No regressions observed** in the existing per-channel permission code or migration runner.

Minor pre-existing items still deferred (per task brief, post-merge OK):
- Webhook archive/lock enforcement
- `THREAD_UPDATE` emission after bulk-delete and after `message_count` reset
- `owner_id` NULL guard on PATCH archive/lock
- Leave-route VIEW_CHANNEL guard (currently requires VIEW on parent which is correct for staying, but leave usually shouldn't require any guard)
- Emoji-name truncation in indicator labels
- App.tsx resize drag listeners not removed if component unmounts mid-drag
- Moderator (non-owner) removal route

None block merge.

---

## 3. Summary + Verdict

R5 cleanly closes the schema/UX gaps from R4:
- Discord-faithful thread shape (ThreadID = MessageID, full `Channel` on `Message.thread`, `invitable`, `flags`)
- Migration v16 is idempotent and safe
- Delete/archive UI is functional with proper menu lifecycle
- Sidebar + Thread Browser reflect real-time state via the new gateway events

No functional bugs or security issues found in the R5 additions. The remaining nits (N+1 enrichment, menu items shown to non-owners, no Escape on Thread Browser, silent toast on archive/delete failure) are quality-of-life polish appropriate for follow-up issues.

Luna has signed off after staging testing. Tests cover the critical thread paths (`threads.test.ts`, 535 lines added). Migration tests updated to v16.

### Verdict: ✅ **Ready to merge**

— 🌠 Nova
