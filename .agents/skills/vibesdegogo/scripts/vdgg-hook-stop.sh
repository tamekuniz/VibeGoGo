#!/bin/bash
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$(pwd)
if ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  CWD="$ROOT"
fi
ACTIVE_FILE="$CWD/.codex/.vdgg-active"
[ -f "$ACTIVE_FILE" ] || { printf '{}\n'; exit 0; }
VDGG_ID=$(cat "$ACTIVE_FILE")
[ -n "$VDGG_ID" ] || { printf '{}\n'; exit 0; }
STATE_FILE="$CWD/.codex/.vdgg-state-${VDGG_ID}"
[ -f "$STATE_FILE" ] || { printf '{}\n'; exit 0; }

LAST_MESSAGE=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty')
if printf '%s' "$LAST_MESSAGE" | grep -qF '[Intentional Stop]'; then
  printf '{}\n'
  exit 0
fi

STEP=$(grep '^step=' "$STATE_FILE" | cut -d= -f2 || true)
PHASE=$(grep '^phase=' "$STATE_FILE" | cut -d= -f2 || true)

cat <<EOF
{
  "decision": "block",
  "reason": "VibesDeGoGo! for Codex [${VDGG_ID}] is still active at step=${STEP}, phase=${PHASE}. Continue the workflow, clear state after Step 9, or output [Intentional Stop] with the reason. Waiting on a background subagent/task to finish is a legitimate reason to stop — say so with [Intentional Stop]."
}
EOF
