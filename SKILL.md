# Code Review Service — SKILL.md

Channel-as-service skill for multi-model code review.

## Trigger

This channel uses natural language — no fixed command format required.

User says anything that implies "review this PR" + provides a PR reference (link, `owner/repo#123`, or just a number if context is clear). Auto-detect owner, repo, PR number.

**Mode detection:**
- Default: **report** (summary in channel only)
- User mentions posting to PR ("贴到PR", "post comment", "写到PR上", etc.) → **comment** mode

**Cross-channel callers:** Other channels/skills should send a structured message via `sessions_send`. Format is documented in the Callers section — that's for skill authors, not end users.

## Execution

**Use FlowForge.** Do not manually execute individual steps.

```bash
flowforge run code-review --input '{"owner":"<owner>","repo":"<repo>","pr":<number>,"mode":"report|comment"}'
```

The workflow is defined in `workflow.yaml` in this directory. It handles:
1. Parse request → extract owner/repo/pr/mode
2. Load review standard → project-specific or default prompt
3. Spawn 3 independent reviewers (Stella/Nova/Vega, different model families)
4. Collect and post consolidated summary
5. Post to PR (comment mode only)
6. Reflection — run record, prompt evolution, reviewer assessment, process evolution
7. Register tracking — add to tracking.json for follow-up

**Do not skip steps.** The workflow includes reflection and tracking that are easy to forget when doing it manually — that's the whole point of FlowForge.

## Modes

| Mode | Syntax | Behavior |
|------|--------|----------|
| Report (default) | `review owner/repo#123` | Summary in channel only |
| Comment | `review owner/repo#123 --comment` | Summary + review posted to PR via `gh api` |

Cross-channel callers always get report mode. Comment mode is only available in #code-review directly.

## Callers

**Don't spawn subagents yourself.** Just send a message to this channel:

```
sessions_send(sessionKey="agent:kagura:discord:channel:1508641076204802159", message="review kagura-agent/cove#96")
```

This channel handles everything — FlowForge runs the workflow, spawns reviewers, collects results, posts summary.

## Reviewers

| Reviewer | Model | Provider/ID |
|----------|-------|-------------|
| 🌟 Stella | GPT-5.5 | `default-llm-sg/gpt-5.5` |
| 🌠 Nova | Claude Opus 4.7 | `default-llm-sg/claude-opus-4.7` |
| 💫 Vega | Gemini 3.1 Pro | `default-llm-sg/gemini-3.1-pro-preview` |

## Review Standards

Review prompts live in `prompts/`:
- `prompts/<repo>.prompt.md` — project-specific standards
- `prompts/default.prompt.md` — fallback for any project

## Key Files

- `workflow.yaml` — FlowForge workflow definition (source of truth for steps)
- `prompts/` — review standard prompts
- `runs/` — run records (reflection output)
- `stats.md` — per-reviewer assessment and meta-evolution log
- `tracking.json` — PR follow-up tracking
