#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

STOPHOOK="$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-hook-stop.sh"
TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

write_state() {
    mkdir -p "$TMPDIR_VDGG/.codex"
    echo "test-id" > "$TMPDIR_VDGG/.codex/.vdgg-active"
    cat > "$TMPDIR_VDGG/.codex/.vdgg-state-test-id" <<EOF
step=6
phase=implementing
loop_count=0
current_task=T
vdgg_id=test-id
last_updated=2026-05-25T00:00:00Z
EOF
}

run_hook() {
    local json="$1"
    set +e
    printf '%s' "$json" | bash "$STOPHOOK" >/tmp/vdgg-test-stop.out 2>/tmp/vdgg-test-stop.err
    local status=$?
    set -e
    echo "$status"
}

write_state
STATUS=$(run_hook '{"cwd":"'"$TMPDIR_VDGG"'","last_assistant_message":"[Intentional Stop] waiting for validation"}')
assert_exit_code 0 "$STATUS" "intentional stop text is allowed"

STATUS=$(run_hook '{"cwd":"'"$TMPDIR_VDGG"'","last_assistant_message":"done"}')
assert_exit_code 0 "$STATUS" "active workflow stop returns a continuation decision"
STOP_DECISION=$(cat /tmp/vdgg-test-stop.out)
assert_contains "$STOP_DECISION" '"decision": "block"' "active workflow cannot stop silently"
