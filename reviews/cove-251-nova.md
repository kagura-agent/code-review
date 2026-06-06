# 🌠 Nova Review — cove#251

**PR**: feat: fill missing Discord response fields (closes #223, #201)
**Size**: +59 / -11 across 10 files
**Scope**: Serialization-layer defaults; no schema/behavior changes.

## 1. Summary

Adds Discord-compatible default fields to `Message`, `Channel`, `User`, `Guild`, and `CoveAgent` responses so third-party Discord clients (which expect a full schema) don't break on missing keys. All defaults live in the `to*` serializers and the WS gateway user shape. PR author confirms `pnpm -r build`, `tsc --noEmit`, and `npm test` (152/152) pass.

The change is exactly what #223 asks for: padding the wire format without touching DB columns or business logic. Author-vs-sender (#201) is verified-only — no code change needed because `toMessage` already mapped `sender` → `author`.

## 2. Critical Issues

None. No correctness, security, or perf concerns.

## 3. Suggestions

### S1 — Extract the repeated WS user shape (readability)
`packages/server/src/ws/index.ts` and `ws/session.ts` now duplicate the same inline type literal **5 times**:

```ts
{ id: string; username: string; bot: boolean; avatar: string | null; discriminator: string; global_name: string | null }
```

This is `AuthUser` minus nothing — just reuse it (or define a `GatewayUser = Pick<AuthUser, ...>`). Every future field addition currently costs 5 edits and a 6th-edit bug is inevitable.

```ts
// auth.ts already exports AuthUser; just import and use.
import type { AuthUser } from "../auth";
user: AuthUser | null = null;
```

### S2 — Type strictness inconsistency in `shared/src/types.ts`
```ts
attachments: unknown[];
embeds: unknown[];
mentions: unknown[];
mention_roles: string[];   // ← strictly typed
```
`mention_roles` being `string[]` while siblings are `unknown[]` is asymmetric. Either type them all (Discord schemas are public — even a minimal `Attachment { id; filename; url; size }` is enough), or relax `mention_roles` to match. I'd prefer the former; `unknown[]` defeats the purpose of having a typed shared package downstream consumers depend on.

### S3 — Dead-defensive `??` in `messages.ts::create`
```ts
author: {
  ...author,
  avatar: author.avatar ?? null,
  discriminator: author.discriminator ?? "0",
  global_name: author.global_name ?? null,
},
```
Since `AuthUser` now mandates these fields (non-optional), the `??` fallbacks are unreachable per the type system. Either:
- drop the fallbacks (trust the types), or
- if you want runtime hardening, do it once at the `AuthUser` boundary in `auth.ts::resolveUser`, not at every callsite.

Right now it reads as "the author of this code didn't trust their own types," which invites future maintainers to scatter more defensive `??` chains.

### S4 — No tests for the new defaults
PR claims existing 152 tests pass, but no test asserts that the serializer now includes `attachments: []`, `pinned: false`, etc. Since the entire point of this PR is "the wire shape must contain these keys," a regression here would silently re-break Discord clients. One tiny snapshot/shape test per `to*` function would lock the contract:

```ts
expect(toMessage(row)).toMatchObject({
  attachments: [], embeds: [], mentions: [], mention_roles: [],
  pinned: false, tts: false, mention_everyone: false,
});
```

Cheap insurance; high signal.

### S5 — `discriminator: "0" as const` only in one spot
`users.ts::findByToken` uses `"0" as const` while every other site uses plain `"0"`. The `as const` is unnecessary here because the target type is `string`, not `"0"`. Drop it for consistency.

## 4. Positive Notes

- ✅ **Right layer**: serializer-only, no DB migration — keeps the change reversible and low-risk.
- ✅ **Discord-correct defaults**: `discriminator: "0"` matches Discord's post-username-update constant; `rate_limit_per_user: 0`, `nsfw: false`, `features: []` all match Discord's "absent ⇒ benign" semantics.
- ✅ **Verification rather than churn for #201**: PR author actually checked that `sender` → `author` mapping already existed and resisted the urge to "fix" working code. That's the correct call.
- ✅ **Tight scope**: 10 files, +59/-11 — exactly the surface area needed.
- ✅ **Client store updated too** (`useBotStore.ts`) — the optimistic insert path didn't get forgotten, which is the usual bug in this kind of "add a required field" PR.

## 5. Verdict

✅ **Approve** — merge after addressing S1 (extract the duplicated WS user type) and S4 (one shape test per serializer). S2/S3/S5 are polish, can land in a follow-up.

The PR does exactly what it advertises, at the right layer, with the right defaults. The only real risk is the inline-type duplication in the WS layer becoming a maintenance trap; fix that once and this becomes a textbook small-feature PR.

— 🌠 Nova
