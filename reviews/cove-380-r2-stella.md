# PR #380 Round 2 Re-review — Stella

**PR:** kagura-agent/cove#380 — `feat(plugin): batch merge queued messages into single agent turn (#375)`

## Rating

⚠️ **Needs Changes**

## Validation performed

- Fetched and reviewed the PR diff with `gh pr diff 380 --repo kagura-agent/cove`.
- Built plugin: `pnpm -F openclaw-cove build` ✅
- Typechecked plugin: `pnpm -F openclaw-cove check` ✅
- Ran plugin tests: `pnpm -F openclaw-cove test` ✅ — 64 tests passed.

## Round 1 fix verification

1. **Code quality** — Mostly fixed. JSDoc is restored and the queue API is cleaner. I still see a couple of style nits in newly added code, but nothing blocking by itself.
2. **Constructor** — Fixed. `ChannelMessageQueueOptions` is now a single explicit interface; no `in` check / `as any` compatibility path remains.
3. **Type safety** — Fixed. `batchedMessages?: Message[]` is now part of `DispatchMessageOptions`; no `Object.assign` hack.
4. **Image attribution** — Partially fixed, but still needs one more adjustment. Batched earlier messages now get inline `[image: ...]` markers beside the sending author, which is good. However those same batched image URLs are also added to the global `fullAttachmentUrls` list and then appended again at the end of `bodyForAgent` without author attribution. Primary-message images are also still appended only in the global block rather than rendered next to a sender line when batching is active. This can reintroduce ambiguity and duplicate image references in mixed-author batches.
5. **Error logging** — Fixed. Batch dispatch failures now log batch size and message IDs.

## Blocking finding

### Incomplete image attribution in batched bodies

The current body construction does add inline markers for earlier batched messages, but then appends all image URLs globally afterward. For batched images, that means the agent can see both an attributed inline marker and an unattributed duplicate. In multi-author batches this undermines the attribution fix from Round 1.

Recommended shape:

- Keep `fullAttachmentUrls` for `extraContext.MediaUrls` so the runtime can access all media.
- For `bodyForAgent`, avoid appending earlier batched image URLs again globally once they have been rendered inline with their sender.
- When batching is active, consider rendering the primary message in the same sender-prefixed format too, so all message text/images are consistently attributed.

## Fresh review notes

- The queue batching semantics look sound for the intended personal/small-team scope: messages arriving during an active dispatch are drained on the next pass and sent as one agent turn.
- Durable history for earlier batched messages and batch-failure re-enqueue remain reasonable follow-ups per the re-review instructions.
- No typecheck, build, or test regressions found.
