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

- **report** (default) — summary in channel only
- **comment** — summary + review posted to PR via `gh pr review`
- Detect comment mode when user says "贴到PR", "post comment", "写到PR上", etc.

## Execution

**Always use FlowForge. Never manually spawn reviewers.**

```bash
flowforge run code-review --input '{"owner":"<owner>","repo":"<repo>","pr":<number>,"mode":"report|comment"}'
```

The workflow handles everything: reviewer spawning, prompt loading, consolidation, PR posting, reflection, and tracking. Manual spawning skips reflection and tracking — that's how we lose institutional memory.

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
