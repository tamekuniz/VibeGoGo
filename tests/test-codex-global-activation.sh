#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

PRETOOL="$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
USERPROMPT="$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-hook-userprompt.sh"
TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

mkdir -p "$TMPDIR_VDGG/repo/subdir"
git -C "$TMPDIR_VDGG/repo" init -q

(
  cd "$TMPDIR_VDGG/repo/subdir" || exit 1
  unset VDGG_CWD VDGG_STATE_DIR VDGG_TASKS_DIR
  source "$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-state.sh"
  vdgg_state_init >/tmp/vdgg-test-root-init.out 2>/tmp/vdgg-test-root-init.err
)

ID=$(cat "$TMPDIR_VDGG/repo/.codex/.vdgg-active")
assert_ne "" "$ID" "state init from subdir creates an active id"
assert_file_exists "$TMPDIR_VDGG/repo/.codex/.vdgg-state-${ID}" "state file lives at git root"
assert_file_not_exists "$TMPDIR_VDGG/repo/subdir/.codex/.vdgg-active" "subdir does not get a separate active file"

cat > "$TMPDIR_VDGG/repo/.codex/.vdgg-state-${ID}" <<EOF
step=6
phase=implementing
loop_count=0
current_task=T
vdgg_id=${ID}
last_updated=2026-06-07T00:00:00Z
EOF

set +e
printf '%s' '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG/repo/subdir"'","tool_input":{"command":"npm test"}}' \
  | bash "$PRETOOL" >/tmp/vdgg-test-root-pre.out 2>/tmp/vdgg-test-root-pre.err
PRE_STATUS=$?
set -e
assert_exit_code 2 "$PRE_STATUS" "pretool finds root state from subdir"

set +e
printf '%s' '{"cwd":"'"$TMPDIR_VDGG/repo/subdir"'","prompt":"fix the bug"}' \
  | bash "$USERPROMPT" >/tmp/vdgg-test-userprompt.out 2>/tmp/vdgg-test-userprompt.err
PROMPT_STATUS=$?
set -e
assert_exit_code 0 "$PROMPT_STATUS" "user prompt hook exits cleanly"
PROMPT_OUTPUT=$(cat /tmp/vdgg-test-userprompt.out)
assert_contains "$PROMPT_OUTPUT" "VibesDeGoGo! for Codex is installed globally" "user prompt hook injects global VDGG context"
