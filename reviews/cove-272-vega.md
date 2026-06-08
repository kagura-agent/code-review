# Code Review: cove#272 (Round 2)

**Reviewer:** Vega 💫
**Status:** Changes Requested ❌ (Escalation)

## R1 Issues Status

### 🔴 Must Fix (Escalated)
* **❌ Unaddressed: Client non-idempotent count math** — *ESCALATED TO CRITICAL*
  The partial fix only covers the `me` flag (`if (me && reactions[idx].me) return m;`). However, for events from *other* users (`me === false`), it still blindly applies `count + 1`. This means duplicate `MESSAGE_REACTION_ADD` events from reconnects will still inflate counts infinitely for other users' reactions. You must use a set-membership model or have the server broadcast the absolute count.

### 🔴 Must Fix (Resolved)
* **✅ Fixed:** Emoji path param no validation (`emoji.length > 64` check added).
* **✅ Fixed:** Double URL decode removed.
* **✅ Fixed:** Tests added for the new route, repo, and dispatcher.

### 🟡 Should Fix (Escalated)
* **❌ Unaddressed: getUsersForReaction unbounded + N+1** — *ESCALATED TO MUST FIX*
  The `GET /reactions/:emoji` route still loops `userIds.map` and calls `repos.users.getById(uid)` per user. No pagination, meaning a message with 10,000 reactions will execute 10,000 queries in the API route. Fix this by using a SQL `JOIN` on `users` with `LIMIT/OFFSET`.
* **❌ Unaddressed: LRU eviction bug** — *ESCALATED TO MUST FIX*
  `SentMessageTracker.add` still blindly deletes the oldest item if `size >= maxSize`, even if the `id` being added already exists in the set! If `maxSize` is reached and you re-add an existing ID, it will delete the oldest ID and then do nothing (since `Set.add` on existing item is a no-op), continuously shrinking the set capacity by mistake. Fix: `if (this.ids.has(id)) this.ids.delete(id);` before checking size and adding.
* **❌ Unaddressed: React key uses emoji.name only**
  Still using `key={r.emoji.name}`. If multiple emojis have the same name but different IDs (custom emojis), keys will clash.

## Summary
The R1 review was partially ignored. Several architectural issues remain in the state sync and backend query performance. Please address the escalated issues.
