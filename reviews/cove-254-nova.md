# PR #254 Review — refactor: remove hardcoded guild ID from plugin

Reviewer: 🌠 Nova
Repo: kagura-agent/cove
Scope: 4 files, +10 / −4

## Summary
Surgical refactor that stops the plugin from pretending every Cove instance is named `"cove"`. Three coordinated moves:
1. `CoveAccount.guildId` widened from `string` → `string | null` (config override still wins; absent config = `null`).
2. `CoveRestClient.getChannels(guildId)` loses its `= "cove"` default, forcing callers to be explicit.
3. `CoveGatewayClient` learns to capture `guilds` from the `READY` payload and expose them as `public guilds: Guild[]`.

The PR matches its title: it removes a hard-coded assumption. It does **not** yet wire the captured guilds into anything that consumes `account.guildId`. That's fine as a staged refactor, but worth being explicit about (see suggestions).

## Critical Issues
None. I traced every existing consumer.

`account.guildId` is referenced only at the assignment site in `channel.ts:131` — no other file in `packages/plugin/src/**` reads it. `getChannels()` has zero call sites in the repo (plugin or otherwise). So the "does `null` propagate to a guild-required API call?" concern resolves to: **there is no live propagation path today.** No regression risk on this PR.

## Suggestions

### S1 — `guilds` field on the gateway client is currently write-only (minor)
`CoveGatewayClient.guilds` is populated on `READY` but nothing reads it (no consumer in plugin, no event emit, no getter on `CoveAccount`). That's the whole point of the PR ("discover guilds from READY instead of hardcoding"), but right now it's wiring without a load.

Two low-cost follow-ups would make this more than scaffolding:
- Emit a typed event, e.g. `gatewayClient.emit("guildsReady", data.guilds)`, so `startAccount` can hydrate `account.guildId` when config didn't provide one (`account.guildId ??= guilds[0]?.id`).
- Or expose a `getDefaultGuildId()` helper on the client used by future REST callers.

Without either, the next person who needs a guild ID will still reach for a literal. Document the intent or land the consumer in the same PR if practical.

### S2 — `READY` payload typing duplicates `CoveReadyData` shape (nit)
The inline `payload.d as { user: …; guilds?: Guild[]; session_id: string }` cast is now a 3-field shape. If `@cove/shared` exports a `ReadyEventData` (or similar), prefer importing it; otherwise add one. Keeps protocol drift in one place.

### S3 — `guilds?: Guild[]` optional + `?? []` (defensive, fine — call it out)
`data.guilds ?? []` silently swallows servers that don't send guilds in READY. For a Discord-compatible protocol that's probably intentional (older servers, partial implementations), but worth a one-line comment so the next reader doesn't tighten the type and break compatibility.

### S4 — `getChannels(guildId: string)` has no test coverage for the new contract (minor)
The PR removes a default parameter — a small but real API break for any external consumer. There are no tests asserting that callers pass a guild ID, and the plugin itself never calls `getChannels`. If this client is published/consumed externally, consider a CHANGELOG note flagging the breaking signature change. If it's strictly internal, this is purely informational.

### S5 — Config key `channels.cove.allowFrom` still hardcodes `"cove"` (out of scope, observed)
`channel.ts:167` still references `"channels.cove.allowFrom"` as a hint path. Not introduced by this PR and not what #237 is about, but if "remove hardcoded cove identifiers" is the broader direction, that one survives. PR body explicitly carves this out ("plugin ID, config key, channel/provider/surface identifiers — these are plugin names, not guild IDs") — call honored, just flagging for the trail.

## Positive Notes
- **Tight blast radius.** 10/4 across 4 files, all in `packages/plugin/src`. Easy to review, easy to revert.
- **Honest type change.** `string | null` reflects reality (config may be absent) instead of papering over with a sentinel `"cove"`. The JSDoc on `CoveAccount.guildId` clearly explains the two sources.
- **PR body is excellent.** Explicit "Not changed" section pre-empts exactly the scope-creep question I would have asked (plugin ID vs guild ID).
- **Closes #237 cleanly** — issue is about misuse of `"cove"` as a guild ID; this rips it out of both the type system and the REST default.
- 152 tests still pass per PR body; nothing in the diff suggests test changes were needed (zero existing consumers exercise the changed paths).

## Verdict
✅ **Approve.**

Correct, narrowly scoped, type-honest, no regression risk because the widened field has no downstream readers yet. The only real ask is **don't let this PR stand alone for long** — `gatewayClient.guilds` is dead weight until something consumes it (S1). Ship it, then immediately follow up with a PR that uses the captured guild ID where `account.guildId` is `null`, or this refactor never finishes paying off.
