# Code Review: PR #435 — Permissions Management UI (#282)

**Reviewer:** 🌟 Stella
**PR:** https://github.com/kagura-agent/cove/pull/435
**Commit:** d644be1
**Date:** 2026-06-25

## Verdict: ⚠️ Needs Changes

Solid architecture overall — the zustand store design is clean, gateway event wiring is correct, the module-level `EMPTY_ROLES`/`EMPTY_MEMBERS` constants properly fix the React #185 selector stability issue, and the component decomposition (RoleList / RoleEditor / MembersRoleSection / ChannelPermissionsEditor) follows good separation of concerns. The spec document is thorough and well-structured.

However, there are several issues that need to be addressed before merge, most notably a data-corruption bug in the GUILD_MEMBER_UPDATE handler and hardcoded permission bypasses that disable all client-side permission gating.

---

## 🔴 Needs Changes (4 issues)

### NC-1: GUILD_MEMBER_UPDATE handler corrupts member data
**File:** `packages/client/src/lib/gateway-subscriptions.ts` (lines ~250-258)
**Severity:** Bug — data corruption

```typescript
subscribe("GUILD_MEMBER_UPDATE", (data) => {
  useMemberStore.getState().upsertMember(data.guild_id, {
    user: { id: data.user.id, username: data.user.id, avatar: null, bot: false, discriminator: "0", global_name: null },
    nick: data.nick,
    roles: data.roles,
    joined_at: "",
  });
});
```

**Problem:** When a member's roles are updated, this handler overwrites the member record with fabricated data:
- `username` is set to the user's **ID** (not their actual username)
- `avatar`, `bot`, `discriminator`, `global_name` are all hardcoded to wrong values
- `joined_at` is set to empty string

This means any role assignment/removal will corrupt the member's display data — their name will show as a snowflake ID, bot badges will disappear, and avatars will be lost.

**Fix:** Look up the existing member first, then merge only the changed fields:

```typescript
subscribe("GUILD_MEMBER_UPDATE", (data) => {
  const store = useMemberStore.getState();
  const existing = store.membersByGuildId[data.guild_id]?.[data.user.id];
  if (existing) {
    store.upsertMember(data.guild_id, {
      ...existing,
      nick: data.nick,
      roles: data.roles,
    });
  }
  // If no existing member, consider fetching or ignoring
});
```

---

### NC-2: Hardcoded permission bypass — all users treated as owner
**File:** `packages/client/src/components/ServerSettings.tsx` (lines ~37-38, ~59)
**Severity:** Security/UX — client-side permission gating disabled

```typescript
// TODO: derive from actual member roles; hardcode high value for now (owner sees all)
const userHighestPosition = 999;
const userPermissions = ~0n; // all bits set for owner
```

And in `MembersSection`:
```typescript
const userHighestPosition = 999; // owner sees all
```

**Problem:** Every user sees all roles as editable, can reorder any role, and the permission toggle `canToggle` check always passes. While the server should enforce these restrictions, the spec explicitly requires client-side hierarchy enforcement:
- "roles at or above the user's highest role are visible but grayed out (not selectable for editing)"
- "dropdown only shows roles below user's highest role"
- Permission toggles should be disabled for bits the user doesn't have

This means regular members will see edit controls, attempt edits, and get 403 errors — a confusing experience.

**Fix:** Derive `userHighestPosition` and `userPermissions` from the current user's member data in the store:

```typescript
const selfId = useUserStore((s) => s.id);
const selfMember = useMemberStore((s) => s.membersByGuildId[guildId]?.[selfId]);
const selfRoles = roles.filter((r) => selfMember?.roles.includes(r.id));
const userHighestPosition = Math.max(0, ...selfRoles.map((r) => r.position));
const userPermissions = selfRoles.reduce((acc, r) => acc | BigInt(r.permissions), 0n);
```

---

### NC-3: Silent error handling on destructive operations
**Files:** `RoleEditor.tsx`, `RoleList.tsx`
**Severity:** UX — violates spec requirement "No silent console.error"

Multiple handlers catch errors and only log to console with no user feedback:

