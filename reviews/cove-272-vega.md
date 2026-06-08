# Code Review: PR #272 (feat: emoji reactions)

**Reviewer:** Vega

Overall, this is a solid PR that implements the reaction feature cleanly. It correctly handles batching to avoid N+1 queries, leverages SQLite's constraints to manage race conditions, and correctly scopes gateway events. 

I've reviewed the code against the key focus areas, and here are my findings:

### 1. Security & Access Control
- **Auth & Channel Checks:** Both the `PUT`, `DELETE`, and `GET` reaction routes correctly retrieve the `userId` from the authenticated session and use `requireGuildMember` to ensure the user has access to the channel before performing any actions. This is secure.

### 2. Race Conditions
- **Concurrent Add/Remove:** Handled perfectly. The backend uses `INSERT OR IGNORE` for adding and checks the `changes > 0` result for both add and remove before dispatching the Gateway events. This ensures that even if a user rapidly clicks a reaction, only one Gateway event is broadcasted, keeping the client state consistent.

### 3. Performance
- **N+1 Queries:** Successfully avoided. The `MessagesRepo.list` method fetches all messages first and then does a single batch query (`reactionsRepo.getForMessages`) using `WHERE message_id IN (...)` with a `GROUP BY`. This is highly efficient and scales well for message lists.

### 4. Gateway Events
- **Scoping:** Events (`MESSAGE_REACTION_ADD`, `MESSAGE_REACTION_REMOVE`) correctly use `channel.guild_id` to broadcast only to members of the specific guild. No data leaks detected.

### 5. Input Validation (Actionable finding)
- **Missing Emoji Length Limit:** In `routes/reactions.ts`, the `emoji` parameter is parsed directly from the URL (`decodeURIComponent(c.req.param("emoji"))`) and inserted into the DB. Because SQLite's `TEXT` type does not enforce length limits, a malicious user could pass an extremely large string (e.g., several megabytes) as the emoji. This would bloat the database and cause massive WebSocket payloads when broadcasted.
  - **Recommendation:** Add a simple length validation in the route handlers before processing:
    ```typescript
    if (emoji.length > 100) return c.body("Emoji too long", 400);
    ```

### 6. DB Schema
- **Migrations & Constraints:** Migration V7 looks good. The composite `PRIMARY KEY (message_id, user_id, emoji)` enforces uniqueness properly. The use of `REFERENCES ... ON DELETE CASCADE` correctly cleans up reactions when a message or user is deleted.

### 7. Other Observations
- **In-Memory Bot Message Tracker (`channel.ts`):** 
  The `SentMessageTracker` used to determine if a message is the bot's "own" message (for reaction notifications) is purely in-memory. If the agent restarts, it will lose track of all messages it previously sent. Consequently, it won't trigger notification events for reactions on pre-restart messages in the `"own"` mode.
  - **Note:** This might be acceptable as a known limitation for ephemeral notification state, but it's worth documenting or considering an API fallback (e.g., fetching the message to check `author.id` if the ID isn't in the set).

---
**Verdict:** Approved with minor changes. Please add a length constraint to the `emoji` parameter in the API routes to prevent abuse.