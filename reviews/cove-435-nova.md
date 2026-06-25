# Code Review: PR #435 — Permissions Management UI (#282)

**Reviewer:** 🌠 Nova
**PR:** https://github.com/kagura-agent/cove/pull/435
**Commit:** d644be1
**Date:** 2026-06-25
**Verdict:** ⚠️ Needs Changes

---

## Summary

Solid feature PR that adds a Discord-parity permissions management UI: role CRUD, permission toggles, member role assignment, and channel permission overwrites with a three-state toggle. The zustand store design is clean, gateway subscriptions are well-structured, and the React #185 fix (module-level constants for stable selector fallbacks) shows good debugging discipline.

However, there are several spec deviations, a data corruption bug in the gateway handler, inconsistent error handling, and hardcoded permission bypasses that need addressing before merge.

---

## Critical Issues

### C1. GUILD_MEMBER_UPDATE handler fabricates user data with ID as username

**File:** `gateway-subscriptions.ts` lines 250-257

```typescript
subscribe("GUILD_MEMBER_UPDATE", (data) => {
  useMemberStore.getState().upsertMember(data.guild_id, {
    user: { id: data.user.id, username: data.user.id, /* ← BUG */ avatar: null, bot: false, ... },
    nick: data.nick,
    roles: data.roles,
    joined_at: "",
  });
});
```

When a member's roles change, this handler constructs a fake user object with the user's **ID as the username**. After any role assignment/removal, the Members section will display raw snowflake IDs instead of actual usernames. This corrupts the member store's existing user data.

**Fix:** Merge with existing member data rather than replacing:
```typescript
subscribe("GUILD_MEMBER_UPDATE", (data) => {
  const existing = useMemberStore.getState().membersByGuildId[data.guild_id]?.[data.user.id];
  if (existing) {
    useMemberStore.getState().upsertMember(data.guild_id, {
      ...existing,
      nick: data.nick,
      roles: data.roles,
    });
  }
  // If member not found, could fetch or ignore — but don't fabricate user data
});
```

### C2. RoleEditor syncs form from store on every role update — overwrites user edits

**File:** `RoleEditor.tsx` lines ~107-112

```typescript
useEffect(() => {
  if (!role) return;
  setName(role.name);
  setColorHex(role.color ? role.color.toString(16).padStart(6, "0") : "");
  setPermissions(BigInt(role.permissions));
}, [role?.id, role?.name, role?.color, role?.permissions]);
```

Dependencies include `role?.name`, `role?.color`, `role?.permissions`. If another user edits the same role (or any gateway event triggers a role update), this effect fires and **silently overwrites the local user's unsaved edits** — exactly the scenario the spec's "concurrent update" handling was supposed to address.

**Fix:** Only re-sync on `role?.id` change (role switch). For same-role updates, compare dirty fields and show the spec's conflict banner ("This role was updated by someone else").

---

## Major Issues

### M1. Hardcoded owner permissions bypass all client-side hierarchy checks

**Files:** `ServerSettings.tsx` (RolesSection, MembersSection)

```typescript
const userHighestPosition = 999;
const userPermissions = ~0n; // all bits set for owner
```

Both `RolesSection` and `MembersSection` hardcode max permissions. Every non-owner user will see all roles as editable, all members as assignable, and all permissions as toggleable. The server should reject unauthorized requests, but:

1. Users see controls they can't use → confusing UX, wasted API calls returning 403
2. Defeats the spec's per-section permission gates (`MANAGE_ROLES` requirement)
3. The entry point in `Sidebar.tsx` shows the gear icon unconditionally when `guildId` exists — no permission check

This is flagged as a TODO in the code, but it's a **spec blocker** — the spec explicitly requires hierarchy enforcement and per-section permission gates.

**Fix:** Derive `userHighestPosition` and `userPermissions` from the current user's member data and role assignments. Gate the gear icon visibility on `MANAGE_GUILD || MANAGE_ROLES`.

### M2. No "discard changes" dialog when navigating away with dirty state

