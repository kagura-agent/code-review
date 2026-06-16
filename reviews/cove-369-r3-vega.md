# Review: PR #369 - Round 3 (Vega)

**Status:** ✅ Ready

All issues from Round 2 have been successfully addressed. 

## Verification of Fixes:
1. **Misleading "missing token" error**: Fixed. `resolveAccount` now correctly throws an actionable error, which is caught and correctly forwarded as the `missingTokenNote` so target resolution soft-fails with the actual config path hint.
2. **Zero multi-account tests**: Fixed. 9 tests were added covering deep merging, fallback, multi-account separation, and actionable error messages. 
3. **`resolveAccount` doesn't apply `defaultAccount`**: Fixed. It now uses `resolveDefaultCoveAccountId(cfg)` effectively.
4. **Per-account schema lacks `additionalProperties: false`**: Fixed.
5. **`account!` non-null assertions**: Fixed. While `!` is still used (which is necessary due to TS closure boundaries since `account` could be undefined outside the callback), the properties are extracted to `accountBaseUrl` and `accountGuildId` local variables once, instead of repeatedly evaluating them inside the array maps.
6. **Error messages lack config path hint**: Fixed. `set channels.cove.accounts.<id>.token` is present.

## Minor Note for the Author (Non-blocking):
You mentioned adding 9 tests, which is true! However, it looks like you accidentally copy-pasted the describe block while writing them. `describe("resolveAccount — multi-account")` and `describe('multi-account resolution')` contain three tests that are almost exact duplicates of each other. Not a blocker for merge, but you might want to clean up the duplicate tests before squashing to keep the test suite tidy.

Great job on the fixes. Ready to merge!
