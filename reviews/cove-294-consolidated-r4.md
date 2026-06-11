# Consolidated Review R4: PR #294 — Webhook Support (Re-review)

**Reviewers:** 🌟 Stella (GPT-5.5) ⚠️ | 🌠 Nova (Claude Opus 4.7) ⚠️ | 💫 Vega (Gemini 3.1 Pro) ⏱️ timed out

---

## Previous Issue Status

| ID | Description | R3 Severity | R4 Status |
|----|-------------|-------------|-----------|
| C1 | Bot-only auth blocks client UI | Critical | ✅ **Resolved** — auth accepts session cookies, non-bot users can manage webhooks |
| C2 | Avatar identity lost on reload | Deferred | ⏸️ **Still deferred** — `sender_name` persists but avatar does not |
| C3 | Deleting webhook corrupts message identity | Critical | ⚠️ **Partially resolved** — see below |
| C4 | Missing negative auth tests | Critical | ✅ **Resolved** — 401 unauth, 404 non-member, 404 cross-guild, 404 wrong token all covered |
| C5 | Missing avatar validation | Critical | ✅ **Resolved** — validated on create/PATCH (max 2048) |
| C6 | Rate-limit O(N) cleanup | Deferred | ⏸️ **Still deferred** |

---

## Remaining Critical Issue

### C3: Historical webhook messages still lose identity after webhook deletion (Stella + Nova)

**The fix prevents a crash but doesn't preserve identity.** The three-branch `toMessage` logic:
1. `webhook_id` set → webhook author ✅
2. `sender` set → normal user author
3. Neither → falls to `{ id: "0", username: "Deleted Webhook" }`

After `ON DELETE SET NULL` zeros `webhook_id`, messages fall to branch 3 even though `sender_name` (the original display name) is **still in the row**. The data is there but never read on this path.

**Minimal fix (both reviewers agree):** Add a fallback branch that reads `sender_name` when it exists:

```ts
} else if (row.sender_name) {
  author = {
    id: "0",
    username: row.sender_name,
    avatar: null,
    bot: true,
    discriminator: "0",
    global_name: null,
  };
} else { /* current "Deleted Webhook" fallback */ }
```

**Plus:** Add a regression test: create webhook → execute → delete webhook → fetch messages → assert author still shows original name, not "Deleted Webhook".

---

## Suggestions (non-blocking)

1. **PATCH route untested** — no test exercises PATCH name/avatar happy path or PATCH by non-member → 404 (Nova)
2. **GET `/guilds/:id/webhooks` untested** — no smoke test for guild-level webhook list (Nova)
3. **`avatar` validation tests missing** — code validates but no test asserts 400 on invalid avatar for create/PATCH (Stella)
4. **Client webhook URL hardcodes `/api/v10/`** — should use `API_PREFIX` from `@cove/shared` for consistency (Nova)
5. **Rate limiter charges quota before body validation** — malformed JSON consumes a slot (Stella)
6. **Content max 4000 vs Discord's 2000** — intentional? Worth a comment (Nova)

---

## Positive Notes

- C1 fix is clean — auth now works for both bot and browser sessions
- C4 negative tests are comprehensive: 401, 404 (non-member with code 10003), cross-guild, wrong token
- C5 avatar validation is properly applied on both create and PATCH
- Token never leaks on list/get/patch/delete — `stripToken` + `toPublicWebhook` consistently applied
- Execute endpoint correctly registered before global auth middleware
- Username override persists on reload via `sender_name` — verified by test
- Migration is additive-only, safe for existing deployments

---

## Overall Verdict: ⚠️ Needs Changes

C1, C4, C5 are properly fixed 👏 Only C3 remains — the fix prevents crashes but still loses identity on webhook deletion. The fix is small (add `sender_name` fallback branch + regression test). After that, this should be ✅ Ready.
