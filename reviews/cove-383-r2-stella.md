# Review: PR #383 — fix(plugin): thread inherits parent channel's cove.md (#382)

## 1. Summary

This PR changes plugin dispatch so messages sent from thread channels resolve `cove.md` from the parent channel instead of the thread channel. The approach is small and directionally correct: it checks the dispatch channel, detects thread type `11`, uses `parent_id` when available, and falls back defensively to the original channel ID if the lookup fails.

## 2. Critical Issues

### Blocking: behavior change has no test coverage

The diff changes runtime behavior for thread-bound agents: thread messages now receive parent-channel `cove.md` context. Per the review standard, any behavior change must include test coverage. This PR modifies one production file only and adds no tests in the diff.

Required coverage should verify at minimum:

- non-thread channel dispatch still calls `getCoveMd`/channel-file lookup with the original channel ID;
- thread channel dispatch with `parent_id` reads `cove.md` from the parent channel ID;
- `getChannel` failure falls back to the original channel ID without breaking dispatch.

This should be covered in plugin tests around `dispatchMessage` or by extracting the channel-resolution logic into a small helper and testing that helper directly.

## 3. Product Impact

The intended product behavior is valuable: thread agents should inherit channel rules and context from the parent channel, otherwise threads silently miss important `cove.md` instructions.

However, without tests this can regress easily. A future change to channel typing, `parent_id`, or dispatch setup could silently break cove.md injection in threads again, which directly affects agent behavior and channel-level safety/rules.

## 4. Suggestions

- Consider avoiding the magic number `11` by using a shared channel type constant or enum if one exists. This would make the intent clearer and reduce risk if supported thread types expand later.
- Consider logging at debug/warn level when `getChannel` fails before falling back, if the logger supports low-noise diagnostics. Silent fallback is safe for dispatch continuity, but it may make misconfigured REST/auth failures harder to diagnose.
- If `dispatchMessage` is hard to test end-to-end, extract a helper such as `resolveCoveMdChannelId(restClient, channelId)` and unit-test it with mocked `getChannel` behavior.

## 5. Positive Notes

- The implementation keeps non-thread behavior unchanged by defaulting to the original `channelId`.
- The fallback behavior is resilient: inability to fetch channel metadata does not block agent dispatch.
- The fix targets the correct conceptual layer: cove.md context is resolved at dispatch-time before agent prompt construction.

## Rating

⚠️ Needs Changes

The code direction looks correct, but this is a behavior change with no new tests in the PR diff, which is blocking under the stated review standard.