| File | Function | Error handling |
|------|----------|---------------|
| `RoleEditor.tsx` | `handleSave` | `console.error("update role:", err)` |
| `RoleEditor.tsx` | `handleDelete` | `console.error("delete role:", err)` |
| `RoleList.tsx` | `handleCreate` | `console.error("create role:", err)` |
| `RoleList.tsx` | `handleMoveUp` | `console.error("move role up:", err)` |
| `RoleList.tsx` | `handleMoveDown` | `console.error("move role down:", err)` |

The spec requires: "403 → toast 'Missing Permissions', 404 → toast 'Role no longer exists', network error → generic toast."

**Fix:** Use antd's `message` API or a toast component to show feedback:

```typescript
import { message } from "antd";

// in catch blocks:
if (err instanceof Response && err.status === 403) {
  message.error("Missing permissions");
} else {
  message.error("Failed to update role");
}
```

Note: `MembersRoleSection.tsx` and `ChannelPermissionsEditor.tsx` use `alert()` which at least provides feedback, but should also be migrated to toast/antd message for consistent UX.

---

### NC-4: Gateway events silently overwrite unsaved edits in RoleEditor
**File:** `packages/client/src/components/RoleEditor.tsx` (lines ~79-84)
**Severity:** UX — spec requires conflict detection

```typescript
useEffect(() => {
  if (!role) return;
  setName(role.name);
  setColorHex(role.color ? role.color.toString(16).padStart(6, "0") : "");
  setPermissions(BigInt(role.permissions));
}, [role?.id, role?.name, role?.color, role?.permissions]);
```

**Problem:** When the role store updates (e.g., another admin edits the same role), this effect fires and overwrites any unsaved changes the current user has made — without warning or confirmation.

The spec explicitly requires conflict detection:
> "If a GUILD_ROLE_UPDATE gateway event arrives for the role being edited:
> - If the changed fields don't overlap with dirty fields → silently update baseline
> - If they overlap → show a banner: 'This role was updated by someone else.'"

**Fix:** Track a `baseline` state separate from form state. When the role updates from the store, compare against baseline to detect conflicts:

```typescript
const [baseline, setBaseline] = useState({ name: "", colorHex: "", permissions: 0n });

useEffect(() => {
  if (!role) return;
  const incoming = {
    name: role.name,
    colorHex: role.color ? role.color.toString(16).padStart(6, "0") : "",
    permissions: BigInt(role.permissions),
  };
  if (!isDirty) {
    // No local changes — safe to overwrite
    setName(incoming.name);
    setColorHex(incoming.colorHex);
    setPermissions(incoming.permissions);
  } else {
    // Check for field overlap with dirty fields
    const conflicts = (name !== baseline.name && incoming.name !== baseline.name)
      || (colorHex !== baseline.colorHex && incoming.colorHex !== baseline.colorHex)
      || (permissions !== baseline.permissions && incoming.permissions !== baseline.permissions);
    if (conflicts) {
      // Show conflict banner
    }
  }
  setBaseline(incoming);
}, [role?.id, role?.name, role?.color, role?.permissions]);
```

---

## 🟡 Suggestions (7 items)

### S-1: ThreeStateToggle label color ternary is a no-op
**File:** `packages/client/src/components/ThreeStateToggle.tsx` (line 27)

```typescript
color: disabled ? "var(--text-muted)" : "var(--text-muted)"
```

Both branches are identical. The enabled label should use `var(--text-normal)` or similar to distinguish from disabled state.

---

### S-2: Use antd Modal/message instead of browser `alert()`/`confirm()`
**Files:** `ChannelPermissionsEditor.tsx`, `MembersRoleSection.tsx`

Browser `alert()` and `confirm()` block the main thread, look inconsistent across platforms, and don't match the app's design system. The `RoleEditor.tsx` already uses antd `Modal` for delete/admin confirmation — the other components should follow the same pattern for consistency.

---

### S-3: Accessibility — clickable divs missing keyboard/ARIA support
**Files:** `ChannelPermissionsEditor.tsx` (overwrite target list), `MembersRoleSection.tsx` (role dropdown items)

Several interactive elements use `<div onClick>` without:
- `role="button"` or `tabIndex={0}`
- `onKeyDown` handler for Enter/Space
- ARIA labels describing the action

