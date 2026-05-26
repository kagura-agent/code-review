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
PROMPT_FILE="~/.openclaw/workspace/code-review/prompts/${repo}.prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
  PROMPT_FILE="~/.openclaw/workspace/code-review/prompts/default.prompt.md"
fi
```
Read the prompt file content — this is the review standard.

### 3. Spawn Three Reviewers

Spawn 3 independent subagents, each with a different model. **Do NOT pre-feed the diff** — let each reviewer pull it themselves via `gh`.

Each reviewer gets the same task template:

```
You are a code reviewer. Your task:

1. Run `export https_proxy=http://127.0.0.1:1083` first for GitHub access
2. Run `gh pr view <owner>/<repo>#<pr_number>` to understand the PR
3. Run `gh pr diff <owner>/<repo>#<pr_number>` to see the changes
4. If the diff is large, also read relevant source files via gh api or clone
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
| Reviewer | Model |
|----------|-------|
| 🌟 Stella | `default-llm-sg/gpt-5.5` |
| 🌿 Nova | `default-llm-sg/claude-opus-4.7` |
| 🔥 Vega | `default-llm-sg/gemini-2.5-pro` |

Use `sessions_spawn` with `mode: "run"` for each. All 3 are independent — spawn them in parallel. Then `sessions_yield` to wait for results.

### 4. Collect Results

After all 3 complete, read their session histories and summarize:
- Consensus issues (found by 2+ reviewers) — high confidence
- Unique findings — worth checking but may be false positives
- Overall verdict (if all say ✅, it's probably good)

### 5. Post Summary

Post the consolidated review summary to this channel. Format:

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

### Vega 🔥 (Gemini 2.5 Pro)
Rating: ✅/⚠️/❌
Key points: ...

### Overall Verdict: ✅/⚠️/❌
```

## Notes

- Each reviewer is isolated — they cannot see each other's reviews
- Large PRs: Stella (400k context) handles most. Nova (200k) may need to be selective. Vega (1M) handles everything
- The review standard file is the single source of truth for what to check
- Reviewers produce text output only. They do NOT post `gh pr review` — the human decides whether to submit the review to GitHub
