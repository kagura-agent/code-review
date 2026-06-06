# PR #251 Review — Stella

## 1. Summary

This is a small, additive serialization-layer PR that fills many Discord-compatible default fields on messages, channels, users, guilds, and gateway READY user objects. The overall direction is sound: no schema migration, no new authorization surface, and the defaults (`[]`, `false`, `0`, `null`, `"0"`) are safe for strict Discord-style clients that currently crash or branch on missing properties.

Verification performed locally on `28aaf67`:
- `pnpm -r exec tsc --noEmit` ✅
- `npm test` under Node `v24.14.1` ✅ — 152/152 pass
- Note: tests fail under Node 22 only because the local `better-sqlite3.node` binary was built for Node 24 (`NODE_MODULE_VERSION 137` vs 127), not because of this PR.

## 2. Critical Issues

No code-level critical blockers found.

One release/process blocker to consider before merge:

- **Do not auto-close #201 unless its scope has intentionally been narrowed.** The actual #201 body includes more than author naming/default shape: `message_reference` support and parsing/populating real `mentions`. This PR sets `mentions: []` and confirms responses use `author`, but it does not implement replies or real mention extraction. If merged with `Closes #201`, GitHub will likely close an issue that still has meaningful product/API work remaining. Recommendation: change PR text/title from `Closes #201` to `Refs #201` or split/rename #201 to track only the author-shape portion.

## 3. Suggestions

1. **Hydrate `author.avatar` consistently for persisted messages.**
   - `MessagesRepo.create()` returns the current `author.avatar`, but `toMessage()` always emits `avatar: null` because `MSG_SELECT` only joins `u.username` and `u.bot`.
   - This means the same message can have an avatar on immediate POST / gateway `MESSAGE_CREATE`, then lose it after reload/list/get.
   - Suggested small fix: include `u.avatar AS sender_avatar` in `MSG_SELECT`, add it to `MessageRow`, and set `author.avatar: row.sender_avatar ?? null`.

2. **Add explicit contract assertions for the newly added fields.**
   - Existing `api.test.ts` has a test named `each channel has Discord-required fields`, but it only checks id/name/type/guild_id/position.
   - Please add direct assertions for:
     - Message: `attachments`, `embeds`, `mentions`, `mention_roles`, `pinned`, `tts`, `mention_everyone`, `author.avatar`, `author.discriminator`, `author.global_name`
     - Channel: `permission_overwrites`, `nsfw`, `rate_limit_per_user`
     - Guild/READY: `features`, `user.discriminator`, `user.global_name`
   - This is exactly the kind of compatibility change that benefits from shape/snapshot tests.

3. **Centralize default object construction soon.**
   - The same user defaults (`discriminator: "0"`, `global_name: null`, avatar fallback) now appear in users, members, auth, websocket pre-auth, explicit gateway identify, and messages.
   - It is correct today, but easy to drift. A small serializer/helper (`toDiscordUser`, `withDiscordUserDefaults`, etc.) would make future Discord-field additions less error-prone.

4. **Consider tightening shared types for placeholders.**
   - `attachments`, `embeds`, and `permission_overwrites` are currently `unknown[]`, which is acceptable for a safe-default PR.
   - If external consumers are expected to compile against Cove as a Discord-ish API, follow-up with minimal structural types may improve ergonomics without implementing full semantics.

## 4. Positive Notes

- The change is additive and safely located in response serialization, avoiding unnecessary DB churn.
- The chosen defaults are Discord-compatible enough for strict clients that only require fields to exist.
- `sender` remains internal DB terminology while API responses consistently expose `author`, which is the right boundary.
- Gateway READY user shape was updated alongside REST/auth paths, avoiding a common split-brain bug between REST and websocket clients.
- Local build/typecheck/test pass under the Node version matching installed native dependencies.

## 5. Verdict: ⚠️

Code looks mergeable after minor cleanup, but I recommend fixing the issue-closing metadata for #201 and adding at least a few contract assertions before treating this as complete. The only functional follow-up I would strongly prefer in this PR is consistent message author avatar hydration, because the current POST-vs-GET shape can diverge for users with avatars.
