# Stella Review — kagura-agent/cove PR #447 (Round 2)

## Summary

**Rating: ⚠️ Needs Changes**

Round 2 addresses the main security defects in the new `invite-agent` endpoint: it now requires guild ownership or `MANAGE_GUILD`, rejects bot principals, blocks default token rotation with `409`, validates the agent name before embedding it in commands, and adds focused endpoint tests. That is a strong improvement over R1.

However, two R1 product-impact issues are still not fully addressed and must be escalated under the re-review rule:

1. **FRE multi-guild targeting still uses the first guild in `membersByGuildId` instead of the active router guild.** The invite tab uses the active guild, but the FRE detector that decides whether to open Settings still checks `Object.keys(...)[0]`.
2. **Existing OAuth users can still get unexpected personal/ghost guilds on login.** `ensurePersonalGuild()` runs for existing Google users and creates a guild whenever they do not already own one, even if they are already members of shared/seed guilds.

I would not merge until those two behaviors are corrected or explicitly accepted as intended product changes.

## Previous Issues Status

### Critical Issues from R1

- **C1. No authorization on `invite-agent`** — ✅ Addressed.
  - The endpoint now rejects bot principals and requires either guild ownership or `MANAGE_GUILD` computed from guild roles.
  - Test coverage includes non-owner rejection and bot rejection.

- **C2. Re-invite silently rotates tokens** — ✅ Mostly addressed.
  - Same-name bot in the same guild now returns `409` unless `{ rotate: true }` is provided.
  - The rotate path explicitly regenerates the existing bot token.
  - Remaining UX gap: the client `inviteAgent()` helper and Settings UI do not expose a rotate/re-invite flow, so a duplicate currently becomes a generic “Failed to create invite” message.

- **C3. “Server Admin” label vs default permissions mismatch** — ✅ Addressed.
  - The invite letter/UI now says `Role: Member`, matching the default non-admin permission set.

- **C4. Agent name embedded in shell commands without sanitization** — ✅ Addressed for `agentName`.
  - The endpoint now requires `^[a-zA-Z0-9_-]{2,80}$`, which is safe for the generated `openclaw config set ... agentName` command.

- **C5. No tests for security-sensitive endpoint** — ✅ Addressed.
  - Added tests cover owner success, unauthorized member rejection, duplicate `409`, explicit rotation, invalid names, and bot-principal rejection.
  - Suggested addition: add a positive `MANAGE_GUILD` non-owner test so the allowed delegated-admin path is locked down too.

### Product Impact from R1

- **FRE detector may never fire because it only subscribed and did not check existing state** — ✅ Addressed.
  - It now calls `checkFRE(useMemberStore.getState())` immediately and subscribes afterward.

- **Multi-guild FRE targets/checks the wrong guild** — ❌ Still unaddressed; escalated.
  - `App.tsx` still does:
    ```ts
    const guildIds = Object.keys(state.membersByGuildId);
    const guildId = guildIds[0];
    ```
  - This means the FRE decision is based on whichever guild happens to appear first in store insertion order, not the active guild in the router.
  - Consequences:
    - If the first loaded guild has a bot but the active guild does not, FRE will not open.
    - If the first loaded guild has no bot but the active guild already has bots, Settings may open unexpectedly.
  - The `InvitationTab` correctly uses `getActiveIdsFromRouter()`, but that only affects where the bot gets invited after the modal opens; it does not fix the FRE trigger condition.

- **Existing users get ghost guilds on login** — ❌ Still problematic; escalated.
  - `routes/auth.ts` now calls `ensurePersonalGuild(db, existing.id, googleUser.name)` for existing OAuth users.
  - `ensurePersonalGuild()` checks whether the user is a member of a guild they own, not whether they already have a valid guild membership:
    ```sql
    SELECT COUNT(*) as count
    FROM guild_members
    WHERE user_id = ?
      AND guild_id IN (SELECT id FROM guilds WHERE owner_id = ?)
    ```
  - Any existing user who is only a member of a shared/seed/non-owned guild will receive a new personal guild on login. If that is intentional, it needs an explicit migration/product decision and tests. If not, restrict personal guild creation to new-user registration or to users with no guild memberships at all.

