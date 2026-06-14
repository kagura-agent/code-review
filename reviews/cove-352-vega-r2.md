# Vega PR Review - Round 2 for #352

## 1. R1 Issue Status

### 🔴 Critical
- **Bot permission bypass** — ✅ Fixed (`requireBotChannelPermission` applied to all 4 routes).
- **Missing bot permission tests** — ✅ Fixed (6 tests added for VIEW_CHANNEL granted/denied).

### 🟡 Vega's R1 Findings
- **content_type no max length** — ✅ Fixed (255 char limit added).
- **Silent UI errors** — ⚠️ Partially Fixed. `message.error` added for `saveFile` and `createFile`, but `deleteFile` lacks error handling in the UI (no try/catch around `handleDelete` in `FilesSidebar.tsx`).
- **Redundant network requests in saveFile** — ❌ Not Fixed. `useChannelFilesStore.saveFile` still makes 3 network calls (PUT, GET list, GET file) per save, despite PUT returning the updated file object.
- **Silent cove.md plugin limit** — ❌ Not Fixed. In `dispatch.ts`, `cove.md` files > 8KB are still silently dropped without any truncation or context warning to the user or the bot.

### Other R1 Items
- **Stella: GET/DELETE filename validation** — ✅ Fixed (RegEx added to GET/DELETE).
- **Nova: content.length → Buffer.byteLength** — ✅ Fixed.
- **Nova: upsert race window** — ❌ Not Fixed. In `ChannelFilesRepo.upsert`, the `SELECT` followed by `INSERT ... ON CONFLICT` still lacks an explicit database transaction, allowing for race conditions.
- **Nova: client state leaks** — ❌ Not Fixed. Switching channels with `FilesSidebar` open does not reset `selectedFile` or `fileContent` in `useChannelFilesStore`, leaking the previous channel's file viewing state.

## 2. New Issues
- **Unhandled Promise Rejection on Delete**: In `FilesSidebar.tsx`, `handleDelete` calls `deleteFile` without a `try/catch`. If the API fails, the user gets no error feedback.

## 3. Summary + Verdict

**Verdict: ⚠️ Needs Changes**

The critical security issues and missing tests from R1 were correctly addressed, which is a big step forward. However, several mid-level architecture and UX issues (silent limits, redundant network requests, state leaks across channels, and lack of DB transactions) remain unaddressed from Round 1. We need one more pass to clear out these remaining bugs before merging.
