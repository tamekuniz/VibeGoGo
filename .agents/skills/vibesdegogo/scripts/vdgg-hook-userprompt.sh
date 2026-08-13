#!/bin/bash
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$(pwd)
if ! ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  exit 0
fi

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "VibesDeGoGo! for Codex is installed globally. For coding work in any git repository, use the vibesdegogo skill by default: agree on Goal, Constraints, and Acceptance criteria before edits, then initialize VDGG state in the repository root. Do not start VDGG for wording-only requests, open-ended discussion, or brainstorming with no repository workflow."
  }
}
EOF