**Spec says:** "Navigate away with changes: if user clicks a different role or closes settings with unsaved changes → confirmation dialog: 'You have unsaved changes. Discard?'"

**Implementation:** Neither switching roles in RoleList nor pressing Escape/clicking backdrop triggers a discard confirmation. Unsaved changes are silently lost (or silently overwritten per C2).

### M3. Inconsistent error handling — mix of console.error, alert(), and no feedback

The spec explicitly requires toast notifications, not `console.error`.

| Component | Error path | Current handling | Spec requirement |
|-----------|-----------|-----------------|-----------------|
| RoleEditor.handleSave | API error | `console.error` | Toast |
| RoleEditor.handleDelete | API error | `console.error` | Toast |
| RoleList.handleCreate | API error | `console.error` | Toast |
| RoleList.handleMoveUp/Down | API error | `console.error` | Toast |
| ServerSettings.RolesSection | fetchRoles error | `console.error` | Toast |
| MembersRoleSection | assign/remove | `alert()` | Toast with specific messages (403→"Missing Permissions") |
| ChannelPermissionsEditor | save/remove | `alert()` | Toast |

**Fix:** Use a consistent toast system (e.g., antd's `message.error()` which is already available via the antd dependency). Differentiate 403 vs 404 vs network errors per spec.

### M4. Delete confirmation dialog doesn't show member count or cascade info

**Spec says:** "Delete [role name]? X members have this role. Channel permission overwrites for this role will be removed."

**Implementation:**
```typescript
<p>Are you sure you want to delete <strong>{role.name}</strong>? This cannot be undone.</p>
```

No member count, no cascade impact warning.

---

## Minor Issues

### m1. ThreeStateToggle label color ternary is a no-op

**File:** `ThreeStateToggle.tsx` line 24

```typescript
color: disabled ? "var(--text-muted)" : "var(--text-muted)"
```

Both branches return the same value. Non-disabled labels should use `var(--text-normal)` for contrast.

### m2. `memberRoles` mapped with `any` type

**File:** `MembersRoleSection.tsx` line ~62

```typescript
{memberRoles.map((role: any) => (
```

The `.filter(Boolean)` after `.map()` should narrow the type. Use a type guard or explicit cast:
```typescript
.filter((r): r is Role => !!r);
```

### m3. `assignableRoles` not memoized in MembersRoleSection

```typescript
const assignableRoles = roles.filter(
  (r) => r.position < userHighestPosition && r.position > 0 && !r.managed
);
```

Computed on every render. Wrap in `useMemo([roles, userHighestPosition])`.

### m4. `overwriteTargets` not memoized in ChannelPermissionsEditor

The `overwrites.map(...)` building `overwriteTargets` runs on every render. Wrap in `useMemo([overwrites, roles, members])`.

### m5. Missing keyboard accessibility

- **ThreeStateToggle:** Buttons have only symbol content (`✓`, `—`, `✕`) with no `aria-label`. Screen readers and keyboard users get no semantic meaning.
- **Role list items / overwrite target list items:** `<div onClick>` with no `tabIndex`, `role="button"`, or `onKeyDown` handler. Not keyboard navigable.
- **Dropdown in MembersRoleSection:** Custom dropdown div is not focusable and doesn't support keyboard navigation (arrow keys, Enter, Escape).

### m6. Inline style objects in JSX create new references each render

Files: `MembersRoleSection.tsx`, `ChannelPermissionsEditor.tsx`

Many inline style objects (e.g., `style={{ padding: "8px 12px", ... }}`) are created fresh on each render. For the overwrite target list and member list, these add up. Extract to `const` or use CSS classes.

### m7. RoleEditor selector re-renders on any guild role change

```typescript
const roles = useRoleStore((s) => s.roles[guildId] || EMPTY_ROLES);
const role = roles.find((r) => r.id === roleId);
```

The selector returns the full guild role array. Any role create/update/delete in the guild triggers re-render even if the selected role is unchanged. Consider a targeted selector:
```typescript
const role = useRoleStore((s) => (s.roles[guildId] ?? EMPTY_ROLES).find(r => r.id === roleId));
```
Note: the `find` result identity changes on every store update since the array is re-sorted. To make this truly stable, use `useShallow` or a custom equality check. Low priority given typical role list sizes.

### m8. Spec says VIEW_CHANNEL in "GENERAL SERVER PERMISSIONS" group, but implementation puts it in "TEXT CHANNEL"

**File:** `RoleEditor.tsx` — PERMISSION_GROUPS puts `VIEW_CHANNEL` under "TEXT CHANNEL" group. The spec lists it under "GENERAL SERVER PERMISSIONS". Minor UI discrepancy.

### m9. `SEND_TTS_MESSAGES` in RoleEditor but not in spec

`RoleEditor.tsx` includes `SEND_TTS_MESSAGES` in the TEXT CHANNEL group, but the spec's permission list doesn't include it. Harmless addition, but worth noting.

---

## What's Good

1. **Module-level constants pattern** (`EMPTY_ROLES`, `EMPTY_MEMBERS`) — clean solution to the zustand selector instability problem. Well-documented in commit messages.

2. **useRoleStore design** — clean interface, sorted on write, no derived state in the store. `getState()` for imperative updates in callbacks avoids stale closures.

3. **Gateway subscription structure** — READY handler seeds roles from guild data, lifecycle events keep store in sync. Clean separation from component code.

4. **ThreeStateToggle** — simple, focused component. The three-segment design with CSS variable theming is correct.

5. **Bitwise permission handling** — `BigInt` used correctly for permission bits. `setBit` helper is clean. The allow/deny mutual exclusion in `handleToggle` is correct.

6. **Save bar pattern** — dirty detection via useMemo comparing form state to role data. Reset and save flows are correct.

7. **Color handling** — hex validation via regex replace, preset swatches, preview dot. Nice UX.

8. **Escape key handler** in ServerSettings with proper cleanup.

---

## File-by-File Notes

| File | LOC | Notes |
|------|-----|-------|
| `useRoleStore.ts` | 43 | Clean. Sort-on-write is correct. |
| `gateway-subscriptions.ts` | +30 | Good structure, but GUILD_MEMBER_UPDATE handler has data fabrication bug (C1). |
| `gateway-dispatcher.ts` | +6 | Correct type additions. |
| `api.ts` | +31 | Clean API functions. Minor: `createRole` sends `{}` when no data, some servers may reject empty body on POST — verify. |
| `ServerSettings.tsx` | 175 | Hardcoded permissions (M1). No loading state for initial fetch. |
| `RoleList.tsx` | 185 | Move handlers don't validate hierarchy against `userHighestPosition` — relies on hardcoded 999. |
| `RoleEditor.tsx` | 393 | Form sync issue (C2). Missing discard dialog (M2). Error handling uses console.error (M3). |
| `MembersRoleSection.tsx` | 201 | Missing useMemo for assignableRoles (m3). `any` type (m2). |
| `ChannelPermissionsEditor.tsx` | 233 | Missing useMemo for overwriteTargets (m4). `alert()` for errors (M3). |
| `ThreeStateToggle.tsx` | 52 | Label color bug (m1). Missing aria-labels (m5). |
| `Sidebar.tsx` | +20 | No permission gate on gear icon (M1). `useCallback` for close is good. |
| `282-permissions-ui.md` | 396 | Comprehensive spec. |

---

## Verdict: ⚠️ Needs Changes

**Must fix before merge:**
- **C1** — GUILD_MEMBER_UPDATE handler corrupts member store data (username → ID)
- **C2** — Form sync overwrites user edits on gateway events (at minimum, only sync on role ID change)
- **M1** — Hardcoded permissions (at least derive from actual user data; doesn't need to be perfect, but can't be `999` / `~0n`)
- **M3** — Replace `console.error` and `alert()` with toast notifications

**Should fix (can be follow-up if tracked):**
- **M2** — Discard changes confirmation dialog
- **M4** — Member count in delete confirmation

**Nice to have:**
- m1–m9 minor items
