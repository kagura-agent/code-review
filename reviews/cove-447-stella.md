# PR #447 Review — feat: redesign FRE — auto-guild, invite-agent endpoint, Settings > Bots integration

**Reviewer:** 🌟 Stella  
**Verdict:** ⚠️ Needs Changes  

## Summary

This PR replaces the multi-page onboarding wizard with a streamlined flow: auto-create a personal guild on registration/login, add a new `POST /guilds/:guildId/invite-agent` endpoint for bot invitations, and move the invite-bot UI into Settings > Bots with a nice letter-paper design. The client-side refactor is clean (new `useSettingsStore`, FRE detection via member store subscription, Ant Design removal from onboarding pages). The server-side `invite-agent` endpoint is well-structured with transactional bot creation and a thoughtful re-invite flow. One real bug: the `createPersonalGuild` function in `register.ts` lacks a transaction wrapper, so a mid-operation failure leaves the DB inconsistent.

---

## Critical Issues

### 1. `createPersonalGuild` in register.ts is not transactional

**File:** `packages/server/src/routes/register.ts` — `createPersonalGuild()` function  

The function executes 4 independent SQL statements (INSERT guild, INSERT role, INSERT channel, INSERT member) without a transaction. If any statement after the first fails (e.g., role insert fails on a constraint), the DB is left with an orphaned guild row.

By contrast, `ensurePersonalGuild` in `auth.ts` correctly wraps the same operations in `db.transaction(() => { ... })()`.

Additionally, `createPersonalGuild` is called *after* the registration transaction commits (line ~107). If guild creation fails, the user is registered and logged in but has no guild — and the error is uncaught (it will throw and return 500, but the registration side effects are already committed).

**Fix:** Either wrap the 4 statements in `db.transaction()` (matching `auth.ts`), or better yet, move the guild creation *inside* the existing `register()` transaction so registration + guild creation are atomic.

---

## Product Impact

### FRE auto-opens Settings > Bots when guild has no bots
The FRE detection (`App.tsx`, lines ~218-238) subscribes to `useMemberStore` and auto-opens `Settings > Bots` if the first guild has no bot members. This is the intended behavior per the PR description. One edge case: if a user deletes their last bot, the FRE will re-trigger on the next full page load (since `freCheckedRef` only persists for the component lifecycle, not across navigations that remount `<App>`). This may be acceptable — or even desirable as a nudge — but worth noting as a product decision.

### Invite letter uses raw `username`, not display name
**File:** `packages/server/src/routes/guilds.ts`, line 114  
`inviterName` is set to `c.get("botUser").username`, not `global_name || username`. If a user has set a display name (e.g., "Luna" vs username "daniyuu"), the invite letter will say "From: daniyuu" instead of "From: Luna". The client-side `InvitationTab` pre-populates `inviterName` from `globalName || username`, but that's only used for the pre-invite prompt text — the actual letter content comes from the server response.

---

## Suggestions

### 1. DRY: Extract shared guild creation logic
**Files:** `packages/server/src/routes/auth.ts`, `packages/server/src/routes/register.ts`  

`ensurePersonalGuild` and `createPersonalGuild` are near-identical (auth.ts adds a guard check + transaction; register.ts has neither). Extract a single `createPersonalGuild(db, userId, username)` utility to a shared module (e.g., `packages/server/src/guild-utils.ts`) and call it from both locations. The guard check can stay in the auth.ts caller.

### 2. Clipboard copy reports success even on failure
**File:** `packages/client/src/components/BotManagement.tsx`, `handleCopy` callback  

```ts
navigator.clipboard.writeText(inviteResult.inviteLetter).catch(() => {});
setCopied(true);
```

`setCopied(true)` runs synchronously regardless of whether the clipboard write succeeds. If the browser denies clipboard access (e.g., non-HTTPS in some browsers, or user denied permission), the button shows "✅ Copied!" but nothing was copied. Move `setCopied(true)` inside the `.then()` or use async/await with try/catch.

### 3. `copied` state never resets
**File:** `packages/client/src/components/BotManagement.tsx`  

Once set to `true`, `copied` never reverts. Standard UX is to reset after 2-3 seconds so the user can re-copy if needed:
```ts
setCopied(true);
setTimeout(() => setCopied(false), 3000);
```

### 4. Surface server error messages in InvitationTab
**File:** `packages/client/src/components/BotManagement.tsx`, `handleInvite` catch block  

```ts
} catch {
  setError("Failed to create invite. Please try again.");
}
```

The server returns structured validation errors (e.g., name too long), but the catch block discards them. Consider extracting the error message from the response body to give users actionable feedback.

### 5. Minor TOCTOU in `ensurePersonalGuild`
**File:** `packages/server/src/routes/auth.ts`  

The "does a personal guild already exist?" check happens *outside* the transaction. Two concurrent OAuth callbacks for the same user could both pass the check and create duplicate personal guilds. The risk is low (snowflakes are unique, so it's two guilds, not a crash), but wrapping the check inside the transaction would close the gap:
```ts
db.transaction(() => {
  const existing = db.prepare(...).get(userId, userId);
  if (existing.count > 0) return;
  // ... create guild
})();
```

### 6. `useSettingsStore` `initialSection` is not cleared after consumption
**File:** `packages/client/src/stores/useSettingsStore.ts` + `packages/client/src/components/SettingsPanel.tsx`  

When the panel opens with `initialSection = "bots"` (from FRE), the effect sets `activeSection` to "bots". But if the user closes the panel and manually reopens it, `initialSection` still has the stale value "bots" (it's only cleared by `close()`... which does clear it). Actually, `close()` does set `initialSection: undefined` — this is fine. Disregard.

---

## Positive Notes

1. **Clean state management** — `useSettingsStore` with `openTo(section)` is a nice pattern for external navigation into settings panels. The Zustand store is minimal and well-typed.

2. **Transactional bot creation** — The `invite-agent` endpoint wraps bot user + role + member creation in a single transaction. The role position shifting (`UPDATE roles SET position = position + 1`) is correctly handled.

3. **Re-invite flow** — Regenerating the token for an existing same-name bot instead of returning 409 is thoughtful UX. It means "re-send invitation" just works without manual cleanup.

4. **FRE detection** — Using `useMemberStore.subscribe()` with a ref guard and cleanup is a clean pattern that avoids render loops while reacting to async data arrival.

5. **Invite letter design** — The letter-paper CSS and the copy-to-clipboard flow make the invitation feel personal and polished. The setup commands embedded in the letter text are practical.

6. **Ant Design removal from onboarding** — Replacing Ant Design components (`Input`, `Button`, `GoogleOutlined`) with plain HTML + CSS on the onboarding pages reduces bundle weight for the critical first-load path and gives more design control.
