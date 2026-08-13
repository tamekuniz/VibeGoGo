#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

POSTTOOL="$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-hook-posttool.sh"
TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

write_state() {
    local phase="$1" step="$2"
    mkdir -p "$TMPDIR_VDGG/.codex"
    echo "test-id" > "$TMPDIR_VDGG/.codex/.vdgg-active"
    cat > "$TMPDIR_VDGG/.codex/.vdgg-state-test-id" <<EOF
step=${step}
phase=${phase}
loop_count=0
current_task=T
vdgg_id=test-id
last_updated=2026-05-25T00:00:00Z
EOF
}

run_hook() {
    local json="$1"
    set +e
    printf '%s' "$json" | bash "$POSTTOOL" >/tmp/vdgg-test-posttool.out 2>/tmp/vdgg-test-posttool.err
    local status=$?
    set -e
    echo "$status"
}

write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"make build"},"tool_response":{"exit_code":1,"stderr":"Error: failed"}}')
assert_exit_code 0 "$STATUS" "posttool itself exits cleanly after recording an error"
assert_file_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "failed Bash creates error flag"

rm -f "$TMPDIR_VDGG/.codex/.vdgg-error-pending"
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"grep missing file"},"tool_response":{"exit_code":1,"stderr":""}}')
assert_exit_code 0 "$STATUS" "grep no-match exits cleanly"
assert_file_not_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "grep exit 1 does not create error flag"

# Codex CLI 0.139.0 delivers tool_response as a plain string, not an object.
# The hook must not error out under set -e, and must still detect failure from
# the response text (best-effort, since there is no exit_code in this form).
rm -f "$TMPDIR_VDGG/.codex/.vdgg-error-pending"
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"make build"},"tool_response":"Error: build failed\nsee log"}')
assert_exit_code 0 "$STATUS" "posttool exits cleanly with string tool_response"
assert_file_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "string tool_response with error text creates error flag"

rm -f "$TMPDIR_VDGG/.codex/.vdgg-error-pending"
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"echo done"},"tool_response":"done"}')
assert_exit_code 0 "$STATUS" "clean string tool_response exits cleanly"
assert_file_not_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "clean string tool_response creates no error flag"

# Regression: object shape, exit 0, stdout containing an error word mid-line
# (e.g. `git log` output "a1b2c3 fix: error in parser") must NOT be misdetected.
# stdout is checked with a strict start-of-line pattern, so normal output passes.
rm -f "$TMPDIR_VDGG/.codex/.vdgg-error-pending"
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"git log --oneline"},"tool_response":{"exit_code":0,"stdout":"a1b2c3 fix: error in parser","stderr":""}}')
assert_exit_code 0 "$STATUS" "object exit 0 with error word in stdout exits cleanly"
assert_file_not_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "error word in normal stdout does not create error flag"

# Regression: object shape, exit 0, stderr containing an error word must still
# create the error flag (broad scan path over stderr stays alive).
rm -f "$TMPDIR_VDGG/.codex/.vdgg-error-pending"
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"make build"},"tool_response":{"exit_code":0,"stdout":"","stderr":"Error: boom"}}')
assert_exit_code 0 "$STATUS" "object exit 0 with error word in stderr exits cleanly"
assert_file_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "error word in stderr still creates error flag"

# Some Codex versions/events omit tool_response entirely. The hook must not error
# out under set -e (jq type check falls to else), and must pass through cleanly.
rm -f "$TMPDIR_VDGG/.codex/.vdgg-error-pending"
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"make build"}}')
assert_exit_code 0 "$STATUS" "missing tool_response exits cleanly"
assert_file_not_exists "$TMPDIR_VDGG/.codex/.vdgg-error-pending" "missing tool_response creates no error flag"

# Review sentinel: Edit during testing flips modified=1 on the review sentinel.
write_state testing 7
mkdir -p "$TMPDIR_VDGG/src"
cat > "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
modified=0
modified_files=
EOF
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/src/foo.sh"}}')
assert_exit_code 0 "$STATUS" "posttool exits cleanly while tracking review sentinel"
MODIFIED=$(grep '^modified=' "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0" | cut -d= -f2)
assert_eq "1" "$MODIFIED" "edit during testing flips review sentinel to modified=1"
rm -f "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0"

# Review sentinel: task-notes edits do not flip the sentinel.
write_state testing 7
mkdir -p "$TMPDIR_VDGG/tasks/vdgg/test-id"
cat > "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
modified=0
modified_files=
EOF
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/tasks/vdgg/test-id/progress.md"}}')
assert_exit_code 0 "$STATUS" "posttool exits cleanly for task-notes edit"
MODIFIED=$(grep '^modified=' "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0" | cut -d= -f2)
assert_eq "0" "$MODIFIED" "task-notes edit does not flip review sentinel"
rm -f "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0"
