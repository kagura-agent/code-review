# 🌠 Nova — Round 2 Review: PR #413 (kagura-agent/cove)

**PR:** fix(ci): shell injection in notification workflows (#393)
**Round:** 2 (re-review after R1 fixes)
**Files reviewed:**
- `.github/workflows/notify-cove.yml`
- `.github/workflows/notify-issue-close.yml`
- `docs/specs/393-shell-injection-fix.md`

---

## 1. R1 Issue Tracker

### ✅ R1-1 (CRITICAL/blocker) — Static `EOF` heredoc delimiter
**Status:** ✅ **Fixed**

`notify-issue-close.yml` now generates a per-run random delimiter:
```
DELIMITER=$(openssl rand -hex 8)
echo "message<<$DELIMITER" >> "$GITHUB_OUTPUT"
echo "$MSG" >> "$GITHUB_OUTPUT"
echo "$DELIMITER" >> "$GITHUB_OUTPUT"
```
(see `notify-issue-close.yml` lines ~38–41 in the new file)

A 16-hex-char delimiter (64 bits of entropy) is well above the bar for "untrusted issue title cannot contain it." This closes the GITHUB_OUTPUT injection vector. Blocker resolved.

### ✅ R1-2 (Suggestion) — Spec doc "After" example didn't match implementation
**Status:** ✅ **Fixed**

`docs/specs/393-shell-injection-fix.md` "After" block now mirrors the actual yml: random delimiter, `LABEL`/`ASSIGNEE` env vars added, the consolidated case statement, and the `WEBHOOK_URL` empty-check + `curl -sfS`. Spec and code are in sync.

### ✅ R1-3 (Suggestion) — `curl -sf` → `curl -sfS`
**Status:** ✅ **Fixed**

Both workflows use `curl -sfS -X POST ...`. Errors are now surfaced (`-S` un-silences error output) while keeping progress quiet (`-s`) and propagating HTTP failures (`-f`). Good.

### ✅ R1-4 (Suggestion, Nova-specific) — WEBHOOK_URL validation
**Status:** ✅ **Fixed**

Both workflows guard the secret:
```
if [ -z "$WEBHOOK_URL" ]; then echo '::warning::WEBHOOK_URL is empty, skipping'; exit 0; fi
```
This prevents a `curl -sfS -X POST ""` failure from masking the real problem (missing secret in a fork / new repo / accidental rotation). Emitting `::warning::` makes it visible on the Actions UI without failing the workflow. Nice touch.

> Note on R1's "comment on event filtering logic" suggestion — that was a documentation nit (no `if:` filter to drop spammy `labeled`/`unlabeled`/`assigned` events). The workflow still fires on every action, which is intentional per existing design; not blocking and not regressed by this PR.

---

## 2. New Issues (introduced or remaining)

### 🟢 Nit — `LABEL`/`ASSIGNEE` env vars are always set
`notify-issue-close.yml` exports `LABEL` and `ASSIGNEE` from `github.event.label.name` / `github.event.assignee.login` regardless of `action`. For non-label/assign events these resolve to empty strings, which is harmless (the `case` arms that use them are not entered). No action needed — flagging only for awareness.

### 🟢 Nit — `printf '%s\n%s\n%s'` with multiline `TITLE`
If an issue title ever contains a real newline (very rare; GitHub generally strips them), `MSG` will have extra lines. This is fully handled by the random-delimiter heredoc on the output side and by `jq --arg` on the send side. Cosmetic only — the produced Cove message could look slightly weird but cannot break parsing.

### 🟢 Confirmed safe — `env: MSG: ${{ steps.msg.outputs.message }}` re-injection
The "Send to Cove" step pulls the previously-stored message back via `${{ steps.msg.outputs.message }}` into `env: MSG:`. Because the substitution lands in a YAML `env:` value (not inside a `run:` script line) and is then read as `"$MSG"` by bash + `jq --arg`, backticks / `$(...)` / quotes inside MSG are inert. This is the GitHub-recommended pattern and is implemented correctly.

### 🟢 Confirmed safe — `jq -nc --arg content "$MSG"` JSON build
Replaces the old `-d "{\"content\": \"...\"}"` string concat. `jq --arg` does proper JSON escaping (quotes, backslashes, control chars), so any payload including `"`, `\`, newlines, or unicode lands in valid JSON. Correct fix.

### 🟢 Confirmed safe — `curl ... -d "$PAYLOAD"`
`$PAYLOAD` is a well-formed JSON string from `jq -c`. Quoting prevents word-splitting. Fine.

No new issues of Major or Critical severity.

---

## 3. Summary & Verdict

| R1 Issue | Severity | Status |
| --- | --- | --- |
| 1. Static `EOF` delimiter (GITHUB_OUTPUT injection) | 🔴 CRITICAL | ✅ Fixed (random hex-8) |
| 2. Spec "After" out of sync | 🟡 Suggestion | ✅ Fixed |
| 3. `curl -sf` → `curl -sfS` | 🟡 Suggestion | ✅ Fixed |
| 4. WEBHOOK_URL non-empty check | 🟡 Suggestion | ✅ Fixed |

All four R1 items — including the lone blocker — are addressed. The new code uses the GitHub-recommended pattern end-to-end:

1. Untrusted GitHub event fields → `env:` (no `${{ }}` inside `run:` bodies).
2. JSON payloads → `jq --arg` (no manual string concatenation).
3. Multiline step outputs → random heredoc delimiter.
4. Secret + transport hardening → empty-secret guard + `curl -sfS`.

Shell injection surface is closed. Spec doc accurately documents the implementation.

### Verdict: ✅ **Ready to merge**

Recommended (non-blocking) follow-ups for a future PR:
- Add the verification test described in the spec (`` `whoami` $(echo hi) `` title) as a one-shot smoke run after merge to confirm in CI.
- Consider an `if:` filter on `notify-issue-close.yml` to skip `labeled`/`unlabeled` events if Cove channel noise becomes an issue (product call, not security).

— 🌠 Nova
