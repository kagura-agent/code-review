---
name: code-review
description: "Multi-model PR review — spawn 3 reviewers (GPT-5.5, Claude Opus 4.7, Gemini 2.5 Pro), consolidate findings, optionally post to GitHub."
---

# Code Review

Trigger: any message implying "review this PR" + a PR reference (link, `owner/repo#123`, or just `#N` with context).

## Reviewers

- 🌟 Stella — `default-llm-sg/gpt-5.5`
- 🌠 Nova — `default-llm-sg/claude-opus-4.7`
- 💫 Vega — `default-llm-sg/gemini-2.5-pro`

## Modes

- Default: always post review to PR via `gh pr review --comment`
- Only skip PR posting if user explicitly says "不要贴PR" or "just channel"

## Execution

**必须用 FlowForge。不接受手动替代。**

```bash
# 开始 workflow
flowforge run code-review
# 每步执行完后推进：
flowforge advance --result '<step output>' -w code-review
# 查看当前进度：
flowforge status -w code-review
```

FlowForge 逐步推进，不能跳步。workflow 保证 reflection 和 tracking 不被遗漏。

**手动 spawn 只在 FlowForge 完全不可用时才允许。** 如果手动执行，必须逐条对照 workflow.yaml 的每个节点，确认全部完成。

已验证 FlowForge 可正常运行此 workflow（2026-06-04 实测）。

## Review Output

Reviewers write to `reviews/<repo>-<pr>-<name>.md` (e.g. `reviews/cove-175-stella.md`).
Parent reads from files, not session history. Prevents truncation + creates persistent record.

## Re-review Protocol

For Round 2+, include the previous consolidated review in each reviewer's prompt with:
1. Check each previous issue — was it addressed?
2. **Escalation rule**: Unaddressed issues from last round → escalate severity. Never downgrade.
3. **Anti-confirmation bias**: "Your previous acceptance doesn't mean correct. Re-evaluate fresh."
4. Fresh review of any new code.

## Language

**All review comments posted to GitHub PRs must be in English.** No exceptions — whether it's our own repo or external. Internal workspace files (reviews/, channel messages) can use any language, but the moment it goes on a PR, English only.

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
- `prompts/` — review standard prompts (default + per-repo)
- `reviews/` — reviewer output files (persistent, git-tracked)
- `runs/` — run records + reflection
- `stats.md` — per-reviewer capability assessment (updated by tracking cron)
- `tracking.json` — PR follow-up tracking

## Automated Assessment

`code-review-pr-tracking` cron (every 6h) does two things:
1. **PR tracking** — check human review feedback, write ground truth to runs/
2. **Reviewer capability assessment** — aggregate runs/ data, update stats.md with dimension strengths, trends, unique find rates
