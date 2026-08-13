#!/bin/bash
set -euo pipefail

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # Best-effort cwd extraction without jq: parse the "cwd" field with grep/sed.
  FALLBACK_CWD=$(printf '%s' "$INPUT" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
  FALLBACK_CWD="${FALLBACK_CWD:-$PWD}"
  # Resolve to the git toplevel the same way the jq path does.
  if R=$(git -C "$FALLBACK_CWD" rev-parse --show-toplevel 2>/dev/null); then
    FALLBACK_CWD="$R"
  fi
  # Fail-open when inactive: no active session means nothing to protect, so stay
  # out of the way rather than blocking every tool in unrelated repositories.
  # Exception: when the repository opts in with VDGG_REQUIRED=on, tools cannot
  # be classified without jq, so fall through to the fail-closed branch below.
  if [ ! -f "$FALLBACK_CWD/.codex/.vdgg-active" ]; then
    FALLBACK_REQUIRED=$(grep -m1 '^VDGG_REQUIRED=' "$FALLBACK_CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' || true)
    if [ "$FALLBACK_REQUIRED" != "on" ]; then
      exit 0
    fi
  fi
  # Active session: cannot parse JSON properly, so fail closed. Allow jq-install
  # commands through so the user can fix the missing dependency.
  if printf '%s' "$INPUT" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*(brew[[:space:]]+(install|reinstall)|apt(-get)?[[:space:]]+install|apk[[:space:]]+add|dnf[[:space:]]+install|yum[[:space:]]+install|pacman[[:space:]]+-S)[[:space:]]+[^"]*jq'; then
    exit 0
  fi
  {
    echo "VibesDeGoGo! for Codex: jq is required for hooks but was not found on PATH."
    echo "  macOS:               brew install jq"
    echo "  Debian/Ubuntu/WSL:   sudo apt-get install jq"
    echo "  Alpine:              apk add jq"
    echo "  Fedora/RHEL:         sudo dnf install jq"
  } >&2
  exit 2
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$(pwd)
if ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  CWD="$ROOT"
fi

# Entry gate (VDGG_REQUIRED): normally an unarmed session (no active id or
# state) leaves the hook fail-open so unrelated repositories are never
# touched. A repository can opt out of that leniency with VDGG_REQUIRED=on in
# .vdgg-target: code-modifying tools are then denied until a session is armed
# through vdgg_state_init. This closes the hole where an agent that ignores
# the workflow contract simply never arms the gates (arming must not be a
# voluntary act). Only the literal value `on` activates the gate. Gated tools
# match the armed path (apply_patch/Edit/Write/Bash); other tools pass, as
# they do when armed. Known limit (same as the sidecar guard): a write hidden
# behind a shell variable or an interpreter one-liner evades the literal
# segment match.
_vdgg_required() {
  local target="$CWD/.vdgg-target" v
  [ -f "$target" ] || return 1
  v=$(grep -m1 '^VDGG_REQUIRED=' "$target" | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' || true)
  [ "$v" = "on" ]
}

_vdgg_entry_deny() {
  echo "VibesDeGoGo! for Codex entry gate: this repository sets VDGG_REQUIRED=on in .vdgg-target and no VibesDeGoGo! session is armed. Code-modifying tools are blocked until Step 1 runs: source the skill's scripts/vdgg-state.sh and run vdgg_state_init. Only a human may relax this by editing .vdgg-target." >&2
  exit 2
}

_vdgg_entry_gate() {
  local tool cmd segs seg seg_checked verb
  tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
  case "$tool" in
    apply_patch|Edit|Write)
      _vdgg_entry_deny
      ;;
    Bash)
      cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
      segs="$cmd"
      segs="${segs//&&/$'\n'}"
      segs="${segs//||/$'\n'}"
      segs="${segs//;/$'\n'}"
      segs="${segs//|/$'\n'}"
      while IFS= read -r seg; do
        # Redirections to /dev/null|stdout|stderr do not modify the
        # repository; strip them (fd dups like 2>&1 are already excluded by
        # the [^&] below) so read-only idioms are not falsely denied.
        seg_checked=$(printf '%s' "$seg" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/(null|stdout|stderr)##g')
        if printf '%s' "$seg_checked" | grep -qE '(>[^&]|>>|(^|[[:space:]])tee([[:space:]]|$))'; then
          _vdgg_entry_deny
        fi
        if printf '%s' "$seg" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
          _vdgg_entry_deny
        fi
        verb=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//')
        case "$verb" in
          rm|mv|cp|dd|install|truncate|touch|ln|patch|mkfifo|apply_patch)
            # apply_patch also arrives as a shell command in some Codex
            # versions, not only as the apply_patch tool.
            _vdgg_entry_deny
            ;;
          sed|perl)
            if printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*i'; then
              _vdgg_entry_deny
            fi
            ;;
        esac
      done <<< "$segs"
      exit 0
      ;;
    *)
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

ACTIVE_FILE="$CWD/.codex/.vdgg-active"
[ -f "$ACTIVE_FILE" ] || _vdgg_unarmed_exit
VDGG_ID=$(cat "$ACTIVE_FILE")
[ -n "$VDGG_ID" ] || _vdgg_unarmed_exit
STATE_FILE="$CWD/.codex/.vdgg-state-${VDGG_ID}"
[ -f "$STATE_FILE" ] || _vdgg_unarmed_exit

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
PHASE=$(grep '^phase=' "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep '^step=' "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT=$(grep '^loop_count=' "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT="${LOOP_COUNT:-0}"
TASK_ALLOWLIST_FILE=$(grep '^task_allowlist_file=' "$STATE_FILE" | cut -d= -f2- || true)
TASK_GATE_FILE="$CWD/.codex/.vdgg-task-gate-${VDGG_ID}-${LOOP_COUNT}"
TASKS_DIR="$CWD/tasks/vdgg/${VDGG_ID}"

block() {
  echo "VibesDeGoGo! for Codex [${VDGG_ID}]: $1" >&2
  exit 2
}

# Portable mtime in epoch seconds. BSD/macOS `stat -f %m` gives the epoch. On
# GNU/Linux `-f` means --file-system and prints non-numeric text with exit 0, so
# the raw `||` chain is not enough: validate the result is all-digits and fall
# back to `stat -c %Y`, then to 0.
_vdgg_mtime() {
  local m
  m=$(stat -f %m "$1" 2>/dev/null || true)
  case "$m" in ''|*[!0-9]*) m=$(stat -c %Y "$1" 2>/dev/null || true) ;; esac
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s\n' "$m"
}

patch_files() {
  printf '%s\n' "$COMMAND" \
    | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.*)$/\2/p'
}

changed_files() {
  case "$TOOL_NAME" in
    apply_patch)
      patch_files
      ;;
    Edit|Write)
      printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // empty'
      ;;
  esac
}

