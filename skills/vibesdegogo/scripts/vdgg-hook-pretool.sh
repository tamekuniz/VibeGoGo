#!/bin/bash
# vdgg-hook-pretool.sh - PreToolUse hook for VibesDeGoGo! step enforcement.

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
        # Unarmed session. When the repository opts in with VDGG_REQUIRED=on,
        # tools cannot be classified without jq, so fall through to the
        # fail-closed branch below; otherwise stay out of the way.
        FALLBACK_REQUIRED=$(grep -m1 '^VDGG_REQUIRED=' "$FALLBACK_CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' || true)
        if [ "$FALLBACK_REQUIRED" != "on" ]; then
            exit 0
        fi
    fi
    # An active session must not run unguarded. Fail closed, but allow the
    # current Bash command through if it is itself an attempt to install jq,
    # so the user can run `brew install jq` / `apt-get install jq` etc.
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

# Portable mtime in epoch seconds. Tries BSD/macOS first, then GNU/Linux, then 0.
_vdgg_mtime() {
    # BSD/macOS `stat -f %m` gives the epoch. On GNU/Linux `-f` means
    # --file-system and prints non-numeric text with exit 0, so the raw `||`
    # chain is not enough: validate the result is all-digits and fall back to
    # `stat -c %Y`, then to 0.
    local m
    m=$(stat -f %m "$1" 2>/dev/null || true)
    case "$m" in ''|*[!0-9]*) m=$(stat -c %Y "$1" 2>/dev/null || true) ;; esac
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    printf '%s\n' "$m"
}

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# CWD is required to locate the repository-local state files.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
    exit 0
fi

# Entry gate (VDGG_REQUIRED): normally an unarmed session (no active id or
# state) leaves the hook fail-open so unrelated repositories are never
# touched. A repository can opt out of that leniency with VDGG_REQUIRED=on in
# .vdgg-target: code-modifying tools are then denied until a session is armed
# through vdgg_state_init. This closes the hole where an agent that ignores
# the workflow contract simply never arms the gates (arming must not be a
# voluntary act). Only the literal value `on` activates the gate; anything
# else keeps the historical fail-open behavior.
_vdgg_required() {
    local target="$CWD/.vdgg-target" v
    [ -f "$target" ] || return 1
    v=$(grep -m1 '^VDGG_REQUIRED=' "$target" | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/')
    [ "$v" = "on" ]
}

_vdgg_entry_deny() {
    echo "VibesDeGoGo! entry gate: this repository sets VDGG_REQUIRED=on in .vdgg-target and no VibesDeGoGo! session is armed. Code-modifying tools are blocked until Step 1 runs: source \"\$HOME/.claude/skills/vibesdegogo/scripts/vdgg-state.sh\" && vdgg_state_init. Only a human may relax this by editing .vdgg-target." >&2
    exit 2
}

# Decide an unarmed tool call under VDGG_REQUIRED=on. Mirrors the armed
# path's tool classification: known read-only tools pass, file edits are
# denied, unknown tools exposing a file path are denied (fail-closed), and
# Bash is denied per segment when it writes files or commits. Agent passes
# because a subagent's own tool calls go through this same hook. Known limit
# (same as the sidecar guard): a write hidden behind a shell variable or an
# interpreter one-liner evades the literal segment match; see
# references/hook_rules.md.
_vdgg_entry_gate() {
    case "$TOOL_NAME" in
        Read|Glob|Grep|LS|NotebookRead|TodoWrite|WebFetch|WebSearch|BashOutput|KillShell|Agent)
            exit 0
            ;;
        Edit|Write|NotebookEdit)
            _vdgg_entry_deny
            ;;
        Bash)
            local cmd segs seg seg_checked verb
            cmd=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
            segs="$cmd"
            segs="${segs//&&/$'\n'}"
            segs="${segs//||/$'\n'}"
            segs="${segs//;/$'\n'}"
            segs="${segs//|/$'\n'}"
            while IFS= read -r seg; do
                # Redirections to /dev/null|stdout|stderr do not modify the
                # repository; strip them (fd dups like 2>&1 are already
                # excluded by the [^&] below) so read-only idioms such as
                # `grep x f 2>/dev/null` are not falsely denied.
                seg_checked=$(printf '%s' "$seg" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/(null|stdout|stderr)##g')
                if echo "$seg_checked" | grep -qE '(>[^&]|>>|(^|[[:space:]])tee([[:space:]]|$))'; then
                    _vdgg_entry_deny
                fi
                if echo "$seg" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
                    _vdgg_entry_deny
                fi
                verb=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//')
                case "$verb" in
                    rm|mv|cp|dd|install|truncate|touch|ln|patch|mkfifo)
                        _vdgg_entry_deny
                        ;;
                    sed|perl)
                        if echo "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*i'; then
                            _vdgg_entry_deny
                        fi
                        ;;
                esac
            done <<< "$segs"
            exit 0
            ;;
        *)
            FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
            if [ -n "$FILE_PATH" ]; then
                _vdgg_entry_deny
            fi
            exit 0
            ;;
    esac
}

