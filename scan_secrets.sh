#!/bin/bash

# ==============================================================================
#  Sanitization & Secrets Scanner (v3 - Git Aware)
#  Only scans files tracked by Git, ignoring the .git directory and all
#  files listed in .gitignore.
# ==============================================================================

# --- Configuration ---
SECRETS_FILE=".secrets_patterns.txt"

# Refined regex patterns to reduce false positives.
SENSITIVE_PATTERNS=(
  # Matches common database host patterns
  "[a-zA-Z0-9.-]+\.(database\.windows\.net|databricks\.com)"
  # Looks for strings with common key prefixes followed by 20+ chars
  "(api_key|secret_key|pat|token)['\"]?[:= ]+['\"]?[a-zA-Z0-9_\\-]{20,}"
)
# --- End of Configuration ---

# Check if we are in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: This script must be run from within a Git repository."
    exit 1
fi

# Check if the secrets file exists
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Error: Secrets file not found at '$SECRETS_FILE'"
  exit 1
fi

ISSUE_COUNT=0
echo "🚀 Starting scan on files tracked by Git..."
echo "================================================="
GREP_OPTIONS="--color=always -niI"

# Get a list of all files tracked by git
FILES_TO_SCAN=$(git ls-files)

# --- 1. Scan for Specific Strings from File ---
echo ""
echo "### Searching for specific strings from '$SECRETS_FILE'... ###"
while IFS= read -r STRING; do
  if [[ -z "$STRING" || "$STRING" == \#* ]]; then continue; fi
  
  # Grep through the list of tracked files
  RESULTS=$(echo "$FILES_TO_SCAN" | xargs grep $GREP_OPTIONS "$STRING" || true)
  if [ -n "$RESULTS" ]; then
    echo ""
    echo "🚨 FOUND POTENTIAL ISSUE FOR: $STRING"
    echo "$RESULTS"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  fi
done < "$SECRETS_FILE"

# --- 2. Scan for General Patterns ---
echo ""
echo "### Searching for general patterns (endpoints, keys)... ###"
for PATTERN in "${SENSITIVE_PATTERNS[@]}"; do
  RESULTS=$(echo "$FILES_TO_SCAN" | xargs grep -E $GREP_OPTIONS "$PATTERN" || true)
  if [ -n "$RESULTS" ]; then
    echo ""
    echo "🚨 FOUND POTENTIAL ISSUE FOR PATTERN: $PATTERN"
    echo "$RESULTS"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  fi
done

# --- 3. Final Report ---
echo ""
echo "================================================="
if [ $ISSUE_COUNT -eq 0 ]; then
  echo "✅ Scan complete. No specific issues found in tracked files."
else
  echo "⚠️ Scan complete. Found $ISSUE_COUNT potential issue(s). Please review the files listed above."
fi
echo "================================================="