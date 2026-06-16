# PR #374 Round 4 Re-review — Stella

## Rating: ✅ Ready

I re-reviewed the Round 4 diff for `kagura-agent/cove#374` and verified the two Round 3 follow-ups.

## Round 3 fix verification

1. **Attachment URL path under `API_PREFIX` — fixed**
   - Stored attachment URLs are now generated as `API_PREFIX + '/attachments/...'`, so they resolve as `/api/v10/attachments/...`.
   - The static attachment route is registered at `API_PREFIX + "/attachments/:guildId/:channelId/:attachmentId/:filename"`.
   - This should work with the Vite dev proxy and same-origin cookie auth for `<img src=...>`.

2. **`c.get('botUser')` — confirmed correct**
   - `packages/server/src/auth.ts` defines `AppEnv` as `Variables: { botUser: AuthUser }`.
   - `requireAuth()` sets `c.set("botUser", result.user)`.
   - Existing routes consistently use `c.get("botUser")`, so the attachment route is aligned with the codebase.

## Fresh review notes

No blocking regressions found in the new Round 4 changes. The attachment route is authenticated, checks guild membership via the channel, applies path sanitization plus `path.relative()` boundary validation, and returns inline content disposition only for recognized image extensions.

The remaining items I noticed are appropriate non-blocking hardening/follow-ups for this small-team project:

- Validate image magic bytes rather than trusting browser-provided MIME type.
- Clean up orphaned files if DB insertion or later message creation fails after `storeAttachment()` succeeds.
- Consider lower-casing extensions when serving files so `.PNG`/`.JPG` render inline consistently.
- Consider reusing the channel permission helper for attachment reads if bot channel-level visibility should match message-read visibility exactly.

## Verification run

- `pnpm -F @cove/server build` ✅
- `pnpm -F @cove/client build` ✅
- `pnpm -F @cove/server test -- --reporter=dot` ✅ — 16 files / 304 tests passed

## Conclusion

✅ Ready to merge.