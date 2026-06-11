# Consolidated Review R5: PR #294 — Webhook Support (Final Re-review)

**Reviewers:** 🌟 Stella (GPT-5.5) ✅ | 🌠 Nova (Claude Opus 4.7) ✅ | 💫 Vega (Gemini 3.1 Pro) ❌ (stale — reviewed old diff, findings identical to R3)

---

## Previous Issue Status

| ID | Description | R4 | R5 |
|----|-------------|----|----|
| C1 | Auth blocks client UI | ✅ | ✅ Confirmed |
| C2 | Avatar persistence on reload | ⏸️ Deferred | ⏸️ Deferred — Nova recommends updating Discord compat table to note `avatar_url` is "accepted, not rendered" |
| C3 | Deletion corrupts message identity | ⚠️ Partial | ✅ **Resolved** — `toMessage` now reads `sender_name` on fallback path |
| C4 | Negative auth tests | ✅ | ✅ Confirmed |
| C5 | Avatar validation | ✅ | ✅ Confirmed |
| C6 | Rate-limit cleanup | ⏸️ Deferred | ⏸️ Deferred |

---

## C3 Verification (Stella + Nova both confirmed)

The fix is correct:
- `toMessage` fallback branch now uses `row.sender_name ?? "Deleted Webhook"` when both `webhook_id` and `sender` are null
- Regression test covers: create webhook → execute with `username: "Custom Name"` → delete webhook → fetch messages → assert `author.username === "Custom Name"` and `author.bot === true`
- Anti-confirmation-bias scenarios verified by Nova: default name (no override), null sender_name, FK bypass — all safe

## Vega Note

Vega's review is identical to its Round 3 output (still flags C1 bot-only auth, C3 deletion identity, C4 missing tests, C5 missing validation as critical). These were all fixed in R4. Vega appears to have reviewed a cached/stale diff. Discounting this review for the consolidated verdict.

---

## Suggestions (non-blocking)

1. **Update Discord compat table** — `avatar_url` is claimed "Aligned" but isn't persisted; mark as "accepted, not yet rendered" (Nova)
2. **`webhookAvatar` param unused** — `createFromWebhook` accepts it but doesn't insert it; either wire it or drop from signature (Nova)
3. **Add `author.id === "0"` assertion** in deletion test for sentinel documentation (Nova)
4. **Code comment on author.id drift** — after deletion, id changes from webhook_id to "0"; worth a comment (Nova)

---

## Overall Verdict: ✅ Ready

All blocking issues (C1–C5) are resolved. C2 and C6 remain as known deferred items. 2/3 reviewers approve (Vega stale). Tests pass (195 tests). PR is ready to merge.
