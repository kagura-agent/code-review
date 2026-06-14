# PR #352 Consolidated Review — `feat: channel file space with cove.md convention`

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Verdict: ⚠️ Needs Changes (unanimous)**

---

## Consensus Findings (2+ reviewers)

### 🔴 C1. Bot channel-permission bypass on all file routes (Stella + Nova)

**File:** `packages/server/src/routes/channel-files.ts`

All 4 file routes call `requireGuildMember` but skip `requireBotChannelPermission(VIEW_CHANNEL)`. Every other channel-scoped route (channels.ts, webhooks.ts) enforces this check. A bot that's a guild member but denied `VIEW_CHANNEL` via overwrites can:
- List/read all files including `cove.md` (private channel instructions)
- Create/overwrite/delete files

This is especially sensitive because `cove.md` is auto-injected into LLM prompts — a denied bot could read or tamper with private channel context (prompt injection surface).

**Fix:** Add `requireBotChannelPermission` check to all 4 handlers, matching the pattern in `channels.ts`.

### 🔴 C2. Missing test for bot + overwrite-deny path (Stella + Nova)

No test covers `bot: 1` + `VIEW_CHANNEL` deny overwrite → blocked. Per review standard: "Security/auth paths without tests = Critical."

### 🟡 C3. `content_type` field has no max length (Stella + Nova + Vega)

Route validates type but not length. All 3 reviewers flagged this. Cap to ~128 chars.

### 🟡 C4. Silent UI errors on save/create/delete failures (Stella + Vega)

Catch blocks log to console only. Users get no feedback when hitting 100KB limit or invalid filename.

---

## Per-Reviewer Unique Findings

### 🌠 Nova (most detailed)
- **Performance:** Every dispatched message adds HTTP round-trip for cove.md with no caching. Suggest TTL cache or WS event.
- **Size cap asymmetry:** Server allows 100KB, plugin injects only ≤8000 chars. Users will save large cove.md and wonder why bot ignores it. Surface the cap in UI.
- **No realtime updates:** File edits don't propagate to other clients. Suggest `CHANNEL_FILE_UPDATE` WS event.
- **Upsert has unnecessary SELECT + race window** (S2) — single INSERT ON CONFLICT is cleaner.
- **`content.length` is UTF-16 units, not bytes** — CJK cove.md could exceed byte budget.
- **Client state leaks across channel switches** — selectedFile/fileContent persists when switching channels.
- **Double-fetch on create** — saveFile refetches, then handleFileClick refetches again.

### 🌟 Stella
- **Validate filename on GET/DELETE too** — only PUT validates with FILENAME_RE. GET/DELETE accept any route param.
- **Rate-limit bucket** — file PUT/DELETE falls through to global bucket, not channel-write bucket.
- **cove.md byte vs char measurement** — `content.length <= 8000` should be `Buffer.byteLength`.

### 💫 Vega
- **Redundant network requests** — saveFile ignores return value and re-fetches.
- **Silent cove.md plugin limit** — consider truncating with warning instead of skipping entirely.

---

## Verdict Summary

| Reviewer | Rating | Key Concern |
|----------|--------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | Bot permission bypass |
| 🌠 Nova | ⚠️ Needs Changes | Bot permission bypass + performance |
| 💫 Vega | ⚠️ Needs Changes | content_type validation |

### Overall: ⚠️ Needs Changes

**Before merge (blockers):**
1. Add `requireBotChannelPermission(VIEW_CHANNEL)` to all file routes
2. Add bot + overwrite-deny test
3. Cap `content_type` max length

**Should fix:**
4. Validate filename on GET/DELETE (not just PUT)
5. Surface save/create errors to users (not just console)

**Follow-up issues:**
6. Cache cove.md in plugin dispatch (performance)
7. Surface 8KB injection cap in UI
8. WS events for file changes (realtime)
9. Fix content.length to byte measurement
