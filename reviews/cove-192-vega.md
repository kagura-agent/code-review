## Review: PR #192 (cove) - Vega - Round 4

**R3 Findings Status:**

- ✅ **N1: Own-message unread** — Fixed. Validated that sending a message properly syncs local and server read states.
- ✅ **N2 (ESCALATED): Stale MESSAGE_ACK dispatch** — Fixed. The server `PUT /ack` endpoint in `routes/messages.ts` now uses short-circuit evaluation (`repos.readStates.set(...) && dispatcher?.messageAck(...)`). The event is only broadcast to client sessions if the DB actually performed the update, successfully shielding the client from stale downgrade acks.
- ✅ **N3 (ESCALATED): No MESSAGE_ACK dispatch on implicit self-ack** — Fixed. In `routes/messages.ts` during message creation, the server now dispatches a `MESSAGE_ACK` to the sender after implicitly setting the read state, ensuring secondary devices correctly clear their unread indicators.
- 🟡 **Edge case: Deleted latest message marks channel unread** — Not Fixed. `useReadStateStore.ts` continues to use a strict equality check (`s.last_read_message_id !== s.last_message_id`). If the absolute latest message in a channel is deleted, the server's `getAllForUserWithLastMessage` returns the ID of the older message, causing a mismatch with the user's `last_read_message_id` (which might still point to the deleted message). This mismatch incorrectly sets the channel to an unread state on reload.

**New Issues:**
None.

**Summary & Verdict**:
The major blocking issues regarding gateway dispatch synchronization (N2 and N3) have been perfectly addressed. The monotonicity guard and dispatch mechanisms are now robust. The only remaining issue is the edge case involving deleted messages marking channels as unread on reload. While this isn't a showstopper for the feature's core functionality, it represents a persistent UI state glitch. 

Given that the escalated blockers are fixed, this PR is functionally ready for merge, with a strong recommendation to either fix the deleted message equality check in a fast-follow PR or address it here if time permits (e.g., by comparing message timestamps instead of strict ID equality, or calculating the unread boolean server-side).

**Rate**: ⚠️ Needs Changes (for the remaining edge case, though mergable if accepted as known tech debt)
