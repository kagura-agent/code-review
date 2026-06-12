# PR #331 Review — Stella

## Summary

This PR adds a new `cove-admin` skill with documentation and a Node ESM CLI for channel create/list/update/delete against the Cove REST API. The endpoint choices match the server/client API shape (`/api/v10/guilds/{guildId}/channels`, `/api/v10/channels/{id}`), token is read from local config rather than hardcoded, and the script passes `node --check`.

Rating: ⚠️ Needs Changes

## Critical Issues

1. **Unhandled failures produce raw Node stack traces instead of CLI-safe errors.**  
   `cove-admin.mjs` uses top-level `await` without a `try/catch` wrapper. Config parse/read errors, network failures, non-JSON success bodies, and API errors will bubble to Node's default exception printer. For an admin skill this should be a clear one-line error with a non-zero exit, ideally without dumping internal stack details by default. Add a `main()` wrapper and catch errors, e.g. print `Error: ...` and `process.exit(1)`.

2. **Destructive delete has no confirmation or explicit force flag.**  
   `channel delete` / alias `rm` immediately deletes a channel by ID. Since this skill is meant for admin channel management and may be invoked by agents, accidental deletion is a real operational risk. Require `--yes`/`--force`, or at least make the command refuse unless an explicit confirmation flag is supplied. The SKILL.md examples should document that requirement.

## Product Impact

- Adds a new operational/admin surface for Cove channel management. This is useful, but mistakes can directly create, rename, or delete live channels.
- Error UX is currently rough: users may see stack traces for common failures such as missing config, invalid JSON config, network errors, 401/403, or invalid response JSON.
- `--topic` cannot be set to an empty string, so the CLI cannot clear an existing topic even though the API likely supports patching `topic: ""`.

## Suggestions

- Consider using `node:util.parseArgs` for option parsing. The current `indexOf` parser does not support `--name=value`, cannot distinguish missing option values from values that start with `--`, and silently ignores unknown flags.
- Validate/sanitize channel names before sending: trim whitespace and enforce/document Cove's accepted naming rules if names must be lowercase/no spaces.
- Improve HTTP response handling:
  - Treat `429` specially and show `Retry-After` when present.
  - Wrap `res.json()` in a helpful error if the server returns non-JSON.
  - For error responses, prefer extracting `{ message, code }` when possible instead of dumping raw body text.
- Avoid re-reading config multiple times per command (`channelCreate`/`channelList` load config, then `api()` loads it again). Load once and pass it through, or initialize an API client.
- Update SKILL.md to mention required permissions/access assumptions and the destructive nature of delete.
- The Direct API Usage snippet should check `r.ok` before `r.json()` so it models robust usage.

## Positive Notes

- No hardcoded secrets; token/base URL/guild ID are read from `~/.openclaw/openclaw.json`.
- API version and documented endpoints match the existing `/api/v10` REST convention.
- Uses ESM cleanly and has no syntax errors under `node --check`.
- The basic command surface is small and easy to understand, with helpful usage messages for missing required arguments.
