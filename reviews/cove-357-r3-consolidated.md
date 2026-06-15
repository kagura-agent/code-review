# PR #357 Round 3 Consolidated Review — feat: Discord-style message threads (#221)

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 3
**Verdict:** ⚠️ Needs Changes (1/3) · ❌ Major Issues (2/3)

---

## R2 Blockers — All 3 Fixed ✅

All three reviewers confirm every R2 blocking issue is resolved:

| # | R2 Blocker | Status |
|---|-----------|--------|
| 1 | Nested thread creation not blocked | ✅ Fixed — rejects `channel.type === 11` with 400 |
| 2 | N+1 active-threads fetch on READY | ✅ Fixed — single `fetchGuildActiveThreads` per guild |
| 3 | `threadDelete` dead code | ✅ Fixed — DELETE dispatches `threadDelete` for type=11 |

---

## Escalated Issues (R2 non-blocking → now blocking)

The reviewers escalated several R2 suggestions that were not addressed. However, applying **small-team/personal-project calibration** per review standard: not all escalations warrant blocking status. Here is a severity-calibrated assessment:

### Must fix before merge

#### 1. Guild active-threads endpoint leaks threads from hidden channels (Stella, Nova, Vega)
**Severity: High (security)**

`GET /guilds/:guildId/threads/active` returns ALL threads without filtering by parent channel VIEW_CHANNEL. Now that the client uses this endpoint for READY hydration (per the N+1 fix), the exposure is increased. Bots with limited channel access can enumerate thread names, parent IDs, and metadata from channels they cannot view.

**Fix:** Filter returned threads by `requireBotChannelPermission(thread.parent_id)` for bot users.

#### 2. PATCH archive/lock has no permission gate — NEW (Nova)
**Severity: High (security)**

`PATCH /channels/:threadId` archive/lock branch has no MANAGE_THREADS or ownership check. **Any guild member can archive or lock any thread.** Discord requires MANAGE_THREADS or thread ownership.

**Fix:** Add explicit permission check before `setArchived`/`setLocked`.

### Should fix before merge

#### 3. Archived/locked threads still accept message writes (Stella, Nova, Vega)
**Severity: Medium (correctness)**

`POST /channels/:id/messages` never checks thread_metadata. Writing to an archived thread succeeds and corrupts archive state. At minimum: auto-unarchive on write if not locked; reject writes to locked threads.

#### 4. Bulk delete / clear-all don't update thread message_count (Stella, Nova, Vega)
**Severity: Medium (correctness)**

Single-message delete decrements correctly, but bulk delete and clear-all leave message_count inflated. Thread indicators show stale reply counts.

### Post-merge OK (small team context)

The following were escalated by reviewers but are appropriate as follow-up for a personal project:

| Item | Severity | Notes |
|------|----------|-------|
| Leave route missing guild-membership guard | Low | Only affects self-removal, low risk |
| No negative permission tests | Low | Happy paths covered; regression risk is real but manageable |
| Drag handler listener leak | Low | Edge case on unmount mid-drag |
| Emoji corruption on auto-naming (`content.slice`) | Low | Cosmetic, affects surrogate pairs near char 40 |
| Missing moderator removal route | Low | Feature gap, not a bug |
| Unused `channelId` prop in ThreadIndicator | Trivial | Lint smell |
| Duplicate CHANNEL_DELETE + THREAD_DELETE dispatch | Low | Works but noisy |

---

## Per-Reviewer Unique Findings (R3-new)

### 🌟 Stella
- **Medium: Duplicate thread race** — no DB uniqueness constraint on `channels.message_id` for type=11. Concurrent creates for the same parent message can both succeed.

### 🌠 Nova (most thorough)
- **Medium: PATCH thread only dispatches THREAD_UPDATE for archive/lock, not name/topic changes** — renaming a thread dispatches CHANNEL_UPDATE, which `useThreadStore` doesn't handle
- **Medium: No LIMIT on active-thread list queries** — no pagination, returns everything
- **Medium: addMember on join doesn't check archive/lock state**
- **Medium: THREAD_CREATE enrichment race** — `setMessageThread` is no-op when parent message not in store
- Minor: archive_timestamp not cleared on unarchive, stale migration test docstring, duplicated validation logic

### 💫 Vega
- **Low: ThreadPanel.tsx replicates the emoji truncation bug** — `activeThread.name.slice(0, 40) + "…"` same surrogate pair issue

---

## Overall Verdict

**⚠️ Needs Changes**

The R2 blockers are solidly fixed. The thread feature is functionally working end-to-end with good test coverage (~29 specs). The architecture is clean and Discord-compatible.

**Two security issues need fixing before merge:**
1. Filter guild active-threads by parent channel permission for bots
2. Add permission gate on PATCH archive/lock

**Two correctness issues should be fixed:**
3. Enforce archived/locked state on message writes
4. Fix bulk-delete message_count drift

Everything else is appropriate for post-merge follow-up at this project's scale.

**Estimated effort: ~1-2 hours for items 1-4.**