### Suggestions from R1

- **Deduplicate guild creation helpers** — ✅ Addressed.
  - Shared `createPersonalGuild()` / `ensurePersonalGuild()` helpers were added.

- **Clear `initialSection` after consuming** — ✅ Addressed.
  - `SettingsPanel` clears `initialSection` after applying it.

- **`register.ts` not wrapped in transaction** — ✅ Addressed.
  - `createPersonalGuild()` is called inside the existing registration transaction.

## Critical Issues

### 1. Escalated: FRE still checks the first guild instead of the active guild

**Severity: High / Needs Changes**

The R1 issue was not fully fixed. The FRE trigger still derives `guildId` from `Object.keys(state.membersByGuildId)[0]`. The active guild should come from the router, with a safe fallback only if no active guild exists.

Suggested direction:

```ts
const { guildId: activeGuildId } = getActiveIdsFromRouter();
const guildId = activeGuildId ?? Object.keys(state.membersByGuildId)[0];
```

Also ensure the check waits until that specific guild’s members are loaded rather than any guild’s members being present.

### 2. Escalated: Existing OAuth users can still receive unexpected personal guilds

**Severity: High / Needs Changes**

The new `ensurePersonalGuild()` behavior is risky for existing users. It creates a personal guild for existing OAuth users whenever they do not own a guild, even if they already belong to another guild. That is exactly the “ghost guild on login” class of issue from R1.

Please either:

- create personal guilds only during new-user registration / first account creation, or
- change the guard to “no guild memberships at all,” not “no owned guilds,” or
- document this as an intentional migration and add tests for existing member-only users.

## Product Impact

- The Settings > Bots integration is much better than the previous standalone FRE modal approach.
- But the FRE trigger can still be wrong for multi-guild users, so the first-run experience remains nondeterministic.
- Duplicate-agent UX is currently poor: the server returns a meaningful `409`, but the client collapses it into a generic failure and offers no rotate/re-copy path.
- The invite letter contains the token and setup commands, which is expected for this flow, but the UI should make it clear that copying/sending the letter shares a live bot credential.

## Suggestions

1. **Add a `MANAGE_GUILD` positive test.**
   - R2 tests cover non-owner denial, but not the intended delegated-admin success path.

2. **Expose duplicate handling in the client.**
   - On `409`, show “An agent with this name already exists” and offer either “choose another name” or an explicit “rotate token / reissue invite” action.

3. **Include the full invite creation in one transaction where practical.**
   - Bot user creation, membership, managed role assignment, and #general permission grant are currently split: the permission grant happens after the transaction. A failure there leaves a created bot that may not be able to see `#general`.

4. **Consider dispatching role updates for the managed bot role.**
   - The endpoint dispatches `GUILD_MEMBER_ADD`, but clients may not learn about the newly created managed role unless they refetch roles elsewhere.

5. **Sanitize/derive `baseUrl` from trusted server config if available.**
   - `baseUrl` is built from request URL / `x-forwarded-proto`. For invite letters that become copy-pasted shell commands, a configured public base URL is safer and more predictable than request headers.

6. **Make the invite-code registration test name match the new behavior.**
   - The test named “does not auto-join new user to default guild” was changed to filter only the default guild. Consider adding an explicit assertion that a personal guild is created, so the new expected behavior is clear.

## Positive Notes

- The R2 security response is materially stronger: authz, bot rejection, name validation, default duplicate conflict, and tests are all in place.
- `createPersonalGuild()` removes duplicated guild/channel/role setup logic and correctly participates in the caller’s transaction.
- Moving invitation into Settings > Bots is a cleaner product surface than a one-off onboarding modal.
- Clearing `initialSection` after use prevents repeated forced navigation in Settings.
