#!/bin/bash
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # jq missing: do not block. Pretool surfaces the install hint when a tool call
  # actually requires hook enforcement.
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$(pwd)
if ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  CWD="$ROOT"
fi
ACTIVE_FILE="$CWD/.codex/.vdgg-active"
[ -f "$ACTIVE_FILE" ] || exit 0
VDGG_ID=$(cat "$ACTIVE_FILE")
[ -n "$VDGG_ID" ] || exit 0
STATE_FILE="$CWD/.codex/.vdgg-state-${VDGG_ID}"
[ -f "$STATE_FILE" ] || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
PHASE=$(grep '^phase=' "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT=$(grep '^loop_count=' "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT="${LOOP_COUNT:-0}"

if [ "$TOOL_NAME" = "apply_patch" ] && [ "$PHASE" = "testing" ]; then
  REVIEW_FILE="$CWD/.codex/.vdgg-review-sentinel-${VDGG_ID}-${LOOP_COUNT}"
  if [ -f "$REVIEW_FILE" ]; then
    MODIFIED_FILES=$(printf '%s\n' "$COMMAND" | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p' | paste -sd, -)
    TMP=$(mktemp)
    grep -v '^modified=' "$REVIEW_FILE" | grep -v '^modified_files=' > "$TMP" || true
    {
      echo "modified=1"
      echo "modified_files=${MODIFIED_FILES}"
    } >> "$TMP"
    mv "$TMP" "$REVIEW_FILE"
  fi
fi

if [ "$PHASE" = "testing" ] && { [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; }; then
  REVIEW_FILE="$CWD/.codex/.vdgg-review-sentinel-${VDGG_ID}-${LOOP_COUNT}"
  if [ -f "$REVIEW_FILE" ]; then
    EDITED_FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
    # Sidecar files are internal workflow files, not implementation changes.
    if [[ "$EDITED_FILE_PATH" == *".codex/.vdgg-"* ]]; then
      exit 0
    fi
    # Task notes are workflow records, not implementation changes.
    if [[ "$EDITED_FILE_PATH" == *"tasks/vdgg/"* ]]; then
      exit 0
    fi
    # Append the edited file uniquely (comma-separated).
    CURRENT_FILES=$(grep '^modified_files=' "$REVIEW_FILE" | head -1 | sed 's/^modified_files=//')
    if [ -n "$EDITED_FILE_PATH" ] && [[ ",$CURRENT_FILES," != *",$EDITED_FILE_PATH,"* ]]; then
      if [ -z "$CURRENT_FILES" ]; then
        NEW_FILES="$EDITED_FILE_PATH"
      else
        NEW_FILES="${CURRENT_FILES},${EDITED_FILE_PATH}"
      fi
    else
      NEW_FILES="$CURRENT_FILES"
    fi
    TMP=$(mktemp)
    grep -v '^modified=' "$REVIEW_FILE" | grep -v '^modified_files=' > "$TMP" || true
    {
      echo "modified=1"
      echo "modified_files=${NEW_FILES}"
    } >> "$TMP"
    mv "$TMP" "$REVIEW_FILE"
  fi
  exit 0
fi

if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Codex CLI delivers tool_response as an object in some versions and as a plain
# string in others (e.g. 0.139.0). Read both shapes without erroring under
# `set -e`. When only a string is available there is no exit_code, so failure
# detection below falls back to scanning the response text (best-effort).
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r 'if (.tool_response|type)=="object" then (.tool_response.exit_code // .tool_response.metadata.exit_code // 0) else 0 end' 2>/dev/null || echo 0)
# Broad error-pattern scan target. For object shape, join only stderr+output so
# that normal stdout containing an error word (e.g. `git log` showing
# "a1b2c3 fix: error in parser") is not misdetected. stdout is checked
# separately with a strict pattern below. For string shape there is no
# stdout/stderr distinction, so scan the whole string.
RESP_TEXT=$(printf '%s' "$INPUT" | jq -r 'if (.tool_response|type)=="object" then [(.tool_response.stderr//""),(.tool_response.output//"")]|join("\n") elif (.tool_response|type)=="string" then .tool_response else "" end' 2>/dev/null || true)
# Object-shape stdout only. Checked with a strict start-of-line pattern below so
# normal command output is not treated as an error. Empty for string/null shapes.
STDOUT_TEXT=$(printf '%s' "$INPUT" | jq -r 'if (.tool_response|type)=="object" then (.tool_response.stdout//"") else "" end' 2>/dev/null || true)

if printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(init|write|advance|loop|clear|read|mark_reviewed)'; then
  exit 0
fi

IS_SEARCH=0
if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];&|(])(grep|rg|ag|ack|find|awk|sed|fgrep|egrep|jq|test|\[)([[:space:]]|$)'; then
  IS_SEARCH=1
fi

ERROR_DETECTED=0
ERROR_REASON=""

if [ "${EXIT_CODE:-0}" -ne 0 ]; then
  if [ "$IS_SEARCH" -eq 1 ] && [ "$EXIT_CODE" -lt 2 ]; then
    :
  else
    ERROR_DETECTED=1
    ERROR_REASON="exit code=${EXIT_CODE}"
  fi
fi

if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
  if printf '%s' "$RESP_TEXT" | grep -qE '(^|[^a-zA-Z])(error|Error|ERROR|fail|Fail|FAIL|Exception|Traceback)([^a-zA-Z]|$)'; then
    ERROR_DETECTED=1
    ERROR_REASON="tool_response matched error/fail/Exception pattern"
  fi
fi

# Object-shape stdout gets only a strict start-of-line pattern, so normal output
# that merely mentions "error"/"fail" mid-line is not misdetected. STDOUT_TEXT is
# empty for string/null shapes, so this check naturally skips there.
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
  if printf '%s' "$STDOUT_TEXT" | grep -qE '^[[:space:]]*(error|Error|ERROR|fail|Fail|FAIL):[[:space:]]'; then
    ERROR_DETECTED=1
    ERROR_REASON="tool_response stdout matched strict error pattern"
  fi
fi

if [ "$ERROR_DETECTED" -eq 1 ]; then
  {
    echo "reason=$ERROR_REASON"
    echo "command=$COMMAND"
    echo "exit_code=$EXIT_CODE"
    echo "response_excerpt=$(printf '%s' "$RESP_TEXT" | head -c 500)"
  } > "$CWD/.codex/.vdgg-error-pending"
fi

exit 0
