# PR #314 Review — 🌠 Nova

**Verdict: ✅ Ready (with one product/security note worth a follow-up)**

## 1. Summary
Two small fixes wired together: the client now sends `bot: true` when creating a bot from the UI (closes #309), and `DELETE /users/:id` is relaxed so that any authenticated user can delete a *bot* target while still blocking human-to-human deletion (closes #311). A new test file gives 5 cases covering the four permission combinations plus 404. Implementation is small, internally consistent, and matches the permission model stated in the PR context ("anyone can delete bots, cannot delete other human users").

## 2. Critical Issues
None blocking.

## 3. Product Impact
- **PR description is stale / inaccurate.** The body says: *"bot users (admin/service accounts) can delete other users, while non-bot users can still only delete themselves."* The actual code (`agents.ts:97–103`) implements the inverse axis: gating is on the **target**'s `bot` flag, not the actor's. The included test `"non-bot user can delete a bot user"` (lines 70–84) confirms a human token successfully deleting a bot returns 204. This matches the task-context permission model, so the **code is correct and the description should be updated** before merge — otherwise reviewers/users will read #311's resolution wrong.
- **Open bot deletion is a footgun worth acknowledging.** Combined with the existing `POST /users` route, which already accepts `bot: true` from any authenticated client without a privilege check (pre-existing, not introduced here), the new rule means any authenticated user can enumerate and delete every bot in the workspace — including service/admin bots. For Cove's current small-team/self-hosted scope this is presumably fine, but if there's ever a notion of "system bots" or bots owned by other users, this rule will need an ownership/role gate. Worth a follow-up issue, not a blocker.

## 4. Suggestions
- **`agents.ts:90`** — `c.get("botUser")` is now read once into `actor` but only `actor.id` is used. Tiny: just keep `const actorId = c.get("botUser").id;` like the sibling routes (`/users/:id/token`, PATCH `/users/:id`) to stay consistent with the surrounding style.
- **`agents.ts:97`** — The non-null assertion `repos.users.getById(id!)` is safe (route param can't be empty), but the same `id!` pattern is repeated three times in this handler. Not worth changing, just calling out for awareness.
- **`POST /users` validation (pre-existing, not in diff)** — `body.bot` is passed through without a `typeof === "boolean"` check. Now that the client actively sets it, a future bug where the field arrives as a string `"true"` would silently flip semantics under SQLite type affinity. Consider adding a boolean check on the create path in a follow-up.
- **Test coverage gap (minor)** — No test for `DELETE /users/@me` resolving via the `@me` branch (`rawId === "@me"`). The existing self-deletion test uses an explicit id. One extra case would lock in that the `@me` shortcut still works for both bots and humans.
- **Naming** — `bot-deletion.test.ts` covers more than bot deletion (it also asserts human-vs-human is forbidden and self-deletion). `user-deletion-permissions.test.ts` would be more discoverable, but rename is optional.

## 5. Positive Notes
- The permission check is structured the right way: explicit self-allow short-circuit, then target lookup, then 404-before-403 (correct order — leaks no information about whether a target exists that you're not allowed to touch, since the 404/403 distinction only applies once you've already failed the self check).
- Negative-path coverage is present: human→human returns 403, nonexistent returns 404. This is exactly the auth-test discipline the review standard calls out as required.
- Tests disable rate limiting explicitly and clean up the env var in `afterEach` — good hygiene.
- `dispatcher?.removeUser(id!)` is preserved on the success path, so WS state stays consistent with the DB after a cross-user delete.
- Client diff is a one-line surgical fix, no incidental churn.
