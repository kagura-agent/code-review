# Code Review Service — SKILL.md

Channel-as-service skill for multi-model code review.

## Trigger

When a message arrives in this channel matching:
```
review <owner>/<repo>#<pr_number>
```

## Execution Steps

### 1. Parse Request
Extract `owner`, `repo`, and `pr_number` from the message.

### 2. Load Review Standard
```bash
# Check for project-specific prompt first
PROMPT_FILE="prompts/${repo}.prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
  PROMPT_FILE="prompts/default.prompt.md"
fi
```
Read the prompt file content — this is the review standard.

### 3. Spawn Three Reviewers

Spawn 3 independent subagents, each with a different model. **Do NOT pre-feed the diff** — let each reviewer pull it themselves via `gh`.

Each reviewer gets the same task template:

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

Spawn config:
| Reviewer | Model | Provider/ID |
|----------|-------|-------------|
| 🌟 Stella | GPT-5.5 | `default-llm-sg/gpt-5.5` |
| 🌿 Nova | Claude Opus 4.7 | `default-llm-sg/claude-opus-4.7` |
| 🔥 Vega | Gemini 3.1 Pro | `default-llm-sg/gemini-3.1-pro` |

Use `sessions_spawn` with `mode: "run"` for each. All 3 are independent — spawn them in parallel.

### 4. Collect Results

After all 3 complete, summarize:
- Consensus issues (found by 2+ reviewers) — high confidence
- Unique findings — worth checking but may be false positives
- Overall verdict (if all say ✅, it's probably good)

### 5. Post Summary

Post the consolidated review summary back to the channel. Format:

```
## Code Review: <owner>/<repo>#<pr_number>

### Consensus (2+ reviewers agree)
- ...

### Stella 🌟 (GPT-5.5)
Rating: ✅/⚠️/❌
Key points: ...

### Nova 🌿 (Claude Opus 4.7)
Rating: ✅/⚠️/❌
Key points: ...

### Vega 🔥 (Gemini 3.1 Pro)
Rating: ✅/⚠️/❌
Key points: ...

### Overall Verdict: ✅/⚠️/❌
```

## Notes

- Each reviewer is isolated — they cannot see each other's reviews
- Large PRs: Stella (32k context) may need to be selective about what to read. Nova (200k) and Vega (1M) handle large diffs better
- The review standard file is the single source of truth for what to check
- Reviewers should NOT post `gh pr review` — they only produce text output. The human decides whether to submit the review to GitHub
