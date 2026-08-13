#!/bin/bash
set -euo pipefail

_vdgg_resolve_root() {
  local cwd="${1:-$(pwd)}"
  git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$cwd"
}

if [ -z "${VDGG_CWD:-}" ]; then
  VDGG_CWD=$(_vdgg_resolve_root "$(pwd)")
fi
VDGG_STATE_DIR="${VDGG_STATE_DIR:-${VDGG_CWD}/.codex}"
VDGG_TASKS_DIR="${VDGG_TASKS_DIR:-${VDGG_CWD}/tasks/vdgg}"
VDGG_CONFIG_DIR="${VDGG_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/vdgg}"
# BASH_SOURCE is bash-only; zsh sets $0 to the sourced file's path instead.
_VDGG_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

_vdgg_generate_id() {
  local timestamp random
  timestamp=$(date +%Y%m%d-%H%M)
  # Truncate to 4 hex chars to match the documented YYYYMMDD-HHMM-xxxx format
  # and stay in parity with the Claude edition.
  random=$(LC_ALL=C od -An -N8 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-4)
  echo "${timestamp}-${random}"
}

_vdgg_active_file() { echo "${VDGG_STATE_DIR}/.vdgg-active"; }
_vdgg_state_file_for_id() { echo "${VDGG_STATE_DIR}/.vdgg-state-$1"; }
_vdgg_review_file_for_id() {
  local id="$1" loop="$2"
  echo "${VDGG_STATE_DIR}/.vdgg-review-sentinel-${id}-${loop}"
}
_vdgg_task_allowlist_file_for_id() {
  local id="$1" loop="$2"
  echo "${VDGG_STATE_DIR}/.vdgg-task-allowlist-${id}-${loop}"
}
_vdgg_task_baseline_dir_for_id() {
  local id="$1" loop="$2"
  echo "${VDGG_STATE_DIR}/.vdgg-task-baseline-${id}-${loop}"
}
_vdgg_task_baseline_status_for_id() {
  local id="$1" loop="$2"
  echo "${VDGG_STATE_DIR}/.vdgg-task-baseline-status-${id}-${loop}"
}
_vdgg_task_gate_file_for_id() {
  local id="$1" loop="$2"
  echo "${VDGG_STATE_DIR}/.vdgg-task-gate-${id}-${loop}"
}

_vdgg_get_active_id() {
  local active_file
  active_file=$(_vdgg_active_file)
  [ -f "$active_file" ] && cat "$active_file" || true
}

_vdgg_get_state_file() {
  local id
  id=$(_vdgg_get_active_id)
  [ -n "$id" ] || return 1
  _vdgg_state_file_for_id "$id"
}

_vdgg_rm_glob() {
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -name "$2" -type f -exec rm -f {} + 2>/dev/null || true
}

_vdgg_rm_dir_glob() {
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -name "$2" -type d -exec rm -rf {} + 2>/dev/null || true
}

