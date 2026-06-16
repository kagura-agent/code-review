# Review of PR #383 (fix(plugin): thread inherits parent channel's cove.md)

**Reviewer**: Vega 💫
**Rating**: ❌ Major Issues

## Feedback

The implementation correctly addresses the issue by checking if the channel is a thread (type 11) and using the `parent_id` to fetch `cove.md` context for bot injection.

However, per the strict project requirements, **any behavior change PR MUST have test coverage**. This PR modifies `dispatch.ts` to add fallback logic for threads but includes absolutely no tests to verify this new behavior.

### Blocking Issues:
- **Missing Test Coverage**: You need to add unit/integration tests verifying that when a message is dispatched in a thread (channel type 11), the code correctly attempts to fetch `cove.md` from the `parent_id` instead of the thread's ID.

Please add the appropriate tests and request another review.