normalize_project_path() {
  local p="$1"
  case "$p" in
    "$CWD"/*) p="${p#"$CWD"/}" ;;
    ./*) p="${p#./}" ;;
  esac
  printf '%s\n' "$p"
}

path_is_tasks_file() {
  local p="$1"
  [[ "$p" == "$TASKS_DIR/"* ]] || [[ "$p" == "tasks/vdgg/${VDGG_ID}/"* ]]
}

path_is_task_allowlisted() {
  local p
  p=$(normalize_project_path "$1")
  [ -n "${TASK_ALLOWLIST_FILE:-}" ] || return 1
  [ -f "$TASK_ALLOWLIST_FILE" ] || return 1
  grep -qxF "$p" "$TASK_ALLOWLIST_FILE"
}

path_is_sidecar_file() {
  local p="$1"
  [[ "$p" == *".codex/.vdgg-"* ]] || [[ "$p" == *".vdgg-target" ]]
}

if [ "$TOOL_NAME" = "Bash" ] && [ -f "$CWD/.codex/.vdgg-error-pending" ]; then
  if ! printf '%s' "$COMMAND" | grep -qF '[Error Acknowledged]'; then
    block "Previous command failed. Acknowledge it with [Error Acknowledged] before running another command."
  fi
  rm -f "$CWD/.codex/.vdgg-error-pending"
fi

if [ "$TOOL_NAME" = "Bash" ]; then
  # Sidecar files (.codex/.vdgg-*) may only be written through vdgg_state_*
  # helpers, and .vdgg-target only by a human (it holds executed config:
  # REVIEW_COMMAND, STEP*_EXECUTOR_COMMAND). Split the command into shell
  # segments so a `git commit` segment (whose message may mention such a path)
  # cannot shield a mutating segment in the same line, e.g.
  #   git commit -m x && rm -f .codex/.vdgg-active
  # Whitelist model (fail-closed): a segment mentioning a protected path is
  # allowed only when it is a git-commit segment or a genuine read (leading
  # read-only verb, no output redirection / tee). Everything else (python/perl,
  # dd/install, redirects, file ops) is denied. Known limit: a path hidden
  # behind a shell variable or command substitution evades the literal match.
  _vdgg_segs="$COMMAND"
  _vdgg_segs="${_vdgg_segs//&&/$'\n'}"
  _vdgg_segs="${_vdgg_segs//||/$'\n'}"
  _vdgg_segs="${_vdgg_segs//;/$'\n'}"
  _vdgg_segs="${_vdgg_segs//|/$'\n'}"
  while IFS= read -r _vdgg_seg; do
    case "$_vdgg_seg" in
      *".codex/.vdgg-"*|*".vdgg-target"*) ;;
      *) continue ;;
    esac
    if printf '%s' "$_vdgg_seg" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
      continue
    fi
    _vdgg_verb=$(printf '%s' "$_vdgg_seg" | sed -E 's/^[[:space:]]*//; s/[[:space:]].*//')
    _vdgg_read_ok=0
    case "$_vdgg_verb" in
      cat|grep|egrep|fgrep|test|'['|ls|head|tail|wc|diff|cmp|stat|od|hexdump|file|realpath|readlink)
        if ! printf '%s' "$_vdgg_seg" | grep -qE '(>[^&]|>>|(^|[[:space:]])tee([[:space:]]|$))'; then
          _vdgg_read_ok=1
        fi
        ;;
    esac
    [ "$_vdgg_read_ok" -eq 1 ] || block "Direct writes to VibesDeGoGo! sidecar/target files are blocked. Use vdgg_state_* helpers; .vdgg-target must be set by a human."
  done <<< "$_vdgg_segs"
