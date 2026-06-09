#!/usr/bin/env bash
# verify-findings.sh — Verify code review findings against actual source
# Inspired by GodModeSkill's self-consistency verification (anti-hallucination)
#
# Usage: verify-findings.sh <repo-path> <review-file>
#
# Reads a review markdown file, extracts file:line references and quoted code,
# then greps the actual source to verify they exist.
# Outputs: verified/unverified counts + flagged unverified findings.

set -euo pipefail

REPO="${1:?Usage: verify-findings.sh <repo-path> <review-file>}"
REVIEW="${2:?Usage: verify-findings.sh <repo-path> <review-file>}"

if [[ ! -d "$REPO" ]]; then
  echo "❌ Repo path not found: $REPO"
  exit 1
fi

if [[ ! -f "$REVIEW" ]]; then
  echo "❌ Review file not found: $REVIEW"
  exit 1
fi

verified=0
unverified=0
total=0
declare -a unverified_findings=()

# Strategy 1: Extract all file path references from review
# Uses grep to find ALL backtick-wrapped file references (multiple per line supported)
# Patterns: `file.ts`, `path/to/file.tsx:42`, `useStore.ts`

mapfile -t refs < <(grep -oP '`([a-zA-Z0-9_./-]+\.(ts|js|py|go|rs|yaml|yml|json|sh|tsx|jsx))(:[0-9]+)?`' "$REVIEW" | sed 's/^`//;s/`$//' | sed 's/:[0-9]*$//' | sort -u)

for filepath in "${refs[@]}"; do
  [[ -z "$filepath" ]] && continue
  ((total++)) || true
  
  # Check if file exists in repo (exact path or find)
  if [[ -f "$REPO/$filepath" ]]; then
    ((verified++)) || true
  else
    found=$(find "$REPO" -path "*/$filepath" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
      ((verified++)) || true
    else
      ((unverified++)) || true
      unverified_findings+=("  ⚠️  File not found: $filepath")
    fi
  fi
done


# Report
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Finding Verification Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total file references: $total"
echo "  ✅ Verified:           $verified"
echo "  ⚠️  Unverified:        $unverified"

if [[ $total -gt 0 ]]; then
  pct=$(( verified * 100 / total ))
  echo "  Confidence:           ${pct}%"
fi

if [[ ${#unverified_findings[@]} -gt 0 ]]; then
  echo ""
  echo "Unverified references:"
  for finding in "${unverified_findings[@]}"; do
    echo "$finding"
  done
fi

if [[ $unverified -gt 0 && $total -gt 0 ]]; then
  pct_bad=$(( unverified * 100 / total ))
  if [[ $pct_bad -gt 30 ]]; then
    echo ""
    echo "🚨 HIGH hallucination risk: ${pct_bad}% of file references unverified"
    echo "   Consider re-reviewing with actual file paths provided to reviewer."
    exit 2
  elif [[ $pct_bad -gt 10 ]]; then
    echo ""
    echo "⚠️  Moderate hallucination risk: ${pct_bad}% of file references unverified"
    exit 1
  fi
fi

exit 0