# Unarmed exit: with the VDGG_REQUIRED opt-in the entry gate decides
# (always exits); without it the hook stays out of the way.
_vdgg_unarmed_exit() {
    if _vdgg_required; then
        _vdgg_entry_gate
    fi
    exit 0
}

# Active file stores the current VibesDeGoGo! id.
ACTIVE_FILE="$CWD/.claude/.vdgg-active"
if [ ! -f "$ACTIVE_FILE" ]; then
    _vdgg_unarmed_exit
fi

VDGG_ID=$(cat "$ACTIVE_FILE")
if [ -z "$VDGG_ID" ]; then
    _vdgg_unarmed_exit
fi

# Load the state file for the active id.
STATE_FILE="$CWD/.claude/.vdgg-state-${VDGG_ID}"
if [ ! -f "$STATE_FILE" ]; then
    _vdgg_unarmed_exit
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT=$(grep "^loop_count=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT="${LOOP_COUNT:-0}"
TASK_ALLOWLIST_FILE=$(grep "^task_allowlist_file=" "$STATE_FILE" | cut -d= -f2- || true)
TASK_GATE_FILE="$CWD/.claude/.vdgg-task-gate-${VDGG_ID}-${LOOP_COUNT}"

if [ -z "$PHASE" ]; then
    exit 0
fi

# Task directory for the active id, used for phase-specific write allowances.
TASKS_DIR="$CWD/tasks/vdgg/${VDGG_ID}"

# Strip the project prefix (or ./) to compare against allowlist entries.
_vdgg_normalize_project_path() {
    local p="$1"
    case "$p" in
        "$CWD"/*) p="${p#"$CWD"/}" ;;
        ./*) p="${p#./}" ;;
    esac
    printf '%s\n' "$p"
}

# Extract only the fields needed for the current tool type.

case "$TOOL_NAME" in
    Edit|Write|NotebookEdit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
        ;;
    Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        ;;
    Agent)
        # Agent calls are phase-gated below.
        ;;
    Read|Glob|Grep|LS|NotebookRead|TodoWrite|WebFetch|WebSearch|BashOutput|KillShell)
        # Known read-only / non-file-mutating tools are always allowed.
        exit 0
        ;;
    *)
        # Unknown tool: it may mutate files. Extract a file path if the tool
        # exposes one and let the phase guards below apply (fail-closed for file
        # writes). A read-only tool with no file path still falls through to the
        # allow at the end, so this does not block genuine reads.
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
        ;;
esac

# Error acknowledgement gate: after a failed Bash command, require the next
# assistant turn to acknowledge it before another tool runs.
ERROR_FLAG="$CWD/.claude/.vdgg-error-pending"
if [ -f "$ERROR_FLAG" ]; then
    TRANSCRIPT_PATH_E=$(echo "$INPUT" | jq -r '.transcript_path // empty')
    if [ -n "$TRANSCRIPT_PATH_E" ] && [ -f "$TRANSCRIPT_PATH_E" ]; then
        # Accept an acknowledgement emitted at any point after the failure was
        # recorded, anchored on the flag file's mtime.
        #
        # Anchoring on "after the last user message" instead made this gate
        # unsatisfiable in practice. The current assistant message is not yet in
        # the transcript at PreToolUse time (see the Guard 2 note below), so the
        # acknowledgement can never ride in the same message as the retry; and
        # once the turn ends, ANY later user entry pushes the acknowledgement out
        # of the window -- including the Stop hook's own feedback, which is
        # recorded as a user entry. No ordering could satisfy it, so a single
        # failed Bash command blocked every non-read tool for the rest of the
        # session.
        FLAG_MTIME_E=$(_vdgg_mtime "$ERROR_FLAG")
        # Fractional seconds are stripped because jq's fromdateiso8601 accepts
        # only whole-second ISO-8601; a parse failure would exclude every entry
        # and recreate the trap.
        TS_EXPR_E='((.timestamp // "") | sub("\\.[0-9]+";"") | fromdateiso8601? // 0)'
        ACK_TEXT_E=$(jq -r --arg t "$FLAG_MTIME_E" "
            select(.type==\"assistant\")
            | select($TS_EXPR_E >= (\$t | tonumber))
            | .message.content[]? | select(.type==\"text\") | .text // empty
        " "$TRANSCRIPT_PATH_E" 2>/dev/null || true)
        # If nothing in the transcript carries a parseable timestamp the mtime
        # anchor cannot work at all; fall back to a bounded tail window so the
        # gate degrades into something satisfiable rather than into a trap.
        HAS_TS_E=$(jq -r "select(.type==\"assistant\") | $TS_EXPR_E | select(. > 0)" "$TRANSCRIPT_PATH_E" 2>/dev/null | head -1)
        if [ -z "$HAS_TS_E" ]; then
            ACK_TEXT_E=$(tail -n 40 "$TRANSCRIPT_PATH_E" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null || true)
        fi
        if echo "$ACK_TEXT_E" | grep -qF "[Error Acknowledged]"; then
            rm -f "$ERROR_FLAG"
        else
            ERROR_REASON=$(grep "^reason=" "$ERROR_FLAG" | cut -d= -f2- || echo "unknown")
            echo "VibesDeGoGo! [${VDGG_ID}]: Previous Bash command failed ($ERROR_REASON). Output [Error Acknowledged] with a short plan before running another tool." >&2
            exit 2
        fi
    fi
fi

# Guard 4: block direct edits to any .claude/.vdgg-* sidecar (state, active,
# sentinels) and to .vdgg-target in all phases. Sentinel forgery would bypass
# the review gate; and .vdgg-target holds trusted config (REVIEW_COMMAND,
# STEP*_EXECUTOR_COMMAND) that is executed, so letting the agent write it would
# let it self-author a passing review or an arbitrary command.
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
    if [[ "$FILE_PATH" == *".claude/.vdgg-"* ]] || [[ "$FILE_PATH" == *".vdgg-target" ]]; then
        echo "VibesDeGoGo! [${VDGG_ID}]: Direct edits to VibesDeGoGo! sidecar/target files are blocked. Use vdgg_state_* helpers; .vdgg-target must be set by a human." >&2
        exit 2
    fi
fi
if [ "$TOOL_NAME" = "Bash" ]; then
    # The review sentinel writer is internal to vdgg_review_run. Calling it
    # directly records a review that never ran, which is the one thing the Step 7
    # gate exists to prevent, and it leaves no sidecar path in the command for
    # the guard below to catch. Same literal-match limit: a name hidden behind a
    # shell variable evades this.
    if echo "$COMMAND" | grep -q '_vdgg_write_review_sentinel'; then
        echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: The review gate is recorded by vdgg_review_run, which runs a review command and writes the sentinel only when it exits 0. Calling the internal sentinel writer directly is not allowed." >&2
        exit 2
    fi
    # Sidecar files (.claude/.vdgg-*) may only be written through vdgg_state_*
    # helpers, never directly, or the review/gate sentinels could be forged.
    # Check each shell segment independently so a `git commit` segment (whose
    # message may legitimately mention a sidecar path) cannot shield a
    # sidecar-mutating segment in the same command line, e.g.
    #   git commit -m x && rm -f .claude/.vdgg-active
    # Whitelist model (fail-closed): a segment that mentions a sidecar path is
    # allowed only when it is a git-commit segment, or a genuine read -- a
    # leading read-only verb with no output redirection or tee. Everything else
    # (interpreters like python/perl, dd/install/truncate, redirects, file ops)
    # is denied. Known limit: a segment that hides the sidecar path behind a
    # shell variable or command substitution can evade the literal match; see
    # references/hook_rules.md.
    _vdgg_segs="$COMMAND"
    _vdgg_segs="${_vdgg_segs//&&/$'\n'}"
    _vdgg_segs="${_vdgg_segs//||/$'\n'}"
    _vdgg_segs="${_vdgg_segs//;/$'\n'}"
    _vdgg_segs="${_vdgg_segs//|/$'\n'}"
    while IFS= read -r _vdgg_seg; do
        # The bare `.vdgg-` basename is matched as well as the directory-prefixed
        # form: `cd .claude && printf ... > .vdgg-review-sentinel-...` writes the
        # same file without the prefix ever appearing in the command. This does
        # widen the match to any path containing `.vdgg-`, which is rare enough
        # in practice to be worth the forged-sentinel case it closes.
        case "$_vdgg_seg" in
            *".claude/.vdgg-"*|*".vdgg-target"*|*".vdgg-"*) ;;
            *) continue ;;
        esac
        if echo "$_vdgg_seg" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
            continue
        fi
        _vdgg_verb=$(printf '%s' "$_vdgg_seg" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//')
        _vdgg_read_ok=0
        case "$_vdgg_verb" in
            cat|grep|egrep|fgrep|test|'['|ls|head|tail|wc|diff|cmp|stat|od|hexdump|file|realpath|readlink)
                if ! echo "$_vdgg_seg" | grep -qE '(>[^&]|>>|(^|[[:space:]])tee([[:space:]]|$))'; then
                    _vdgg_read_ok=1
                fi
                ;;
        esac
        if [ "$_vdgg_read_ok" -ne 1 ]; then
            echo "VibesDeGoGo! [${VDGG_ID}]: Direct writes to VibesDeGoGo! sidecar files are blocked. Use vdgg_state_* helpers." >&2
            exit 2
        fi
    done <<< "$_vdgg_segs"
fi

# Guard 2: validate Step declarations in Bash state-transition commands.
#
# The hook checks tool_input.command instead of transcript text because the
# current assistant message may not be in the transcript at PreToolUse time.
# This prevents a valid first attempt from being falsely rejected, and prevents
# a retry from bypassing the declaration check.
#
# Exception: Step 2 accepts the declaration banner emitted during initialization.
#
# Example:
#   # [VibesDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0
#   source $HOME/.claude/skills/vibesdegogo/scripts/vdgg-state.sh && vdgg_state_advance 3 investigating
#
# Human-readable assistant text may still include the declaration, but the
# enforceable contract is the command text.
if [ "$TOOL_NAME" = "Bash" ] && echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+'; then
    TRANSITION_COUNT=$(printf '%s\n' "$COMMAND" | grep -oE 'vdgg_state_(advance|loop)[[:space:]]+[0-9]+' | wc -l | tr -d ' ')
    if [ "${TRANSITION_COUNT:-0}" -gt 1 ]; then
        echo "VibesDeGoGo! [${VDGG_ID}]: State transition commands must include the matching VibesDeGoGo! Step declaration." >&2
        exit 2
    fi
    TARGET_STEP=$(echo "$COMMAND" | sed -nE 's/.*vdgg_state_(advance|loop|write)[[:space:]]+([0-9]+).*/\2/p' | head -1)
    if [ -n "$TARGET_STEP" ]; then
        DECL_OK=0
        if echo "$COMMAND" | grep -qF "[VibesDeGoGo! Step ${TARGET_STEP} Start]"; then
            DECL_OK=1
        elif [ "$TARGET_STEP" = "2" ] && echo "$COMMAND" | grep -qF '[VibesDeGoGo! Declaration]'; then
            DECL_OK=1
        fi
        if [ "$DECL_OK" -eq 0 ]; then
            echo "VibesDeGoGo! [${VDGG_ID}]: State transition commands must include the matching VibesDeGoGo! Step declaration." >&2
            exit 2
        fi
    fi
fi

# Guard 5: tests must run only after the workflow enters testing.
# The default command pattern can be extended through `.vdgg-target`.
if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "implementing" ]; then
    TEST_PATTERN_DEFAULT='swift[[:space:]]+test|xcodebuild[[:space:]]+[^|]*[[:space:]]test|pytest|npm[[:space:]]+(run[[:space:]]+)?test|pnpm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+(run[[:space:]]+)?test|go[[:space:]]+test|cargo[[:space:]]+test|jest|vitest|mocha'
    TEST_PATTERN_EXTRA=""
    if [ -f "$CWD/.vdgg-target" ]; then
        TEST_PATTERN_EXTRA=$(grep '^TEST_COMMAND_PATTERN=' "$CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' | head -1)
    fi
    TEST_PATTERN="$TEST_PATTERN_DEFAULT"
    if [ -n "$TEST_PATTERN_EXTRA" ]; then
        TEST_PATTERN="${TEST_PATTERN}|${TEST_PATTERN_EXTRA}"
    fi
    if echo "$COMMAND" | grep -qE "(^|[[:space:];&|(])(${TEST_PATTERN})([[:space:]]|$)"; then
        echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
        exit 2
    fi
fi

# Loop-count safety: block mutating tools after an obviously runaway retry loop.
# Read-like tools returned earlier, so only Edit/Write/Bash/Agent reach this.
if [ "$PHASE" = "implementing" ] || [ "$PHASE" = "testing" ]; then
    if [ "$LOOP_COUNT" -ge 99 ]; then
        echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
        exit 2
    fi
fi

# Phase-specific guards.

case "$PHASE" in
    declare|requirements)
        # Agent work is blocked until requirements are fixed.
        if [ "$TOOL_NAME" = "Agent" ]; then
            echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
            exit 2
        fi
        # During declaration/requirements, only task files may be written.
        if [ -n "${FILE_PATH:-}" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == ${TASKS_DIR}/* ]] || [[ "$FILE_PATH" == tasks/vdgg/${VDGG_ID}/* ]]; then
                    exit 0
                fi
                echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                exit 2
            fi
        fi
        # requirements.md is mandatory before investigation starts.
        if [ "$PHASE" = "requirements" ] && [ "$TOOL_NAME" = "Bash" ]; then
            if echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+3[[:space:]]+investigating([[:space:]]|$)'; then
                REQ_FILE="${TASKS_DIR}/requirements.md"
                if [ ! -f "$REQ_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (requirements) [${VDGG_ID}]: requirements.md is required before investigation." >&2
                    exit 2
                fi
            fi
        fi
        ;;

    investigating|planning)
        # Investigation and planning may only update task documentation.
        if [ -n "${FILE_PATH:-}" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == ${TASKS_DIR}/* ]] || [[ "$FILE_PATH" == tasks/vdgg/${VDGG_ID}/* ]]; then
                    exit 0
                fi
                echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                exit 2
            fi
        fi
        ;;

    task-selected)
        # Once a task is selected, advance to implementing before editing files.
        if [ -n "${FILE_PATH:-}" ]; then
            echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
            exit 2
        fi
        ;;

    implementing|testing)
        # Implementation edits must stay inside the task allowlist declared by
        # vdgg_task_begin. Task notes under tasks/vdgg/{id}/ stay editable.
        if [ -n "${FILE_PATH:-}" ]; then
            if [ -n "$FILE_PATH" ] \
                && [[ "$FILE_PATH" != ${TASKS_DIR}/* ]] \
                && [[ "$FILE_PATH" != tasks/vdgg/${VDGG_ID}/* ]]; then
                if [ -z "$TASK_ALLOWLIST_FILE" ] || [ ! -f "$TASK_ALLOWLIST_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: No active task allowlist. Run vdgg_task_begin before editing implementation files." >&2
                    exit 2
                fi
                NORMALIZED_PATH=$(_vdgg_normalize_project_path "$FILE_PATH")
                if ! grep -qxF "$NORMALIZED_PATH" "$TASK_ALLOWLIST_FILE"; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: Task allowlist blocks edit: ${NORMALIZED_PATH}" >&2
                    exit 2
                fi
            fi
        fi
        # Commit only after verification and progress are complete.
        if [ "$TOOL_NAME" = "Bash" ]; then
            if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
                echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                exit 2
            fi
            # A failed test must go through reflection before more implementation.
            if [ "$PHASE" = "testing" ] && echo "$COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+[0-9]+[[:space:]]+implementing'; then
                echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                exit 2
            fi
            # verified requires a review gate: either the simplify sentinel or the
            # explicit review sentinel written by vdgg_review_run,
            # and the review must not have edited implementation code.
            if [ "$PHASE" = "testing" ] && echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
                # When a task allowlist is active, the task gate must have passed.
                if [ -n "$TASK_ALLOWLIST_FILE" ] && [ -f "$TASK_ALLOWLIST_FILE" ] && [ ! -f "$TASK_GATE_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: Run vdgg_task_gate successfully before verified." >&2
                    exit 2
                fi
                SIMPLIFY_SENTINEL="$CWD/.claude/.vdgg-simplify-sentinel-${VDGG_ID}-${LOOP_COUNT}"
                REVIEW_SENTINEL="$CWD/.claude/.vdgg-review-sentinel-${VDGG_ID}-${LOOP_COUNT}"
                GATE_FILE=""
                if [ -f "$SIMPLIFY_SENTINEL" ]; then
                    GATE_FILE="$SIMPLIFY_SENTINEL"
                elif [ -f "$REVIEW_SENTINEL" ]; then
                    GATE_FILE="$REVIEW_SENTINEL"
                fi
                if [ -z "$GATE_FILE" ]; then
                    echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                    exit 2
                fi
                MODIFIED=$(grep '^modified=' "$GATE_FILE" | head -1 | sed 's/^modified=//')
                if [ "$MODIFIED" = "1" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                # Consume the sentinels so they cannot be reused by a later cycle.
                rm -f "$SIMPLIFY_SENTINEL" "$REVIEW_SENTINEL"
            fi
        fi
        ;;

    reflection)
        # Reflection can only update retry investigation notes and progress.
        if [ -n "${FILE_PATH:-}" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == "${TASKS_DIR}/progress.md" ]] \
                    || [[ "$FILE_PATH" == "${TASKS_DIR}"/investigation-r*.md ]]; then
                    exit 0
                fi
            fi
            echo "VibesDeGoGo! reflection [${VDGG_ID}]: Reflection must update retry investigation and progress before returning to implementation." >&2
            exit 2
        fi
        # Reflection may use Bash, but it may not jump directly to verified.
        if [ "$TOOL_NAME" = "Bash" ]; then
            # verified is only reachable from testing after review.
            if echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
                echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                exit 2
            fi
            if echo "$COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+6[[:space:]]+implementing'; then
                PROGRESS_FILE="${TASKS_DIR}/progress.md"
                RETRY_INVESTIGATION_FILE="${TASKS_DIR}/investigation-r${LOOP_COUNT}.md"
                if [ ! -f "$RETRY_INVESTIGATION_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                if [ ! -f "$PROGRESS_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                STATE_MTIME=$(_vdgg_mtime "$STATE_FILE")
                RETRY_INVESTIGATION_MTIME=$(_vdgg_mtime "$RETRY_INVESTIGATION_FILE")
                PROGRESS_MTIME=$(_vdgg_mtime "$PROGRESS_FILE")
                if [ "$RETRY_INVESTIGATION_MTIME" -le "$STATE_MTIME" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                if [ "$PROGRESS_MTIME" -le "$STATE_MTIME" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
            fi
        fi
        ;;

    verified|progress|commit)
        # No code edits after verification; only progress/version metadata may change.
        if [ -n "${FILE_PATH:-}" ]; then
            if { [ "$PHASE" = "progress" ] || [ "$PHASE" = "commit" ]; } && [ -n "$FILE_PATH" ]; then
                # progress.md remains editable for validation and commit notes.
                if [[ "$FILE_PATH" == "${TASKS_DIR}/progress.md" ]]; then
                    exit 0
                fi
                # Version files explicitly configured in `.vdgg-target` are allowed.
                TARGET_FILE="$CWD/.vdgg-target"
                if [ -f "$TARGET_FILE" ]; then
                    ALLOWED_PATHS=$(grep -E '^VERSION_FILE_[0-9]+_PATH=' "$TARGET_FILE" \
                        | sed -E 's/^[^=]*=//' \
                        | sed -E 's/^"(.*)"$/\1/' \
                        | sed -E "s/^'(.*)'\$/\\1/" \
                        | grep -v '^$' || true)
                    while IFS= read -r allowed; do
                        [ -z "$allowed" ] && continue
                        if [[ "$FILE_PATH" == "${allowed}" ]] \
                            || [[ "$FILE_PATH" == "$CWD/${allowed}" ]]; then
                            exit 0
                        fi
                    done <<< "$ALLOWED_PATHS"
                fi
            fi
            echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
            exit 2
        fi
        # branch-pr workflow forbids committing or pushing directly on the base branch.
        if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "commit" ]; then
            # Defaults match SKILL.md unless `.vdgg-target` overrides them.
            WF=branch-pr; BB=""
            if [ -f "$CWD/.vdgg-target" ]; then
                WF=$( { grep -E '^WORKFLOW=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
                BB=$( { grep -E '^BASE_BRANCH=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
                WF=${WF:-branch-pr}
            fi
            if [ "$WF" != "trunk" ]; then
                if [ -z "$BB" ]; then
                    BB=$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
                    BB=${BB#origin/}
                    BB=${BB:-main}
                fi
                CURBR=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                # Escape base branch for grep -E before matching push commands.
                BB_RE=$(printf '%s' "$BB" | sed 's/[^[:alnum:]]/\\&/g')
                if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+(commit|push)([[:space:]]|$)'; then
                    if [ "$CURBR" = "$BB" ]; then
                        echo "VibesDeGoGo! Step ${STEP} (commit) [${VDGG_ID}]: branch-pr workflow requires committing/pushing the feature branch and opening a PR." >&2
                        exit 2
                    fi
                    if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+push' \
                        && echo "$COMMAND" | grep -qE "(^|[^a-zA-Z0-9_/.-])${BB_RE}([^a-zA-Z0-9_/.-]|\$)"; then
                        echo "VibesDeGoGo! Step ${STEP} (commit) [${VDGG_ID}]: branch-pr workflow requires committing/pushing the feature branch and opening a PR." >&2
                        exit 2
                    fi
                fi
            fi
        fi
        ;;

    *)
        # Unknown phase: fail closed. Read-like tools already returned 0 at the
        # tool-name switch, so only mutating tools (Edit/Write/Bash/Agent) reach
        # here. A crafted state file (or any future phase the guards don't know)
        # must not silently disable enforcement. vdgg_state_write also rejects
        # unknown phases at the source; this is defense in depth.
        echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Unknown workflow phase '${PHASE}'. Tool call blocked by VibesDeGoGo! hook." >&2
        exit 2
        ;;
esac

exit 0
