# Consolidated Review — cove#251: fill missing Discord response fields

**Reviewers:** 🌠 Nova (Claude Opus 4.7) — primary review
**Kagura** — diff verification

## Summary

Small, focused PR (59+/11-, 10 files) padding the wire format with Discord-expected default fields. All changes in the serialization layer — no DB schema changes, no behavior changes. 152 tests pass.

## Critical Issues

None. Correctness, security, and performance are all clean.

## Suggestions (non-blocking)

### 🟡 S1: Extract duplicated WS user type (Nova)

The inline type `{ id; username; bot; avatar; discriminator; global_name }` appears **5 times** across `ws/index.ts` and `ws/session.ts`. This is exactly `AuthUser` from `auth.ts` — just import and reuse it. Every future field addition currently costs 5 edits.

### 🟢 S2: No tests for the new defaults (Nova)

No test asserts the serializer now includes `attachments: []`, `pinned: false`, etc. Since the entire point is wire-shape compliance, one `toMatchObject` per `to*` function would lock the contract cheaply.

### 🟢 S3: Defensive `??` in `messages.ts::create` is unreachable (Nova)

`author.discriminator ?? "0"` is unreachable since `AuthUser` now mandates these fields. Trust the types or do it once at the `resolveUser` boundary.

### 🟢 S4: Type inconsistency — `mention_roles: string[]` vs `unknown[]` siblings (Nova)

Pick one style. Either type them all (Discord schemas are public) or relax `mention_roles` to match.

### 🟢 S5: `"0" as const` only in `findByToken` (Nova)

Inconsistent with every other site that uses plain `"0"`. Drop the `as const`.

## Positive Notes

- Right layer — serializer-only, no migration, reversible ✅
- Discord-correct defaults (`discriminator: "0"`, `rate_limit_per_user: 0`, `features: []`) ✅
- #201 verified rather than churned — `toMessage` already maps `sender` → `author` ✅
- Client store updated (`useBotStore.ts`) — optimistic insert didn't get forgotten ✅
- Tight scope — exactly the surface area needed ✅

## Verdict

### ✅ Ready to Merge

Clean, well-scoped feature PR. S1 (extract WS user type) is worth doing in a follow-up to prevent the 5-site duplication from growing. Everything else is polish.
