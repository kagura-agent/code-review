# Review: PR #381 Round 2 — webhook execute `?wait` + `?thread_id`

## 1. Summary

Round 2 addresses the blocking Round 1 gap. The webhook execute route now rejects locked threads, accepts thread channel types `10`, `11`, and `12`, documents the default response change in-code, and adds the requested six coverage cases for no-wait, wait, thread routing, invalid thread, archived thread, and locked thread. I also re-ran the server test suite (`pnpm -F @cove/server test -- webhooks.test.ts`; Vitest ran all server tests) and it passed: 16 files / 312 tests.

**Rating: ✅ Ready**

## 2. Critical Issues

None.

Round 1 verification:

- ✅ New tests are present in `packages/server/src/__tests__/webhooks.test.ts:128-267` for the six requested cases.
- ✅ Locked-thread validation is present in `packages/server/src/routes/webhooks.ts:159-161`.
- ✅ Thread type validation now accepts `[10, 11, 12]` in `packages/server/src/routes/webhooks.ts:153`.
- ✅ The breaking default response change is called out in `packages/server/src/routes/webhooks.ts:231`.

## 3. Product Impact

The intended Discord-compatible response behavior is now covered: webhook execute defaults to `204 No Content`, while `?wait=true` returns `200` with the created message. Existing internal tests that need the response body have been updated to opt into `wait=true`, which is the right compatibility pattern for this change.

Thread routing now rejects invalid, archived, and locked targets before message creation, so webhooks no longer bypass the regular thread write restrictions.

## 4. Suggestions

1. **Add coverage for type `10` / `12` thread bookkeeping when those types become first-class.** The route accepts types `10`, `11`, and `12`, but `repos.threads.incrementMessageCount()` currently updates only `WHERE type = 11` (`packages/server/src/repos/threads.ts:118-121`). If Cove later stores announcement/private threads as `10` or `12`, webhook posts will be accepted but their `message_count` / `total_message_sent` will not update. Not blocking today if the app only creates type `11` threads, but worth tightening with either broader repo support or an explicit test/decision.

2. **Consider one more negative `thread_id` test for wrong-parent or non-thread channels.** The current invalid-thread test covers a nonexistent id. The route also intentionally hides wrong-parent/non-thread targets as `404 Unknown Channel`; a small regression test would preserve that privacy boundary.

3. **Minor style consistency:** the added route code uses single quotes in a file that mostly uses double quotes. Existing code already has some mixed style, and tests pass, so this is just cleanup if the project wants consistent formatting.

## 5. Positive Notes

- The locked-thread fix mirrors the existing message route behavior and closes the important bypass from Round 1.
- The tests are focused and readable; they exercise both response shape (`204` empty body vs `200` JSON) and thread error cases.
- `targetChannelId` is consistently used for message creation, last-message updates, mention counts, dispatch payload, and thread count updates.
- The implementation remains small and easy to reason about.
