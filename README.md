# Code Review — Channel-as-Service

Multi-model code review service for Kagura's workspace. Send a PR, get 3 independent reviews from different model families.

## How It Works

1. Send a review request to `#code-review` channel with repo and PR number
2. Three reviewers spawn independently:
   - 🌟 **Stella** (GPT-5.5) — fast, concise, catches logic issues
   - 🌠 **Nova** (Claude Opus 4.7) — thorough, strong on architecture and patterns
   - 💫 **Vega** (Gemini 3.1 Pro) — massive context, good for large PRs
3. Each reviewer independently reads the review standard, pulls PR diff, reads source code as needed, and posts their review
4. Results are collected and summarized

## Review Standards

Review prompts live in `prompts/`:
- `prompts/default.prompt.md` — fallback for any project
- `prompts/<project>.prompt.md` — project-specific standards

The reviewer first checks for a project-specific prompt, falls back to default.

## Request Format

Send to `#code-review`:
```
review <owner>/<repo>#<pr_number>
```

Example:
```
review kagura-agent/flowforge#42
```

## Architecture

- **Repo**: `kagura-agent/code-review` (this repo)
- **Channel**: `#code-review` on Discord
- **Pattern**: Channel-as-Service — the channel has its own session, skill, and operational context
- **Models**: 3 different model families for cross-validation
- **Review standard**: per-project with fallback default

## Adding a Project-Specific Review Standard

Create `prompts/<project-name>.prompt.md` with your review criteria. The project name should match the repo name (e.g., `openclaw.prompt.md` for the `openclaw` repo).