# NOTE: never declare `local path` in these helpers — when the script is
# sourced into zsh, `path` is tied to $PATH and localizing it empties PATH.
_vdgg_normalize_path() {
  local entry="$1"
  case "$entry" in
    "$VDGG_CWD"/*) entry="${entry#"$VDGG_CWD"/}" ;;
    ./*) entry="${entry#./}" ;;
  esac
  printf '%s\n' "$entry"
}

_vdgg_path_is_safe_relative() {
  local entry
  entry=$(_vdgg_normalize_path "$1")
  [ -n "$entry" ] || return 1
  case "$entry" in
    /*|../*|*/../*|..|.) return 1 ;;
  esac
  return 0
}

_vdgg_task_loop() {
  local state_file loop
  state_file=$(_vdgg_get_state_file)
  loop=$(grep '^loop_count=' "$state_file" | cut -d= -f2)
  printf '%s\n' "${loop:-0}"
}

_vdgg_check_step_transition() {
  local current="$1" next="$2"
  if ! [[ "$current" =~ ^[0-9]+$ ]] || ! [[ "$next" =~ ^[0-9]+$ ]]; then
    echo "vdgg-state: invalid or blocked state transition" >&2
    return 1
  fi
  if [ "$next" -eq "$current" ] || [ "$next" -eq $((current + 1)) ]; then
    return 0
  fi
  if [ "$current" -eq 8 ] && [ "$next" -eq 5 ]; then return 0; fi
  if [ "$current" -eq 7 ] && [ "$next" -eq 6 ]; then return 0; fi
  echo "vdgg-state: invalid or blocked state transition" >&2
  return 1
}

vdgg_get_id() {
  _vdgg_get_active_id
}

# Append VibesDeGoGo!'s own sidecar patterns to the project .gitignore if it
# exists and doesn't already contain them. Idempotent (uses a marker comment).
# Skips silently when no .gitignore is present (we don't create one).
# This prevents Step 9 from being blocked by surprise untracked .codex/ files
# at commit time.
_vdgg_ensure_gitignore() {
  local gitignore="${VDGG_CWD}/.gitignore"
  [ -f "$gitignore" ] || return 0
  if grep -qF '# Codex / VibesDeGoGo!' "$gitignore"; then
    return 0
  fi
  cat >> "$gitignore" <<'EOF'

# Codex / VibesDeGoGo!
.codex/.vdgg-*
EOF
  echo "vdgg-state: appended VibesDeGoGo! patterns to ${gitignore}" >&2
}

_vdgg_formation_keys() {
  printf '%s\n' \
    STEP_0_AI STEP_1_AI STEP_2_AI STEP_3_AI STEP_4_AI STEP_5_AI \
    STEP_6_AI STEP_6R_AI STEP_7_AI STEP_8_AI STEP_9_AI STEP_0_GRILL_AI
}

_vdgg_name_is_safe() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

_vdgg_step_key_is_valid() {
  case "$1" in
    STEP_0_AI|STEP_1_AI|STEP_2_AI|STEP_3_AI|STEP_4_AI|STEP_5_AI|STEP_6_AI|STEP_6R_AI|STEP_7_AI|STEP_8_AI|STEP_9_AI|STEP_0_GRILL_AI) return 0 ;;
    *) return 1 ;;
  esac
}

_vdgg_formation_file() {
  printf '%s/formations/%s.conf\n' "$VDGG_CONFIG_DIR" "$1"
}

_vdgg_executor_file() {
  printf '%s/executors/%s.conf\n' "$VDGG_CONFIG_DIR" "$1"
}

# --- Friendly formation syntax ------------------------------------------------
# One line per delegated seat: "<seat>: <ai> [model] [effort]".
# Seats: 0, 3, 4, 6, 6R, 7, grill (case-insensitive), plus "*" which assigns
# the non-interactive seats 3, 4, 6, 6R, 7 at once; an explicit seat line wins
# over "*" regardless of order. Unlisted seats default to inline.
# Values: "inline", the builtins "claude"/"codex" (optional model and effort
# tokens, effort recognized by a per-vendor closed vocabulary), or a bare
# executor name resolved through executors/<name>.conf as before.

_vdgg_seat_to_key() {
  case "$1" in
    0) echo STEP_0_AI ;;
    1) echo STEP_1_AI ;;
    2) echo STEP_2_AI ;;
    3) echo STEP_3_AI ;;
    4) echo STEP_4_AI ;;
    5) echo STEP_5_AI ;;
    6) echo STEP_6_AI ;;
    6R|6r) echo STEP_6R_AI ;;
    7) echo STEP_7_AI ;;
    8) echo STEP_8_AI ;;
    9) echo STEP_9_AI ;;
    0G|0g|[Gg][Rr][Ii][Ll][Ll]) echo STEP_0_GRILL_AI ;;
    *) return 1 ;;
  esac
}

# Model shorthands. Each expands to the bundled "claude" wrapper plus a
# full model id, so the rest of the pipeline needs no special case.
_vdgg_model_alias() {
  case "$1" in
    opus5) echo claude-opus-5 ;;
    sonnet5) echo claude-sonnet-5 ;;
    fable5) echo claude-fable-5 ;;
    haiku45) echo claude-haiku-4-5 ;;
    *) return 1 ;;
  esac
}

_vdgg_key_in_wildcard() {
  case "$1" in
    STEP_3_AI|STEP_4_AI|STEP_6_AI|STEP_6R_AI|STEP_7_AI) return 0 ;;
  esac
  return 1
}

# First char must be alphanumeric so a token can never be mistaken for a CLI
# flag when it reaches an executor's argv.
_vdgg_token_is_safe() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# Closed per-vendor effort vocabulary, matched with case patterns (portable
# across bash and zsh, which does not word-split unquoted expansions).
_vdgg_is_effort_token() {
  case "$1" in
    claude) case "$2" in low|medium|high) return 0 ;; esac ;;
    codex) case "$2" in minimal|low|medium|high|xhigh) return 0 ;; esac ;;
  esac
  return 1
}

_vdgg_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

# Parse a seat value "<name> [model] [effort]" into _VDGG_SEAT_NAME,
# _VDGG_SEAT_MODEL, _VDGG_SEAT_EFFORT, enforcing the grammar (token charset,
# token count, tokens only on the builtins). $2 labels error messages.
# Single source of truth for the split — validation, preflight, and run time
# all call this so the interpretation can never drift between them.
_vdgg_parse_seat_value() {
  local value="$1" label="$2" tok1 tok2 extra tok
  _VDGG_SEAT_NAME="" _VDGG_SEAT_MODEL="" _VDGG_SEAT_EFFORT=""
  IFS=' 	' read -r _VDGG_SEAT_NAME tok1 tok2 extra <<< "$value"
  [ -n "$_VDGG_SEAT_NAME" ] || {
    echo "vdgg-formation: empty value for $label" >&2
    return 1
  }
  case "$_VDGG_SEAT_NAME" in
    primary|inline)
      [ -z "$tok1" ] || {
        echo "vdgg-formation: $_VDGG_SEAT_NAME takes no extra tokens ($label): $value" >&2
        return 1
      }
      _VDGG_SEAT_NAME="inline"
      ;;
    opus5|sonnet5|fable5|haiku45)
      [ -z "$tok1" ] || {
        echo "vdgg-formation: model shorthand '$_VDGG_SEAT_NAME' takes no extra tokens ($label): $value" >&2
        return 1
      }
      _VDGG_SEAT_MODEL=$(_vdgg_model_alias "$_VDGG_SEAT_NAME")
      _VDGG_SEAT_NAME="claude"
      ;;
    claude|codex)
      [ -z "$extra" ] || {
        echo "vdgg-formation: too many tokens for $label: $value" >&2
        return 1
      }
      for tok in "$tok1" "$tok2"; do
        [ -n "$tok" ] || continue
        _vdgg_token_is_safe "$tok" || {
          echo "vdgg-formation: invalid token for $label: $tok" >&2
          return 1
        }
        if [ -z "$_VDGG_SEAT_EFFORT" ] && _vdgg_is_effort_token "$_VDGG_SEAT_NAME" "$tok"; then
          _VDGG_SEAT_EFFORT="$tok"
        elif [ -z "$_VDGG_SEAT_MODEL" ]; then
          _VDGG_SEAT_MODEL="$tok"
        else
          echo "vdgg-formation: too many tokens for $label: $value" >&2
          return 1
        fi
      done
      ;;
    *)
      [ -z "$tok1" ] || {
        echo "vdgg-formation: executor '$_VDGG_SEAT_NAME' takes no model/effort tokens ($label); bake settings into executors/${_VDGG_SEAT_NAME}.conf instead" >&2
        return 1
      }
      _vdgg_name_is_safe "$_VDGG_SEAT_NAME" || {
        echo "vdgg-formation: invalid AI name for $label: $_VDGG_SEAT_NAME" >&2
        return 1
      }
      ;;
  esac
}

# Every seat accepts every value: any step can name the model it should run on.
# Seat 0 and Grill Me are conversational, so a bundled one-shot wrapper there
# answers in a single pass instead of holding a dialogue — that is a runtime
# consequence of the choice, not a reason to reject the configuration.
_vdgg_check_seat_value() {
  local key="$1" value="$2"
  _vdgg_parse_seat_value "$value" "$key" || return 1
}

_vdgg_validate_formation_file() {
  local formation="$1" file line seat value key seen=""
  _vdgg_name_is_safe "$formation" || {
    echo "vdgg-formation: invalid formation name: $formation" >&2
    return 1
  }
  file=$(_vdgg_formation_file "$formation")
  [ -f "$file" ] || {
    echo "vdgg-formation: formation not found: $file" >&2
    return 1
  }

  while IFS= read -r line || [ -n "$line" ]; do
    # Everything below a lone "--" is a free-form memo: stop reading.
    [ "$(_vdgg_trim "$line")" = "--" ] && break
    case "$line" in
      ''|'#'*) continue ;;
      STEP_*=*)
        echo "vdgg-formation: $file uses the old KEY=VALUE format. Rewrite each delegated seat as '<seat>: <ai>' (e.g. '3: codex' or '6: claude sonnet low'); unlisted seats default to inline." >&2
        return 1
        ;;
      *:*) ;;
      *)
        echo "vdgg-formation: invalid line in $file: $line (expected '<seat>: <ai> [model] [effort]')" >&2
        return 1
        ;;
    esac
    seat=$(_vdgg_trim "${line%%:*}")
    value=$(_vdgg_trim "${line#*:}")
    if [ "$seat" = "*" ]; then
      key="*"
    else
      key=$(_vdgg_seat_to_key "$seat") || {
        echo "vdgg-formation: unknown seat in $file: $seat (valid: 0, 0G, 1, 2, 3, 4, 5, 6, 6R, 7, 8, 9, *)" >&2
        return 1
      }
    fi
    case "
$seen
" in
      *"
$key
"*) echo "vdgg-formation: duplicate seat in $file: $seat" >&2; return 1 ;;
    esac
    seen="${seen}${seen:+
}${key}"
    # For "*" lines the key is the literal "*": it never matches the
    # interactive seats, and error messages show what the user wrote.
    _vdgg_check_seat_value "$key" "$value" || return 1
  done < "$file"
}

_vdgg_formation_value() {
  local formation="$1" step_key="$2" file line seat value key explicit="" wildcard=""
  file=$(_vdgg_formation_file "$formation")
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$(_vdgg_trim "$line")" = "--" ] && break
    case "$line" in
      ''|'#'*) continue ;;
    esac
    seat=$(_vdgg_trim "${line%%:*}")
    value=$(_vdgg_trim "${line#*:}")
    if [ "$seat" = "*" ]; then
      wildcard="$value"
      continue
    fi
    key=$(_vdgg_seat_to_key "$seat" 2>/dev/null) || continue
    [ "$key" = "$step_key" ] && explicit="$value"
  done < "$file"
  local result="inline"
  if [ -n "$explicit" ]; then
    result="$explicit"
  elif [ -n "$wildcard" ] && _vdgg_key_in_wildcard "$step_key"; then
    result="$wildcard"
  fi
  # "primary" is the file-facing word for "the session's own model"; every
  # caller downstream already understands "inline", so normalize here.
  case "$result" in
    primary) result="inline" ;;
  esac
  printf '%s\n' "$result"
}

# Resolve a validated seat value ("<name> [model] [effort]") to an executable.
# A user-defined executors/<name>.conf wins over the builtin claude/codex
# wrappers; model/effort tokens are only meaningful on the builtin path.
_vdgg_seat_command() {
  local value="$1" label="${2:-seat value}" name bundled
  _vdgg_parse_seat_value "$value" "$label" || return 1
  name="$_VDGG_SEAT_NAME"
  if [ -f "$(_vdgg_executor_file "$name")" ]; then
    [ -z "${_VDGG_SEAT_MODEL}${_VDGG_SEAT_EFFORT}" ] || {
      echo "vdgg-formation: executors/${name}.conf overrides the builtin; model/effort tokens are not allowed: $value" >&2
      return 1
    }
    _vdgg_executor_command "$name"
    return
  fi
  case "$name" in
    claude|codex)
      bundled="${_VDGG_SCRIPT_DIR}/vdgg-exec-${name}.sh"
      [ -f "$bundled" ] && [ -x "$bundled" ] || {
        echo "vdgg-formation: bundled executor missing or not executable: $bundled" >&2
        return 1
      }
      printf '%s\n' "$bundled"
      ;;
    *)
      _vdgg_executor_command "$name"
      ;;
  esac
}

_vdgg_executor_command() {
  local ai="$1" file line key command="" seen=0
  _vdgg_name_is_safe "$ai" || {
    echo "vdgg-formation: invalid AI name: $ai" >&2
    return 1
  }
  file=$(_vdgg_executor_file "$ai")
  [ -f "$file" ] || {
    echo "vdgg-formation: executor not found for $ai: $file" >&2
    return 1
  }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
      *=*) ;;
      *) echo "vdgg-formation: invalid line in $file: $line" >&2; return 1 ;;
    esac
    key=${line%%=*}
    [ "$key" = "COMMAND" ] || {
      echo "vdgg-formation: unknown key in $file: $key" >&2
      return 1
    }
    [ "$seen" -eq 0 ] || {
      echo "vdgg-formation: duplicate COMMAND in $file" >&2
      return 1
    }
    command=${line#*=}
    seen=1
  done < "$file"
  [ -n "$command" ] || {
    echo "vdgg-formation: missing COMMAND in $file" >&2
    return 1
  }
  case "$command" in
    /*) ;;
    *) echo "vdgg-formation: COMMAND must be an absolute path: $command" >&2; return 1 ;;
  esac
  [ -f "$command" ] && [ -x "$command" ] || {
    echo "vdgg-formation: COMMAND is not executable: $command" >&2
    return 1
  }
  printf '%s\n' "$command"
}

vdgg_formation_current() {
  local state_file formation=""
  state_file=$(_vdgg_get_state_file 2>/dev/null || true)
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    formation=$(grep '^formation=' "$state_file" | cut -d= -f2- || true)
    printf '%s\n' "$formation"
    return 0
  fi
  printf '%s\n' "${VDGG_FORMATION:-}"
}

vdgg_formation_preflight() {
  local formation="${1:-}" step_key ai
  [ -n "$formation" ] || formation=$(vdgg_formation_current)
  [ -n "$formation" ] || {
    echo "vdgg-formation: no formation selected" >&2
    return 1
  }
  _vdgg_validate_formation_file "$formation" || return 1
  for step_key in $(_vdgg_formation_keys); do
    ai=$(_vdgg_formation_value "$formation" "$step_key")
    [ "$ai" = "inline" ] || _vdgg_seat_command "$ai" "$step_key" >/dev/null || return 1
  done
}

vdgg_formation_resolve() {
  local step_key="${1:-}" formation="${2:-}"
  _vdgg_step_key_is_valid "$step_key" || {
    echo "vdgg-formation: invalid step key: $step_key" >&2
    return 1
  }
  [ -n "$formation" ] || formation=$(vdgg_formation_current)
  vdgg_formation_preflight "$formation" || return 1
  _vdgg_formation_value "$formation" "$step_key"
}

vdgg_grill_validate_output() {
  local output_file="${1:-}" headings expected
  [ -s "$output_file" ] || {
    echo "vdgg-formation: Grill Me output is missing or empty: $output_file" >&2
    return 1
  }
  headings=$(grep '^## ' "$output_file" || true)
  expected=$(printf '%s\n' \
    '## Goal' \
    '## Constraints' \
    '## Acceptance criteria' \
    '## Decisions' \
    '## Unresolved questions')
  [ "$headings" = "$expected" ] || {
    echo "vdgg-formation: Grill Me output must contain only the five required level-2 headings in order" >&2
    return 1
  }
}

vdgg_executor_run() {
  local step_key="${1:-}" input_file="${2:-}" output_file="${3:-}"
  local formation ai command
  _vdgg_step_key_is_valid "$step_key" || {
    echo "vdgg-formation: invalid step key: $step_key" >&2
    return 1
  }
  [ -f "$input_file" ] || {
    echo "vdgg-formation: executor input not found: $input_file" >&2
    return 1
  }
  if [ "$step_key" = "STEP_0_GRILL_AI" ] && [ -z "$output_file" ]; then
    echo "vdgg-formation: Grill Me executor requires an output file" >&2
    return 1
  fi
  if [ -n "$output_file" ] && [ -e "$output_file" ]; then
    echo "vdgg-formation: executor output already exists: $output_file" >&2
    return 1
  fi
  formation=$(vdgg_formation_current)
  ai=$(vdgg_formation_resolve "$step_key" "$formation") || return 1
  [ "$ai" != "inline" ] || {
    echo "vdgg-formation: $step_key is assigned to inline; no external executor was run" >&2
    return 1
  }
  command=$(_vdgg_seat_command "$ai" "$step_key") || return 1
  _vdgg_parse_seat_value "$ai" "$step_key" || return 1
  VDGG_EXECUTOR_FORMATION="$formation" \
  VDGG_EXECUTOR_AI="$_VDGG_SEAT_NAME" \
  VDGG_EXECUTOR_MODEL="$_VDGG_SEAT_MODEL" \
  VDGG_EXECUTOR_EFFORT="$_VDGG_SEAT_EFFORT" \
  VDGG_EXECUTOR_STEP="$step_key" \
  VDGG_EXECUTOR_INPUT="$input_file" \
  VDGG_EXECUTOR_OUTPUT="$output_file" \
    "$command" || return $?
  if [ -n "$output_file" ] && [ ! -s "$output_file" ]; then
    echo "vdgg-formation: executor did not create output: $output_file" >&2
    return 1
  fi
  if [ "$step_key" = "STEP_0_GRILL_AI" ]; then
    vdgg_grill_validate_output "$output_file" || return 1
  fi
}

vdgg_state_init() {
  local id active_file state_file tasks_dir formation="${VDGG_FORMATION:-}"
  if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = "--formation" ] && [ -n "$2" ] || {
      echo "vdgg_state_init: usage: vdgg_state_init [--formation NAME]" >&2
      return 1
    }
    formation=$2
  fi
  [ -z "$formation" ] || vdgg_formation_preflight "$formation" || return 1
  id=$(_vdgg_generate_id)
  active_file=$(_vdgg_active_file)
  state_file=$(_vdgg_state_file_for_id "$id")
  tasks_dir="${VDGG_TASKS_DIR}/${id}"

  if [ -f "$active_file" ]; then
    echo "vdgg-state: active VibesDeGoGo! session already exists" >&2
    return 1
  fi

  mkdir -p "$(dirname "$state_file")" "$tasks_dir"

  # Ensure .gitignore is up to date so our sidecar files are never staged.
  _vdgg_ensure_gitignore

  rm -f "${VDGG_STATE_DIR}/.vdgg-error-pending" 2>/dev/null || true
  _vdgg_rm_glob "${VDGG_STATE_DIR}" '.vdgg-review-sentinel-*'
  echo "$id" > "$active_file"
  cat > "$state_file" <<EOF
step=1
phase=declare
loop_count=0
current_task=
task_allowlist_file=
task_base_ref=
formation=${formation}
vdgg_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  echo "vdgg-state: initialized id=${id}, state=${state_file}, tasks=${tasks_dir}" >&2
}

vdgg_state_read() {
  local state_file
  state_file=$(_vdgg_get_state_file || true)
  if [ -z "${state_file:-}" ] || [ ! -f "$state_file" ]; then
    printf 'step=0\nphase=none\nloop_count=0\ncurrent_task=\nformation=\nvdgg_id=\nlast_updated=\n'
    return 1
  fi
  cat "$state_file"
}

vdgg_state_write() {
  local new_step="$1" new_phase="$2" new_loop_count="$3" new_current_task="${4:-}"
  local new_task_allowlist_file="${5:-}" new_task_base_ref="${6:-}"
  local state_file current_step id formation

  [[ "$new_step" =~ ^[0-9]+$ ]] || { echo "vdgg-state: invalid step" >&2; return 1; }
  case "$new_phase" in
    declare|requirements|investigating|planning|task-selected|implementing|testing|reflection|verified|progress|commit) ;;
    *) echo "vdgg-state: invalid phase" >&2; return 1 ;;
  esac
  [[ "$new_loop_count" =~ ^[0-9]+$ ]] || { echo "vdgg-state: invalid loop" >&2; return 1; }

  state_file=$(_vdgg_get_state_file)
  [ -f "$state_file" ] || { echo "vdgg-state: state file not found" >&2; return 1; }
  current_step=$(grep '^step=' "$state_file" | cut -d= -f2)
  _vdgg_check_step_transition "${current_step:-0}" "$new_step"

  # Omitted optional fields preserve the stored values; a literal `-` clears a
  # task field explicitly (used at the 8->5 boundary).
  if [ -z "$new_current_task" ]; then
    new_current_task=$(grep '^current_task=' "$state_file" | cut -d= -f2- || true)
  fi
  if [ "$new_task_allowlist_file" = "-" ]; then
    new_task_allowlist_file=""
  elif [ -z "$new_task_allowlist_file" ]; then
    new_task_allowlist_file=$(grep '^task_allowlist_file=' "$state_file" | cut -d= -f2- || true)
  fi
  if [ "$new_task_base_ref" = "-" ]; then
    new_task_base_ref=""
  elif [ -z "$new_task_base_ref" ]; then
    new_task_base_ref=$(grep '^task_base_ref=' "$state_file" | cut -d= -f2- || true)
  fi
  formation=$(grep '^formation=' "$state_file" | cut -d= -f2- || true)
  id=$(_vdgg_get_active_id)
  cat > "$state_file" <<EOF
step=${new_step}
phase=${new_phase}
loop_count=${new_loop_count}
current_task=${new_current_task}
task_allowlist_file=${new_task_allowlist_file}
task_base_ref=${new_task_base_ref}
formation=${formation}
vdgg_id=${id}
last_updated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  echo "vdgg-state: -> step=$new_step, phase=$new_phase, loop=$new_loop_count (id=$id)" >&2
}

vdgg_state_advance() {
  local next_step="$1" next_phase="$2" state_file current_step current_loop current_task
  state_file=$(_vdgg_get_state_file)
  [ -f "$state_file" ] || { echo "vdgg_state_advance: state file not found" >&2; return 1; }
  current_step=$(grep '^step=' "$state_file" | cut -d= -f2)
  current_task=$(grep '^current_task=' "$state_file" | cut -d= -f2- || true)
  # When Step 8 continues to Step 5, start the next task with a fresh loop and
  # clear the previous task's allowlist/baseline so vdgg_task_begin is required
  # again before any new-task edits.
  if [ "${current_step:-0}" -eq 8 ] && [ "$next_step" -eq 5 ]; then
    vdgg_state_write "$next_step" "$next_phase" 0 "$current_task" - -
    return
  fi
  current_loop=$(grep '^loop_count=' "$state_file" | cut -d= -f2)
  vdgg_state_write "$next_step" "$next_phase" "${current_loop:-0}" "$current_task"
}

vdgg_state_loop() {
  local loop_step="$1" loop_phase="$2" state_file current_loop current_task
  state_file=$(_vdgg_get_state_file)
  [ -f "$state_file" ] || { echo "vdgg_state_loop: state file not found" >&2; return 1; }
  current_loop=$(grep '^loop_count=' "$state_file" | cut -d= -f2)
  current_task=$(grep '^current_task=' "$state_file" | cut -d= -f2- || true)
  vdgg_state_write "$loop_step" "$loop_phase" "$(( ${current_loop:-0} + 1 ))" "$current_task"
}

vdgg_state_mark_reviewed() {
  local state_file id loop review_file
  state_file=$(_vdgg_get_state_file)
  [ -f "$state_file" ] || { echo "vdgg_state_mark_reviewed: state file not found" >&2; return 1; }
  id=$(_vdgg_get_active_id)
  loop=$(grep '^loop_count=' "$state_file" | cut -d= -f2)
  review_file=$(_vdgg_review_file_for_id "$id" "${loop:-0}")
  cat > "$review_file" <<EOF
started=1
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
modified=0
modified_files=
EOF
  echo "vdgg-state: review gate marked for id=${id}, loop=${loop:-0}" >&2
}

# Run an explicit review pass and mark the review gate only when it succeeds.
# With arguments, runs them as the review command. Without arguments, runs
# REVIEW_COMMAND from .vdgg-target via bash -c. Exit status of a failing
# review is propagated and no sentinel is written.
vdgg_review_run() {
  if [ "$#" -gt 0 ]; then
    "$@" || return $?
  else
    local review_command=""
    if [ -f "${VDGG_CWD}/.vdgg-target" ]; then
      review_command=$(grep '^REVIEW_COMMAND=' "${VDGG_CWD}/.vdgg-target" | head -1 | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' || true)
    fi
    if [ -z "$review_command" ]; then
      echo "vdgg_review_run: no command given and no REVIEW_COMMAND in .vdgg-target" >&2
      return 1
    fi
    bash -c "$review_command" || return $?
  fi
  vdgg_state_mark_reviewed
}

vdgg_task_begin() {
  local task_title="${1:-}" id loop allowlist_file baseline_dir baseline_status gate_file entry normalized
  shift || true

  [ -n "$task_title" ] || { echo "vdgg_task_begin: task title is required" >&2; return 1; }
  [ "$#" -gt 0 ] || { echo "vdgg_task_begin: at least one allowlist path is required" >&2; return 1; }

  id=$(_vdgg_get_active_id)
  [ -n "$id" ] || { echo "vdgg_task_begin: active session not found" >&2; return 1; }

  # Refuse BEFORE any side effect: (re)arming is only legal where a state
  # write to step 5 is (Step 4/5/8 per _vdgg_check_step_transition). Called
  # from implementing/reflection it would otherwise clobber the active loop's
  # allowlist/baseline and then fail the state write anyway, leaving the hook
  # enforcing a stale (or, same-loop, a deleted) allowlist while still
  # printing a success message.
  local current_step state_file
  state_file=$(_vdgg_state_file_for_id "$id")
  if [ -f "$state_file" ]; then
    current_step=$(grep "^step=" "$state_file" | cut -d= -f2)
    if ! _vdgg_check_step_transition "${current_step:-0}" 5 2>/dev/null; then
      echo "vdgg_task_begin: blocked — cannot (re)arm a task outside Step 5 (current step=${current_step})." >&2
      echo "vdgg_task_begin: fit the change to the current allowlist, or take the extra scope as a new task via Step 8 -> Step 5." >&2
      return 1
    fi
  fi

  loop=$(_vdgg_task_loop)
  allowlist_file=$(_vdgg_task_allowlist_file_for_id "$id" "$loop")
  baseline_dir=$(_vdgg_task_baseline_dir_for_id "$id" "$loop")
  baseline_status=$(_vdgg_task_baseline_status_for_id "$id" "$loop")
  gate_file=$(_vdgg_task_gate_file_for_id "$id" "$loop")

  # Validate every path BEFORE any side effect, for the same reason as the step
  # check above: the setup below truncates the allowlist and deletes the
  # baseline, so rejecting the third of four entries would leave the session
  # armed with nothing and stuck at Step 5 (5 -> 8 is not a legal transition).
  for entry in "$@"; do
    _vdgg_path_is_safe_relative "$entry" || {
      echo "vdgg_task_begin: unsafe allowlist path: $entry" >&2
      return 1
    }
  done

  rm -rf "$baseline_dir"
  rm -f "$gate_file"
  mkdir -p "$baseline_dir"
  : > "$allowlist_file"

  for entry in "$@"; do
    normalized=$(_vdgg_normalize_path "$entry")
    printf '%s\n' "$normalized" >> "$allowlist_file"
    if [ -e "$VDGG_CWD/$normalized" ]; then
      mkdir -p "$(dirname "$baseline_dir/$normalized")"
      cp -R "$VDGG_CWD/$normalized" "$baseline_dir/$normalized"
    fi
  done
  sort -u "$allowlist_file" -o "$allowlist_file"
  git -C "$VDGG_CWD" status --porcelain=v1 --untracked-files=all > "$baseline_status"

  # Single state write records the task and both gate fields atomically.
  # The transition was pre-checked above, so a failure here is unexpected —
  # still, never report success on a failed write: roll the side effects back
  # so no half-armed gate survives.
  if ! vdgg_state_write 5 task-selected "$loop" "$task_title" "$allowlist_file" "$baseline_status"; then
    rm -rf "$baseline_dir"
    rm -f "$allowlist_file" "$gate_file" "$baseline_status"
    echo "vdgg_task_begin: state write failed; task gate not armed." >&2
    return 1
  fi
  echo "vdgg-task: began '${task_title}' with allowlist ${allowlist_file}" >&2
}

vdgg_task_changed_files() {
  local id loop baseline_status current_status
  id=$(_vdgg_get_active_id)
  [ -n "$id" ] || { echo "vdgg_task_changed_files: active session not found" >&2; return 1; }
  loop=$(_vdgg_task_loop)
  # Prefer the baseline recorded at vdgg_task_begin so the comparison stays
  # anchored to the task even after vdgg_state_loop increments the loop.
  baseline_status=$(grep '^task_base_ref=' "$(_vdgg_get_state_file)" | cut -d= -f2- || true)
  [ -n "$baseline_status" ] || baseline_status=$(_vdgg_task_baseline_status_for_id "$id" "$loop")
  current_status=$(mktemp)
  git -C "$VDGG_CWD" status --porcelain=v1 --untracked-files=all > "$current_status"
  { [ -f "$baseline_status" ] && cat "$baseline_status"; cat "$current_status"; } \
    | sort | uniq -u | sed -E 's/^...//; s/^"//; s/"$//; s/.* -> //; /^\.codex\/\.vdgg-/d' \
    | grep -v "^tasks/vdgg/${id}/" \
    | sort -u || true
  rm -f "$current_status"
}

vdgg_task_check_allowlist() {
  local id loop allowlist_file changed file
  id=$(_vdgg_get_active_id)
  [ -n "$id" ] || { echo "vdgg_task_check_allowlist: active session not found" >&2; return 1; }
  loop=$(_vdgg_task_loop)
  # Resolve from state so the allowlist survives vdgg_state_loop increments.
  allowlist_file=$(grep '^task_allowlist_file=' "$(_vdgg_get_state_file)" | cut -d= -f2- || true)
  [ -n "$allowlist_file" ] || allowlist_file=$(_vdgg_task_allowlist_file_for_id "$id" "$loop")
  [ -f "$allowlist_file" ] || { echo "vdgg_task_check_allowlist: allowlist not found" >&2; return 1; }
  changed=$(vdgg_task_changed_files)
  [ -n "$changed" ] || return 0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if ! grep -qxF "$file" "$allowlist_file"; then
      echo "vdgg-task: allowlist violation: $file" >&2
      return 1
    fi
  done <<EOF
$changed
EOF
}

vdgg_task_gate() {
  local id loop gate_file
  vdgg_task_check_allowlist || return 1
  if [ "$#" -gt 0 ]; then
    "$@" || return $?
  fi
  id=$(_vdgg_get_active_id)
  loop=$(_vdgg_task_loop)
  gate_file=$(_vdgg_task_gate_file_for_id "$id" "$loop")
  cat > "$gate_file" <<EOF
passed=1
passed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  echo "vdgg-task: gate passed for id=${id}, loop=${loop}" >&2
}

vdgg_task_rollback() {
  local id loop allowlist_file base_ref baseline_dir gate_file changed file
  id=$(_vdgg_get_active_id)
  [ -n "$id" ] || { echo "vdgg_task_rollback: active session not found" >&2; return 1; }
  loop=$(_vdgg_task_loop)
  # Resolve from state so the allowlist survives vdgg_state_loop increments.
  allowlist_file=$(grep '^task_allowlist_file=' "$(_vdgg_get_state_file)" | cut -d= -f2- || true)
  [ -n "$allowlist_file" ] || allowlist_file=$(_vdgg_task_allowlist_file_for_id "$id" "$loop")
  # Derive the baseline dir from the stored base_ref so rollback survives
  # vdgg_state_loop increments; fall back to the current-loop derivation.
  base_ref=$(grep '^task_base_ref=' "$(_vdgg_get_state_file)" | cut -d= -f2- || true)
  if [ -n "$base_ref" ]; then
    baseline_dir="${base_ref/baseline-status-/baseline-}"
  else
    baseline_dir=$(_vdgg_task_baseline_dir_for_id "$id" "$loop")
  fi
  gate_file=$(_vdgg_task_gate_file_for_id "$id" "$loop")
  [ -f "$allowlist_file" ] || { echo "vdgg_task_rollback: allowlist not found" >&2; return 1; }
  [ -d "$baseline_dir" ] || { echo "vdgg_task_rollback: baseline dir not found" >&2; return 1; }

  vdgg_task_check_allowlist || return 1
  rm -f "$gate_file"
  changed=$(vdgg_task_changed_files)
  [ -n "$changed" ] || return 0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ -e "$baseline_dir/$file" ]; then
      rm -rf "$VDGG_CWD/$file"
      mkdir -p "$(dirname "$VDGG_CWD/$file")"
      cp -R "$baseline_dir/$file" "$VDGG_CWD/$file"
    else
      rm -rf "$VDGG_CWD/$file"
    fi
  done <<EOF
$changed
EOF
  echo "vdgg-task: rolled back current task changes" >&2
}

vdgg_state_clear() {
  local id state_file
  id=$(_vdgg_get_active_id)
  [ -n "$id" ] || return 0
  state_file=$(_vdgg_state_file_for_id "$id")
  rm -f "$state_file" "$(_vdgg_active_file)" "${VDGG_STATE_DIR}/.vdgg-error-pending"
  _vdgg_rm_glob "${VDGG_STATE_DIR}" ".vdgg-review-sentinel-${id}-*"
  _vdgg_rm_glob "${VDGG_STATE_DIR}" ".vdgg-task-allowlist-${id}-*"
  _vdgg_rm_glob "${VDGG_STATE_DIR}" ".vdgg-task-baseline-status-${id}-*"
  _vdgg_rm_glob "${VDGG_STATE_DIR}" ".vdgg-task-gate-${id}-*"
  _vdgg_rm_dir_glob "${VDGG_STATE_DIR}" ".vdgg-task-baseline-${id}-*"
  echo "vdgg-state: cleared id=${id}" >&2
}
