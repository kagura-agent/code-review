# Code Review Service — SKILL.md

Channel-as-service skill for multi-model code review.

## Trigger

When a message arrives in this channel matching:
```
review <owner>/<repo>#<pr_number>
```

## Execution

**Use FlowForge.** Run `workflow.yaml` — it enforces all steps including reflection and tracking.

```
flowforge run workflow.yaml --input "review <owner>/<repo>#<pr_number>"
```

Steps (enforced by workflow, do not skip any):
1. **parse_request** — extract owner/repo/pr, validate format
2. **load_prompt** — load project-specific or default review standard
3. **spawn_reviewers** — 3 parallel subagents (Stella/Nova/Vega), each pulls diff independently
4. **post_summary** — consolidate reviews, post to channel
5. **reflection** — write run record, check for prompt evolution opportunities, update prompt if needed
6. **register_tracking** — add PR to `tracking.json` for human-review follow-up

### Reviewer Config

| Reviewer | Model | Provider/ID |
|----------|-------|-------------|
| 🌟 Stella | GPT-5.5 | `default-llm-sg/gpt-5.5` |
| 🌠 Nova | Claude Opus 4.7 | `default-llm-sg/claude-opus-4.7` |
| 💫 Vega | Gemini 2.5 Pro | `default-llm-sg/gemini-2.5-pro` |

All three support 1M token context.

### Reviewer Task Template

```
You are a code reviewer. Your task:

1. Read the review standard below
2. Run `gh pr view <owner>/<repo>#<pr_number>` to understand the PR
3. Run `gh pr diff <owner>/<repo>#<pr_number>` to see the changes
4. If the diff is large, also read relevant source files in the repo at ~/repos/forks/<repo> or clone if needed
5. Apply the review standard and write your review

## Review Standard
<insert prompt content>

## PR Details
- Repository: <owner>/<repo>
- PR Number: #<pr_number>

Write your review. Be specific with file names and line numbers.
At the end, rate: ✅ Ready / ⚠️ Needs Changes / ❌ Major Issues
```

### Summary Format

```
## Code Review: <owner>/<repo>#<pr_number>

### Consensus (2+ reviewers agree)
- ...

### Stella 🌟 (GPT-5.5)
Rating: ✅/⚠️/❌
Key points: ...

### Nova 🌠 (Claude Opus 4.7)
Rating: ✅/⚠️/❌
Key points: ...

### Vega 💫 (Gemini 3.1 Pro)
Rating: ✅/⚠️/❌
Key points: ...

### Overall Verdict: ✅/⚠️/❌
```

### PR Tracking (cron-driven)

A cron job periodically checks `tracking.json` for PRs we've reviewed:
- Pulls human review comments via `gh pr reviews` and `gh pr comments`
- Compares human findings vs our findings → identifies prompt blind spots
- Updates run records with `ground_truth` data
- This is the highest-value evolution signal

## Notes

- Each reviewer is isolated — they cannot see each other's reviews
- All three reviewers support 1M token context — large PRs are handled natively
- The review standard file is the single source of truth for what to check
- Reviewers should NOT post `gh pr review` — they only produce text output. The human decides whether to submit the review to GitHub
