# 🌠 Nova — PR #435 Review (Round 2)

**PR:** kagura-agent/cove#435 — feat: Permissions Management UI (#282)
**Commit:** d12bfdc
**Reviewer:** Nova (code reviewer)
**Round:** 2 (re-review)
**Rating:** ⚠️ Needs Changes

---

## Round 1 Issue Verification

### ✅ C1: GUILD_MEMBER_UPDATE fabricates user data — FIXED

**gateway-subscriptions.ts** now merges with existing member data:
```typescript
const existing = useMemberStore.getState().membersByGuildId[data.guild_id]?.[data.user.id];
const existingUser = existing?.user ?? { id: data.user.id, username: data.user.id, ... };
const mergedUser = { ...existingUser, ...data.user } as typeof existingUser;
```
Correctly preserves existing username/avatar when the gateway event sends a partial user object, then overlays any new fields from the event. Falls back to a sensible default (`data.user.id` as username) for never-before-seen members. **Resolved.**

---

### 🔴 C2: RoleEditor syncs form overwrites user edits — STILL PRESENT

**Status:** Not claimed fixed. Confirmed still present.

**RoleEditor.tsx lines 96–101:**
```typescript
useEffect(() => {
  if (!role) return;
  setName(role.name);
  setColorHex(role.color ? role.color.toString(16).padStart(6, "0") : "");
  setPermissions(BigInt(role.permissions));
}, [role?.id, role?.name, role?.color, role?.permissions]);
```

The effect dependencies include `role?.name`, `role?.color`, `role?.permissions`. When a `GUILD_ROLE_UPDATE` gateway event arrives (e.g., another admin edits the same role), the store updates, the effect re-fires, and **unconditionally overwrites the user's in-progress edits** without warning.

The spec explicitly requires:
- Non-overlapping field changes → silently update baseline only
- Overlapping field changes → banner: "This role was updated by someone else" + [Reload] / [Keep mine]

Neither is implemented. The form needs a separate `baseline` state that tracks the server-known values, independent of the form state. The effect should update the baseline, compare against dirty fields, and only clobber non-dirty fields.

**Impact:** Critical — data loss scenario. User A edits a role name, User B saves a color change, User A's name edit vanishes.

---

### ✅ M1: Hardcoded permission bypass — FIXED

**useUserPermissions.ts** is a well-structured hook. Verified all four requirements:

| Requirement | Status | Evidence |
|---|---|---|
| Owner bypass (`guild.owner_id === userId`) | ✅ | Returns `Infinity` position + `ALL_PERMISSIONS` |
| ADMINISTRATOR grants all bits | ✅ | `if (permissions & PermissionBits.ADMINISTRATOR)` → `ALL_PERMISSIONS` |
| Highest role position from actual member roles | ✅ | Iterates `member.roles`, tracks `role.position > highestPosition` |
| User with no roles (only @everyone) | ✅ | `highestPosition` stays 0, `permissions` starts from @everyone role. User correctly can't edit any role (all have position ≥ 0) |

Additional correctness: @everyone role identified by `r.id === guildId` (Discord convention). The hook is consumed by both `RolesSection` and `MembersSection`, replacing any hardcoded checks. **Resolved.**

---

### 🟠 M2: No discard changes dialog — STILL PRESENT

**Status:** Not claimed fixed. Confirmed still present.

When a user has unsaved changes in `RoleEditor` and clicks a different role in `RoleList`, the `selectedRoleId` changes, the sync effect fires, and form state is silently replaced. No confirmation dialog is shown.

The spec requires: "if user clicks a different role or closes settings with unsaved changes → confirmation dialog: 'You have unsaved changes. Discard?' [Cancel] [Discard]"

**Fix approach:** `RoleList.onSelectRole` should check if the editor has dirty state (lift `isDirty` up or use a ref/callback) and show a `Modal.confirm()` before switching. Similarly, the `ServerSettings` close handler should check for dirty state.

---

### 🟠 M3: console.error/alert() error handling — PARTIALLY FIXED

**What improved:**
- Most error paths now show user-visible feedback via `alert()` instead of silent `console.error`

**What remains:**

1. **One `console.error` survives** in `ServerSettings.tsx`:
   ```typescript
   api.fetchRoles(guildId).then(r => useRoleStore.getState().setRoles(guildId, r)).catch(console.error);
   ```
   If the roles fetch fails, the user sees nothing — the Roles section just stays empty with no indication of failure.

2. **`alert()` blocks the UI thread** and is not appropriate for a modern web app. The spec explicitly calls for **toast** notifications:
   > 403 → toast "Missing Permissions", 404 → toast "Role no longer exists", network error → generic toast

3. **No error differentiation** — all 9 `alert()` calls use generic messages ("Failed to save role", "Failed to create role", etc.) regardless of whether the error is 403 (permission), 404 (deleted resource), or network failure.

4. **`confirm()` used in ChannelPermissionsEditor** (`handleRemove`) — same UI-blocking issue. Should use `Modal.confirm()` from antd (which is already used in `RoleEditor` for delete confirmation — inconsistent).

---

### 🟠 M4: Delete confirmation missing info — STILL PRESENT

**Status:** Not claimed fixed. Confirmed still present.

**RoleEditor.tsx delete modal:**
```tsx
<Modal title="Delete Role" ...>
  <p>Are you sure you want to delete <strong>{role.name}</strong>? This cannot be undone.</p>
</Modal>
```

The spec requires:
> Delete **[role name]**?
> **X members** have this role. Channel permission overwrites for this role will be removed.

Missing:
1. **Member count** — should count members whose `roles` array includes the role being deleted
2. **Channel overwrite warning** — should warn that channel permission overwrites for this role will be removed

The member count is computable from `useMemberStore` (count members whose `roles` includes `roleId`). The overwrite warning is static text.

---

## Summary

| ID | Severity | Description | Status |
|---|---|---|---|
| C1 | 🔴 Critical | GUILD_MEMBER_UPDATE fabricates user data | ✅ Fixed |
| C2 | 🔴 Critical | RoleEditor gateway sync overwrites user edits | ❌ Still present |
| M1 | 🟠 Medium | Hardcoded permission bypass | ✅ Fixed |
| M2 | 🟠 Medium | No discard changes dialog | ❌ Still present |
| M3 | 🟠 Medium | console.error/alert() error handling | ⚠️ Partially fixed |
| M4 | 🟠 Medium | Delete confirmation missing info | ❌ Still present |

**Verdict: ⚠️ Needs Changes**

C2 remains a critical data-loss scenario. M2/M3/M4 are spec deviations that should be addressed before merge. The `useUserPermissions` hook (M1 fix) is well-implemented and the GUILD_MEMBER_UPDATE merge (C1 fix) is correct.

**Blocking:** C2
**Should fix before merge:** M2, M3, M4
