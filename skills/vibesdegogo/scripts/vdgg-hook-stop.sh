#!/bin/bash
# vdgg-hook-stop.sh - Stop hook for active VibesDeGoGo! cycles.
#
# Behavior:
#   - Fires when a turn is about to end while VibesDeGoGo! state is active.
#   - Allows the stop only if the current assistant turn either:
#       1. ran a Bash tool_use containing vdgg_state_(advance|loop|write|clear|init), or
#       2. explicitly output [Intentional Stop].
#   - No active state file -> exit 0.
#   - stop_hook_active=true -> exit 0 to prevent recursive hook loops.
#
# CWD handling:
#   Stop hook input is expected to contain cwd. Reconstructing cwd from
#   transcript_path is unsafe for paths with hyphens, so missing cwd exits 0.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    # jq missing: do not block the agent from stopping. Pretool/posttool will surface
    # the install hint when a tool call actually requires hook enforcement.
    exit 0
fi

# Prevent recursive Stop hook loops.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# CWD must come from the hook payload; transcript path decoding is lossy.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

# Active file stores the current VibesDeGoGo! id.
ACTIVE_FILE="$CWD/.claude/.vdgg-active"
if [ ! -f "$ACTIVE_FILE" ]; then
    exit 0
fi

VDGG_ID=$(cat "$ACTIVE_FILE")
if [ -z "$VDGG_ID" ]; then
    exit 0
fi

STATE_FILE="$CWD/.claude/.vdgg-state-${VDGG_ID}"
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)

# Current-turn assistant messages begin after the last user message.
LAST_USER_LINE=$(jq -r 'select(.type=="user" and ((.message.content | type) == "string" or ((.message.content | type) == "array" and (.message.content[0].type // "") != "tool_result"))) | input_line_number' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
LAST_USER_LINE="${LAST_USER_LINE:-0}"

# Text is checked for explicit intentional-stop acknowledgement.
CURRENT_TURN_TEXT=$(awk -v start="$LAST_USER_LINE" 'NR > start' "$TRANSCRIPT_PATH" \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null || true)

# Bash tool calls are checked for state progression commands.
CURRENT_TURN_BASH=$(awk -v start="$LAST_USER_LINE" 'NR > start' "$TRANSCRIPT_PATH" \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' 2>/dev/null || true)

# State helper usage means the workflow advanced during this turn.
if echo "$CURRENT_TURN_BASH" | grep -qE 'vdgg_state_(advance|loop|write|clear|init)'; then
    exit 0
fi

# Explicit stop text means the agent is intentionally yielding control.
if echo "$CURRENT_TURN_TEXT" | grep -qF "[Intentional Stop]"; then
    exit 0
fi

# Otherwise block silent stop while the workflow is active.
echo "VibesDeGoGo! [${VDGG_ID}] step=${STEP} phase=${PHASE}: Active workflow cannot stop silently. If you are waiting on a background subagent, that is a legitimate reason to pause — say so with [Intentional Stop]. Otherwise run the next state action." >&2
exit 2
