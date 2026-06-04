---
name: code-review
description: "Multi-model PR review — spawn 3 reviewers (GPT-5.5, Claude Opus 4.7, Gemini 3.1 Pro), consolidate findings, optionally post to GitHub."
---

# Code Review

Trigger: any message implying "review this PR" + a PR reference (link, `owner/repo#123`, or just `#N` with context).

## Reviewers

- 🌟 Stella — `default-llm-sg/gpt-5.5`
- 🌠 Nova — `default-llm-sg/claude-opus-4.7`
- 💫 Vega — `default-llm-sg/gemini-3.1-pro-preview`

## Modes

- Default: always post review to PR via `gh pr review --comment`
- Only skip PR posting if user explicitly says "不要贴PR" or "just channel"

## Execution

**Use FlowForge when possible. Manual spawn is acceptable as fallback.**

```bash
# Start workflow (interactive, step-by-step)
flowforge run code-review
# Then advance each step with results:
flowforge advance --result '<step output>'
```

FlowForge is step-by-step — it does NOT accept `--input` for one-shot execution.
The workflow guides: parse → load prompt → spawn reviewers → consolidate → reflect → track.

If manually spawning (e.g. flowforge unavailable), remember to also do:
- Post-review reflection (write to `runs/`)
- **Cross-run pattern check**: read last 5 runs, find repeated suggestions, escalate to prompt
- Update `stats.md` with reviewer performance
- Update `tracking.json`
- Reflection is NOT optional in manual mode — it's where prompt evolution happens

## Review Output

Reviewers write to `reviews/<repo>-<pr>-<name>.md` (e.g. `reviews/cove-175-stella.md`).
Parent reads from files, not session history. Prevents truncation + creates persistent record.

## Re-review Protocol

For Round 2+, include the previous consolidated review in each reviewer's prompt with:
1. Check each previous issue — was it addressed?
2. **Escalation rule**: Unaddressed issues from last round → escalate severity. Never downgrade.
3. **Anti-confirmation bias**: "Your previous acceptance doesn't mean correct. Re-evaluate fresh."
4. Fresh review of any new code.

## Review Standards

- `prompts/<repo>.prompt.md` — project-specific
- `prompts/default.prompt.md` — fallback

## Cross-channel Callers

Other channels request review via `sessions_send`:
```
sessions_send(sessionKey="agent:kagura:discord:channel:1508641076204802159", message="review kagura-agent/cove#96")
```

Results route back to the requesting channel.

## Key Files

- `workflow.yaml` — FlowForge workflow (source of truth)
- `prompts/` — review standard prompts
- `runs/` — run records
- `stats.md` — per-reviewer assessment
- `tracking.json` — PR follow-up tracking
