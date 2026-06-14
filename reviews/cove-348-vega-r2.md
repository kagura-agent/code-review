# PR #348 Code Review - Round 2 (Vega)

## 1. R1 Issue Status
### Consensus Critical
- **C1: Empty string / whitespace-only global_name not normalized server-side**: ✅ Fixed. The `PATCH /users/@me` route now explicitly normalizes empty and whitespace-only strings to `null`.
- **C2: Missing control char / zero-width / RTL validation on global_name**: ✅ Fixed. Added `validateDisplayName` which rejects `[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u2064\uFEFF]`.
- **C3: Missing tests for PATCH /users/@me, resolveUser fix, OAuth fallback**: ✅ Fixed. Added `display-name.test.ts` with 9 tests covering validation, normalization, and an E2E round-trip.
- **C4: Settings hint misleading**: ✅ Fixed. Changed to "Leave empty to use your account name."

### Vega's Findings
- **OAuth COALESCE(global_name, ?) overwrites user-cleared names**: ✅ Fixed. The PR removed the `global_name` update from the OAuth login `UPDATE` query, properly preserving the explicitly cleared names.
- **validateString may reject null**: ✅ Fixed. Confirmed that `validateString` permits `null` when `required` is not set, and tests verify that sending `null` successfully clears the name.

### Team Findings
- **Stella: toUser() in members.ts hardcodes global_name: null**: ✅ Fixed. Now reads `row.global_name ?? null`.
- **Nova: repos.users.update(id!, body) passes whole request body**: ✅ Fixed. The route now builds an explicit `patch` object.
- **Nova: findByToken redundant cast**: ✅ Fixed. `(row as UserRow).global_name` cast was removed.
- **Nova: nick chain incomplete in MessageItem**: ✅ Partially Fixed / Acceptable. Added a TODO comment to handle server-level nicknames when that support lands.
- **Nova: Plugin log line leaks display name with potential control chars**: ✅ Fixed. Server-side validation (`validateDisplayName`) prevents control characters from entering the database in the first place.

## 2. New Issues
No new issues were identified in the updated code. The data flow, client-side saving states, UI fallback chains, and API normalization are all robust.

## 3. Summary + Verdict
✅ **Ready**

Excellent follow-up. All blocking concerns from Round 1 have been completely resolved, the newly added test coverage is comprehensive, and edge cases with empty strings / control characters are properly handled. The PR is safe to merge.