#!/usr/bin/env bash
# reflection-gate.sh — Structural enforcement for code-review reflection
# Checks that a reflection run file exists for a given PR before allowing completion.
# Usage: bash reflection-gate.sh <repo> <pr_number>
# Exit 0 = reflection exists, 1 = missing (blocks completion)
#
# Addresses: skip-reflection pattern (4-day recidivist, 2026-06-04)
# Principle: structural fix > behavioral rule

set -euo pipefail

RUNS_DIR="$(dirname "$0")/runs"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <repo> <pr_number>"
    echo "Example: $0 cove 294"
    exit 2
fi

REPO="$1"
PR="$2"

# Check for run file matching pattern: <repo>-<pr>*.md
matching_files=()
for f in "$RUNS_DIR"/${REPO}-${PR}*.md; do
    [[ -f "$f" ]] && matching_files+=("$f")
done

if [[ ${#matching_files[@]} -eq 0 ]]; then
    echo "❌ REFLECTION MISSING: No run file found for ${REPO}#${PR}"
    echo "   Expected: ${RUNS_DIR}/${REPO}-${PR}.md"
    echo ""
    echo "   You must write a reflection before completing this review."
    echo "   Required layers:"
    echo "   - Layer 1: Record findings summary"
    echo "   - Layer 2: Prompt evolution (cross-run patterns)"
    echo "   - Layer 3: Reviewer assessment (stats.md update)"
    echo ""
    echo "   This is a structural gate (skip-reflection pattern, 4d recidivist)."
    echo "   Cannot be bypassed."
    exit 1
fi

# Validate reflection has minimum content (not just a stub)
for f in "${matching_files[@]}"; do
    line_count=$(wc -l < "$f")
    if [[ $line_count -lt 5 ]]; then
        echo "⚠️  REFLECTION TOO SHORT: ${f} has only ${line_count} lines"
        echo "   Minimum 5 lines expected (not a stub)."
        echo "   Must include Layer 1 (record) at minimum."
        exit 1
    fi
done

echo "✅ Reflection verified for ${REPO}#${PR}: ${matching_files[*]}"
exit 0
