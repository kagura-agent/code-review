# Code Review — Channel-as-Service

Multi-model code review service for Kagura's workspace. Send a PR, get 3 independent reviews from different model families.

## How It Works

1. Send a review request to `#code-review` channel:
   - `review <owner>/<repo>#<pr_number>` — get review summary in channel
   - `review <owner>/<repo>#<pr_number> --comment` — also post comments to the PR on GitHub
2. This channel spawns 3 independent reviewers:
   - 🌟 **Stella** (GPT-5.5) — fast, concise, catches logic issues
   - 🌠 **Nova** (Claude Opus 4.7) — thorough, strong on architecture and patterns
   - 💫 **Vega** (Gemini 3.1 Pro) — massive context, good for large PRs
3. Each reviewer independently reads the review standard, pulls PR diff, reads source code as needed
4. Results are collected and summarized in this channel
5. With `--comment`: a consolidated review is also posted directly to the PR via `gh pr review`

## Modes

| Mode | Syntax | Behavior |
|------|--------|----------|
| Report (default) | `review owner/repo#123` | Summary in channel only |
| Comment | `review owner/repo#123 --comment` | Summary + PR comment |

Cross-channel callers always get report mode. Comment mode is only available in #code-review directly.

## Callers

**Don't spawn subagents yourself.** Just send a message to this channel:

```
sessions_send(sessionKey="agent:kagura:discord:channel:1508641076204802159", message="review kagura-agent/cove#96")
```

This channel handles everything — spawning reviewers, collecting results, posting the summary.

## Review Standards

Review prompts live in `prompts/`:
- `prompts/default.prompt.md` — fallback for any project
- `prompts/<project>.prompt.md` — project-specific standards

The reviewer first checks for a project-specific prompt, falls back to default.

## Models

| Reviewer | Model | Provider/ID | Context |
|----------|-------|-------------|---------|
| 🌟 Stella | GPT-5.5 | `default-llm-sg/gpt-5.5` | 1.05M |
| 🌠 Nova | Claude Opus 4.7 | `default-llm-sg/claude-opus-4.7` | 1M |
| 💫 Vega | Gemini 3.1 Pro | `default-llm-sg/gemini-3.1-pro-preview` | 1M |

## Adding a Project-Specific Review Standard

Create `prompts/<project-name>.prompt.md` with your review criteria. The project name should match the repo name (e.g., `openclaw.prompt.md` for the `openclaw` repo).
