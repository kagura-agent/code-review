# R2 Code Review: cove#269 (Vega)

## 🔴 Must Fix (Escalated from R1 "Should Address")

The following issues were raised in R1 as "Should Address" but were ignored in this round. Per review policy, unaddressed issues are escalated to "Must Fix".

1. **60s per-connection polling scalability**
   - **Status**: ❌ Unaddressed (Escalated to 🔴 Must Fix)
   - **Details**: `SESSION_EXPIRY_CHECK_INTERVAL` is still 60s per connection (`ws/index.ts`). This does not scale. Please use a centralized check or rely on sliding token expiry.

2. **`repos/users.ts` re-export needs `@deprecated`**
   - **Status**: ❌ Unaddressed (Escalated to 🔴 Must Fix)
   - **Details**: `export { SESSION_TTL_MS };` in `packages/server/src/repos/users.ts` still lacks the `@deprecated` JSDoc tag.

3. **`preAuthUser` not revalidated at IDENTIFY time**
   - **Status**: ❌ Unaddressed (Escalated to 🔴 Must Fix)
   - **Details**: When falling back to `preAuthUser` during `IDENTIFY`, the user is still not re-queried from the database, meaning revoked sessions or changed user states aren't caught until the expiry check fires.

---

## ✅ Addressed R1 Must-Fix Issues

1. **re-IDENTIFY leaks intervals**
   - **Status**: ✅ Fixed (Noted that `session.isIdentified` guard is already present and prevents the interval leak).
2. **Cookie fallback tracks wrong token**
   - **Status**: ✅ Fixed (Always parses the token from the cookie headers instead of trusting the invalid explicit token).
3. **Test 2 doesn't test short TTL**
   - **Status**: ✅ Fixed (Properly tests the threshold logic with a 1h short TTL).
4. **Test 3 is tautological**
   - **Status**: ✅ Fixed (Uses real `app.request` integration test with global fetch mocking instead of manual SQL updates).

## Conclusion
**Block merging.** The critical issues from R1 were correctly addressed, but the R1 optional issues were unaddressed and are now escalated to blocking per our review rules. Please address the escalated issues.