fi

if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    path_is_sidecar_file "$file_path" && block "Direct edits to VibesDeGoGo! sidecar files are blocked. Use vdgg_state_* helpers."
  done < <(changed_files)
fi

if [ "$TOOL_NAME" = "Bash" ] && printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+'; then
  TARGET_STEP=$(printf '%s' "$COMMAND" | sed -nE 's/.*vdgg_state_(advance|loop|write)[[:space:]]+([0-9]+).*/\2/p' | head -1)
  if [ -n "$TARGET_STEP" ]; then
    if ! printf '%s' "$COMMAND" | grep -qF "[VibesDeGoGo! Step ${TARGET_STEP} Start]" \
      && ! { [ "$TARGET_STEP" = "2" ] && printf '%s' "$COMMAND" | grep -qF '[VibesDeGoGo! Declaration]'; }; then
      block "State transition commands must include the matching VibesDeGoGo! Step declaration."
    fi
  fi
fi

if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "requirements" ]; then
  if printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+3[[:space:]]+investigating'; then
    [ -f "$TASKS_DIR/requirements.md" ] || block "requirements.md is required before investigation."
  fi
fi

if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "implementing" ]; then
  TEST_PATTERN='swift[[:space:]]+test|xcodebuild[[:space:]]+[^|]*[[:space:]]test|pytest|npm[[:space:]]+(run[[:space:]]+)?test|pnpm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+(run[[:space:]]+)?test|go[[:space:]]+test|cargo[[:space:]]+test|jest|vitest|mocha'
  if [ -f "$CWD/.vdgg-target" ]; then
    EXTRA=$(grep '^TEST_COMMAND_PATTERN=' "$CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' | head -1)
    [ -z "${EXTRA:-}" ] || TEST_PATTERN="${TEST_PATTERN}|${EXTRA}"
  fi
  if printf '%s' "$COMMAND" | grep -qE "(^|[[:space:];&|(])(${TEST_PATTERN})([[:space:]]|$)"; then
    block "Tests are blocked in implementing. Advance to Step 7 testing first."
  fi
fi

case "$PHASE" in
  declare|requirements|investigating|planning)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        path_is_tasks_file "$file_path" || block "Only the active tasks/vdgg/${VDGG_ID}/ files may be edited in phase ${PHASE}."
      done < <(changed_files)
    fi
    ;;
  task-selected)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      block "Edits are blocked in task-selected. Advance to implementing first."
    fi
    ;;
  implementing|testing)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        # Task notes under tasks/vdgg/{id}/ stay editable without allowlisting.
        path_is_tasks_file "$file_path" && continue
        [ -n "${TASK_ALLOWLIST_FILE:-}" ] && [ -f "$TASK_ALLOWLIST_FILE" ] \
          || block "No active task allowlist. Run vdgg_task_begin before editing implementation files."
        path_is_task_allowlisted "$file_path" \
          || block "Task allowlist blocks edit: $(normalize_project_path "$file_path")"
      done < <(changed_files)
    fi
    if [ "$TOOL_NAME" = "Bash" ] && printf '%s' "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
      block "Commit is blocked before Step 9."
    fi
    # A failed test must go through reflection before more implementation.
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "testing" ] \
      && printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+[0-9]+[[:space:]]+implementing'; then
      block "A failed test must go through reflection (Step 6-R) before returning to implementing."
    fi
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "testing" ]; then
      if printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
        if [ -n "${TASK_ALLOWLIST_FILE:-}" ] && [ -f "$TASK_ALLOWLIST_FILE" ]; then
          [ -f "$TASK_GATE_FILE" ] || block "Run vdgg_task_gate successfully before verified."
        fi
        REVIEW_FILE="$CWD/.codex/.vdgg-review-sentinel-${VDGG_ID}-${LOOP_COUNT}"
        [ -f "$REVIEW_FILE" ] || block "Run the Codex review gate with vdgg_state_mark_reviewed before verified."
        MODIFIED=$(grep '^modified=' "$REVIEW_FILE" | sed 's/^modified=//' | head -1)
        [ "$MODIFIED" != "1" ] || block "Review changed files. Go through reflection and retest."
        rm -f "$REVIEW_FILE"
      fi
    fi
    ;;
  reflection)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        case "$file_path" in
          "$TASKS_DIR/progress.md"|tasks/vdgg/"$VDGG_ID"/progress.md|"$TASKS_DIR"/investigation-r*.md|tasks/vdgg/"$VDGG_ID"/investigation-r*.md) ;;
          *) block "Reflection may only edit progress.md and investigation-r*.md." ;;
        esac
      done < <(changed_files)
    fi
    # verified is only reachable from testing after review, never from reflection.
    if [ "$TOOL_NAME" = "Bash" ] && printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
      block "verified is only reachable from testing after review, not from reflection."
    fi
    # Returning to implementing requires a fresh retry investigation: both
    # investigation-r{loop}.md and progress.md must exist and be newer than the
    # state file (mtime, seconds precision). This stops a blind retry that skips
    # analysis of the failure. Known limit: seconds-precision mtime can tie if a
    # file is written in the same second the state was last written.
    if [ "$TOOL_NAME" = "Bash" ] \
      && printf '%s' "$COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+6[[:space:]]+implementing'; then
      RETRY_INVESTIGATION_FILE="$TASKS_DIR/investigation-r${LOOP_COUNT}.md"
      PROGRESS_FILE="$TASKS_DIR/progress.md"
      [ -f "$RETRY_INVESTIGATION_FILE" ] || block "Write a retry investigation (investigation-r${LOOP_COUNT}.md) before returning to implementing."
      [ -f "$PROGRESS_FILE" ] || block "Update progress.md before returning to implementing."
      STATE_MTIME=$(_vdgg_mtime "$STATE_FILE")
      [ "$(_vdgg_mtime "$RETRY_INVESTIGATION_FILE")" -gt "$STATE_MTIME" ] \
        || block "Write a fresh retry investigation (investigation-r${LOOP_COUNT}.md) before returning to implementing."
      [ "$(_vdgg_mtime "$PROGRESS_FILE")" -gt "$STATE_MTIME" ] \
        || block "Update progress.md before returning to implementing."
    fi
    ;;
  verified|progress|commit)
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        path_is_tasks_file "$file_path" && continue
        # No code edits after verification; configured version files may change
        # only during progress/commit, never in verified.
        if [ "$PHASE" != "verified" ] && [ -f "$CWD/.vdgg-target" ]; then
          if grep -E '^VERSION_FILE_[0-9]+_PATH=' "$CWD/.vdgg-target" | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' | grep -qx "$file_path"; then
            continue
          fi
        fi
        block "No code edits after verification; only progress and configured version files may be edited in phase ${PHASE}."
      done < <(changed_files)
    fi
    # branch-pr workflow forbids committing or pushing directly on the base branch.
    if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "commit" ]; then
      WF=branch-pr; BB=""
      if [ -f "$CWD/.vdgg-target" ]; then
        WF=$( { grep -E '^WORKFLOW=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
        BB=$( { grep -E '^BASE_BRANCH=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
        case "$WF" in trunk|branch-pr) ;; *) WF=branch-pr ;; esac
      fi
      if [ "$WF" != "trunk" ]; then
        if [ -z "$BB" ]; then
          BB=$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
          BB=${BB#origin/}; BB=${BB:-main}
        fi
        CURBR=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        BB_RE=$(printf '%s' "$BB" | sed 's/[^[:alnum:]]/\\&/g')
        if printf '%s' "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+(commit|push)([[:space:]]|$)'; then
          if [ "$CURBR" = "$BB" ]; then
            block "branch-pr workflow requires committing/pushing a feature branch and opening a PR, not the base branch."
          fi
          if printf '%s' "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+push' \
            && printf '%s' "$COMMAND" | grep -qE "(^|[^a-zA-Z0-9_/.-])${BB_RE}([^a-zA-Z0-9_/.-]|\$)"; then
            block "branch-pr workflow: do not push the base branch."
          fi
        fi
      fi
    fi
    ;;
  *)
    # Unknown phase: fail closed for mutating tools and Bash. vdgg_state_write
    # also rejects unknown phases at the source; this is defense in depth against
    # a crafted state file.
    if [ "$TOOL_NAME" = "apply_patch" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Bash" ]; then
      block "Unknown workflow phase '${PHASE}'."
    fi
    ;;
esac

exit 0