```typescript
// ChannelPermissionsEditor.tsx line ~146
<div onClick={() => setSelectedTarget(...)}>  // not keyboard-accessible

// MembersRoleSection.tsx line ~165
<div onClick={() => handleAddRole(...)}>  // not keyboard-accessible
```

The `ThreeStateToggle` buttons and `ServerSettings` close button have proper elements — extend this pattern to the rest.

---

### S-4: Extract color-to-hex utility
**Files:** `RoleList.tsx`, `RoleEditor.tsx`, `MembersRoleSection.tsx`, `ChannelPermissionsEditor.tsx`

The expression `role.color.toString(16).padStart(6, "0")` appears ~8 times across 4 files. Extract to a shared utility:

```typescript
// lib/utils.ts
export function colorToHex(color: number): string {
  return color.toString(16).padStart(6, "0");
}
```

---

### S-5: Rapid reorder clicks can race
**File:** `packages/client/src/components/RoleList.tsx`

`handleMoveUp` and `handleMoveDown` each fire an immediate API call with no debounce or queue. A user clicking the up arrow 5 times rapidly will fire 5 concurrent PATCH requests that may resolve out of order, leaving roles in an unexpected position.

Consider adding a brief debounce, or disabling the arrows while a reorder is in-flight (similar to how `creating` state disables the create button).

---

### S-6: No loading state for role list
**File:** `packages/client/src/components/ServerSettings.tsx`

When `RolesSection` mounts and calls `api.fetchRoles()`, there's no loading indicator. The user sees an empty role list until the response arrives. Add a loading state or skeleton.

Also, the `useEffect` fetch doesn't abort on unmount:
```typescript
useEffect(() => {
  api.fetchRoles(guildId).then((r) => useRoleStore.getState().setRoles(guildId, r)).catch(console.error);
}, [guildId]);
```

Consider using an `AbortController` or at minimum a mounted check.

---

### S-7: Member list not virtualized
**File:** `packages/client/src/components/MembersRoleSection.tsx`

The member list renders all members at once. For servers with hundreds of members, this could cause performance issues. For typical Cove use (small communities) this is fine, but worth noting for future scaling. Consider `react-window` or pagination if the member count grows.

---

## ✅ What's Done Well

1. **Module-level constants pattern** — `EMPTY_ROLES` and `EMPTY_MEMBERS` correctly prevent unstable selector references (the React #185 fix). This is applied consistently across all components.

2. **Zustand store design** — `useRoleStore` is clean, properly sorts by position, and handles all CRUD operations immutably. The `sortRoles` helper with `id` tiebreaker is a nice touch for deterministic ordering.

3. **Gateway event wiring** — The READY payload seeding properly extracts roles alongside channels, and the three role lifecycle events (CREATE/UPDATE/DELETE) correctly sync the store. The `roles` field in `ReadyGuild` is properly marked optional.

4. **Component decomposition** — Clean separation between RoleList, RoleEditor, MembersRoleSection, and ChannelPermissionsEditor. Each component has a focused responsibility.

5. **CSS variables** — Consistent use of design system variables (`--text-normal`, `--bg-modifier-active`, `--border-subtle`, etc.) across all components. No hardcoded color values.

6. **Permission bit manipulation** — The `setBit` helper and `getToggleState` in ChannelPermissionsEditor correctly handle BigInt bitwise operations for three-state toggles.

7. **Spec document** — Comprehensive spec with clear phases, edge cases, and test plan. Good Discord-parity reference.

8. **Save bar pattern** — Dirty detection with Reset/Save in RoleEditor uses proper `useMemo` comparison against the role state.

---

## Summary

| Category | Count |
|----------|-------|
| 🔴 Needs Changes | 4 |
| 🟡 Suggestions | 7 |

The PR needs fixes for the **GUILD_MEMBER_UPDATE data corruption bug** (NC-1) and **hardcoded permission bypass** (NC-2) before merge. The **silent error handling** (NC-3) and **gateway conflict overwrite** (NC-4) are also important for UX quality but less urgent. The suggestions are polish items that can be addressed in follow-up PRs.
