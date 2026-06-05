#!/usr/bin/env bash
# rule-inject.sh — Detect file types in a PR diff and output relevant review rules
# Inspired by Alibaba Open-Code-Review's rules-as-prompt architecture
#
# Usage: bash rule-inject.sh <owner/repo> <pr_number>
# Output: Combined language-specific rules to inject into reviewer prompts
# Exit 0 with empty output if no matching rules found

set -euo pipefail

RULES_DIR="$(dirname "$0")/rules"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <owner/repo> <pr_number>" >&2
  exit 1
fi

REPO="$1"
PR="$2"

# Get changed file extensions from PR diff
extensions=$(gh pr diff "$PR" -R "$REPO" --name-only 2>/dev/null | \
  sed -n 's/.*\.\([^.]*\)$/\1/p' | \
  sort -u)

if [[ -z "$extensions" ]]; then
  exit 0
fi

# Map extensions to rule files
declare -A EXT_TO_RULE=(
  [ts]="typescript"
  [tsx]="typescript"
  [js]="typescript"
  [jsx]="typescript"
  [mjs]="typescript"
  [cjs]="typescript"
  [mts]="typescript"
  [go]="go"
  [py]="python"
  [pyx]="python"
  [rs]="rust"
)

# Collect unique rule files to include
declare -A included=()
for ext in $extensions; do
  rule="${EXT_TO_RULE[$ext]:-}"
  if [[ -n "$rule" && -z "${included[$rule]:-}" && -f "$RULES_DIR/$rule.md" ]]; then
    included[$rule]=1
  fi
done

if [[ ${#included[@]} -eq 0 ]]; then
  exit 0
fi

# Output combined rules
echo "## Language-Specific Review Rules"
echo ""
echo "The following language-specific checklists apply to this PR based on the file types changed."
echo "Use these as additional review criteria alongside the general review standard."
echo ""

for rule in "${!included[@]}"; do
  cat "$RULES_DIR/$rule.md"
  echo ""
  echo "---"
  echo ""
done
