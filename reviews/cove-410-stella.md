**Summary** — The PR moves final fresh sends onto `sendDurableMessageBatch` and adds focused tests for long final replies, long-edit fallback, and preview truncation. The chunking direction is right and avoids custom splitting, and the session key matches the existing Cove inbound route key pattern. However, the new integration does not actually verify the durable batch outcome before treating delivery as successful, and it still deletes the existing draft before the replacement has been confirmed, so the original “silent deletion” class can still happen on durable-send failure.

**Critical Issues** — Must fix before merge

1. `freshSend` deletes the draft and ignores `sendDurableMessageBatch` failure/partial-failure status (`packages/plugin/src/dispatch.ts`, new `freshSend` body). `sendDurableMessageBatch` returns an explicit result (`sent`, `suppressed`, `partial_failed`, `failed`) rather than guaranteeing a thrown error for failed delivery. This code awaits it but discards the result, so a `failed` result is treated as success by the finalizer. Combined with deleting `draftMessageId` before the batch send, a failed durable send can still remove the user-visible draft and leave no final message — the same data-loss/silent-delete failure mode described in the PR. Please check the returned status and only clean up the old draft after successful replacement delivery, or otherwise preserve/restore the draft on failed delivery. Add a behavioral test where `sendDurableMessageBatch` returns `{ status: "failed", ... }` and verify the draft is not silently deleted / finalization does not report success.

**Suggestions** — Non-blocking

- Consider asserting the `session` argument in the long-message tests. The runtime value `agent:${targetAgent}:cove:group:${channelId}` matches the inbound `SessionKey`/`routeSessionKey` shape, but a regression here would break hook correlation and the current tests don’t lock it down.
- The preview truncation uses `trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - 1) + "…"`, which is correct for the 4000-character boundary. A test with text that differs only after the truncation boundary would help document the harmless-but-possible repeated identical preview edits during streaming.

**Positive Notes**

- Good choice to delegate splitting to the SDK’s registered outbound adapter (`textChunkLimit: 4000`, markdown chunker) instead of introducing Cove-specific chunking logic.
- `editFinal` correctly avoids attempting an over-limit direct edit, so long final replies no longer hit the known 400 path.
- The added tests cover the key happy-path chunking behavior and the exact 4000-character preview boundary.

Rate: ⚠️ Needs Changes
