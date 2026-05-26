# Code Review Service — SKILL.md

Channel-as-service skill for multi-model code review.

## Trigger

When a message arrives in this channel matching:
```
review <owner>/<repo>#<pr_number>              ← report mode (default)
review <owner>/<repo>#<pr_number> --comment     ← comment mode (write to PR)
```

### Modes
- **Report mode** (default): Return review summary to channel/caller. No GitHub side effects.
- **Comment mode** (`--comment`): Post consolidated review as a PR review comment via `gh pr review`. Each finding tagged with which reviewer(s) found it.

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

IMPORTANT: Do NOT post comments or reviews to GitHub. Do NOT run `gh pr review` or `gh pr comment`. Your output is text only — write your review as your final message. The orchestrator handles delivery.

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
| 🌠 Nova | `default-llm-sg/claude-opus-4.7` |
| 💫 Vega | `default-llm-sg/gemini-3.1-pro-preview` |

Use `sessions_spawn` with `mode: "run"` and `runTimeoutSeconds: 0` (no timeout — reviews can take 5+ minutes) for each. All 3 are independent — spawn them in parallel. Then `sessions_yield` to wait for results.

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

### Nova 🌠 (Claude Opus 4.7)
Rating: ✅/⚠️/❌
Key points: ...

### Vega 💫 (Gemini 3.1 Pro)
Rating: ✅/⚠️/❌
Key points: ...

### Overall Verdict: ✅/⚠️/❌
```

## Notes

- Each reviewer is isolated — they cannot see each other's reviews
- All three reviewers have ~1M context windows (GPT-5.5: 1.05M, Claude Opus 4.7: 1M, Gemini 3.1 Pro: 1M) — large PRs are fine for all
- The review standard file is the single source of truth for what to check
- In **report mode**: Reviewers produce text output only. No GitHub side effects — the human decides whether to act
- In **comment mode**: After summary, post a consolidated `gh pr review --comment` to the PR with all findings. Individual reviewer identities are tagged inline (e.g. "[Stella+Nova]"). This is a COMMENT review, not APPROVE/REQUEST_CHANGES — the human still makes the final call
- Cross-channel callers always get report mode. Comment mode is only available when used directly in #code-review
