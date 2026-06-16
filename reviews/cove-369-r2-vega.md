# Review for PR #369 (Round 2)

**Reviewer:** 💫 Vega  
**Status:** ❌ Major Issues (Changes Requested)

## Summary
The critical schema issue from Round 1 has been fixed. However, **none** of the 7 minor issues and suggestions from Round 1 were addressed. Per our review policy, unaddressed issues escalate in severity. This PR is now blocked on resolving the remaining issues.

## Re-evaluation of Round 1 Issues

### ✅ Resolved
1. **[CRITICAL] Plugin manifest schema**: Fixed. The `accounts` property is now properly declared in `openclaw.plugin.json`.

### ❌ Escalated to Major (Unaddressed from Round 1)
2. **`resolveDefaultCoveAccountId(cfg) ?? "default"` dead code**: Unchanged. If the SDK helper guarantees a string, the fallback is dead code. If it doesn't, this leads to an unhelpful `"default"` account error.
3. **Unconditional catch in `resolver.resolveTargets`**: Unchanged. `catch { account = undefined; }` still swallows *all* errors, not just expected config misses.
4. **Fragile Non-null Assertions**: Unchanged. `account!.guildId!` and `account!.baseUrl` remain. While technically guarded by the token check, it's unsafe TypeScript practice.
5. **Actionability of Error Messages**: Unchanged. Errors like `cove: account missing token` still lack instructions on how to fix them (unlike the previous versions which told the user what config or env var to set).
6. **Misleading "missing token" from Error Swallowing**: Unchanged. If `resolveAccount` throws because `agentId` is missing, the unconditional catch sets `account = undefined`. This results in a "missing Cove bot token" resolution note, even if the token was actually present.
7. **Missing Multi-account Tests**: Unchanged. No tests were added to verify multi-account resolution or merging.
8. **Test Fixture Shape**: Unchanged. `packages/plugin/src/resolver.test.ts` still tests using the root-level config shape instead of the new `accounts` structure, despite the PR description stating root-level single-account config is removed.

## Conclusion
Please address the remaining 7 escalated issues from Round 1. Code review is a dialogue—if you disagree with a suggestion, please leave a comment explaining why rather than silently ignoring it, so we can clear the block.