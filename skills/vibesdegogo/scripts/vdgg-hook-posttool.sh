#!/bin/bash
# vdgg-hook-posttool.sh - PostToolUse hook for error and simplify tracking.
# It records failed Bash commands so the next PreToolUse can require acknowledgement.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
    # Without jq the hook JSON cannot be parsed properly. Best-effort: extract
    # cwd with grep/sed and check for an active VibesDeGoGo! session there. No
    # active session -> stay out of the way so unrelated repositories are never
    # blocked by a missing dependency.
    FALLBACK_CWD=$(printf '%s' "$INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
    FALLBACK_CWD="${FALLBACK_CWD:-$PWD}"
    if [ ! -f "$FALLBACK_CWD/.claude/.vdgg-active" ]; then
        exit 0
    fi
    # Allow the current Bash command through if it is itself an attempt to install jq.
    if printf '%s' "$INPUT" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*(brew[[:space:]]+(install|reinstall)|apt(-get)?[[:space:]]+install|apk[[:space:]]+add|dnf[[:space:]]+install|yum[[:space:]]+install|pacman[[:space:]]+-S)[[:space:]]+[^"]*jq'; then
        exit 0
    fi
    {
        echo "VibesDeGoGo! hook: jq is required for hooks but was not found on PATH."
        echo "  macOS:               brew install jq"
        echo "  Debian/Ubuntu/WSL:   sudo apt-get install jq"
        echo "  Alpine:              apk add jq"
        echo "  Fedora/RHEL:         sudo dnf install jq"
    } >&2
    exit 2
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
HOOK_EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# CWD is required to locate the repository-local state files.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
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

# Load the state file for the active id.
STATE_FILE="$CWD/.claude/.vdgg-state-${VDGG_ID}"
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT=$(grep "^loop_count=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT="${LOOP_COUNT:-0}"

if [ -z "$PHASE" ]; then
    exit 0
fi

# Phase-specific tool filter.
# Outside testing, only Bash results can create error flags.
# In testing, Skill/Edit/Write are also needed for simplify sentinel tracking.
if [ "$PHASE" != "testing" ]; then
    if [ "$TOOL_NAME" != "Bash" ]; then
        exit 0
    fi
else
    case "$TOOL_NAME" in
        Bash|Skill|Edit|Write)
            ;;
        *)
            exit 0
            ;;
    esac
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0')
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty')
STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
HOOK_ERROR=$(echo "$INPUT" | jq -r '.error // empty')

# Skill/Edit/Write events are handled only by the testing-specific blocks below.

# simplify skill invocation creates a sentinel for the current test loop.
# The sentinel later records whether simplify changed implementation files.
if [ "$PHASE" = "testing" ] && [ "$TOOL_NAME" = "Skill" ]; then
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
    if [ "$SKILL_NAME" = "simplify" ]; then
        SENTINEL_FILE="$CWD/.claude/.vdgg-simplify-sentinel-${VDGG_ID}-${LOOP_COUNT}"
        if [ ! -f "$SENTINEL_FILE" ]; then
            STARTED_AT=$(date -u +%FT%TZ)
            cat > "$SENTINEL_FILE" <<EOF
started=1
started_at=${STARTED_AT}
modified=0
modified_files=
EOF
        fi
        exit 0
    fi
fi

# After a review gate starts (simplify or explicit review), any Edit/Write to
# implementation files marks the sentinel as modified so verified is blocked
# until reflection/re-test. Both sentinel kinds get the same tracking.
if [ "$PHASE" = "testing" ] && { [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; }; then
    EDITED_FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    for SENTINEL_FILE in \
        "$CWD/.claude/.vdgg-simplify-sentinel-${VDGG_ID}-${LOOP_COUNT}" \
        "$CWD/.claude/.vdgg-review-sentinel-${VDGG_ID}-${LOOP_COUNT}"; do
        [ -f "$SENTINEL_FILE" ] || continue
        # Sidecar files are internal workflow files, not implementation changes.
        # (Pretool also blocks editing them; this guard is defense in depth.)
        if [[ "$EDITED_FILE_PATH" == *".claude/.vdgg-"* ]]; then
            continue
        fi
        # Task notes are workflow records, not implementation changes.
        TASKS_DIR_BASENAME="tasks/vdgg/${VDGG_ID}"
        if [[ "$EDITED_FILE_PATH" == *"$TASKS_DIR_BASENAME"* ]]; then
            continue
        fi
        # Append the edited file once.
        CURRENT_FILES=$(grep '^modified_files=' "$SENTINEL_FILE" | head -1 | sed 's/^modified_files=//')
        if [ -n "$EDITED_FILE_PATH" ] && [[ ",$CURRENT_FILES," != *",$EDITED_FILE_PATH,"* ]]; then
            if [ -z "$CURRENT_FILES" ]; then
                NEW_FILES="$EDITED_FILE_PATH"
            else
                NEW_FILES="${CURRENT_FILES},${EDITED_FILE_PATH}"
            fi
        else
            NEW_FILES="$CURRENT_FILES"
        fi
        # Rewrite the sentinel atomically through a temp file.
        TMP=$(mktemp)
        grep -v '^modified=' "$SENTINEL_FILE" | grep -v '^modified_files=' > "$TMP" || true
        cat >> "$TMP" <<EOF
modified=1
modified_files=${NEW_FILES}
EOF
        mv "$TMP" "$SENTINEL_FILE"
    done
    exit 0
fi

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# Search commands often use exit 1 for "no matches"; avoid treating that as failure.
SEARCH_CMDS_PATTERN='(^|[[:space:];&|(])(grep|rg|ag|ack|find|awk|sed|fgrep|egrep|jq|test|\[)([[:space:]]|$)'
IS_SEARCH=0
if echo "$COMMAND" | grep -qE "$SEARCH_CMDS_PATTERN"; then
    IS_SEARCH=1
fi

# Internal state-helper commands are workflow operations, not user command failures.
if echo "$COMMAND" | grep -qE 'vdgg_state_(init|write|advance|loop|clear|read)'; then
    exit 0
fi

# Error detection combines exit status, hook failure events, and textual error signals.
ERROR_DETECTED=0
ERROR_REASON=""

if [ "$EXIT_CODE" -ne 0 ]; then
    # For search commands, exit 1 means "not found"; exit 2+ is a real error.
    if [ "$IS_SEARCH" -eq 1 ] && [ "$EXIT_CODE" -lt 2 ]; then
        : # ignore no-match search results
    else
        ERROR_DETECTED=1
        ERROR_REASON="exit code=$EXIT_CODE"
    fi
fi

if [ "$ERROR_DETECTED" -eq 0 ] && [ "$HOOK_EVENT_NAME" = "PostToolUseFailure" ]; then
    # VibesDeGoGo hook/state logic.
    # Search commands' no-match (exit=1) is benign; same exception as the EXIT_CODE branch above.
    if [ "$IS_SEARCH" -eq 1 ] && [ "$EXIT_CODE" -lt 2 ]; then
        :
    else
        ERROR_DETECTED=1
        if [ -n "$HOOK_ERROR" ]; then
            ERROR_REASON="$HOOK_ERROR"
        else
            ERROR_REASON="PostToolUseFailure"
        fi
    fi
fi

# stderr error/fail signals count only for non-search commands.
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
    if echo "$STDERR" | grep -qE '(^|[^a-zA-Z])(error|Error|ERROR|fail|Fail|FAIL|Exception|Traceback)([^a-zA-Z]|$)'; then
        ERROR_DETECTED=1
        ERROR_REASON="stderr matched error/fail/Exception pattern"
    fi
fi

# stdout is noisier, so only line-starting `error:` / `fail:` style output counts.
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
    if echo "$STDOUT" | grep -qE '^[[:space:]]*(error|Error|ERROR|fail|Fail|FAIL):[[:space:]]'; then
        ERROR_DETECTED=1
        ERROR_REASON="stdout started with error/fail pattern"
    fi
fi

# Store the pending error for the next PreToolUse acknowledgement gate.
if [ "$ERROR_DETECTED" -eq 1 ]; then
    FLAG_FILE="$CWD/.claude/.vdgg-error-pending"
    {
        echo "reason=$ERROR_REASON"
        echo "command=$COMMAND"
        echo "exit_code=$EXIT_CODE"
        if [ -n "$STDERR" ]; then
            echo "stderr_excerpt=$(echo "$STDERR" | head -c 500)"
        else
            echo "stderr_excerpt=$(echo "$HOOK_ERROR" | head -c 500)"
        fi
    } > "$FLAG_FILE"
fi

exit 0
