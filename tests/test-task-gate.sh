#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

cd "$TMPDIR_VDGG" || exit 1
git init -q .
git config user.email "vdgg-test@example.com"
git config user.name "vdgg-test"
mkdir -p src
echo "v1" > src/app.sh
git add -A
git commit -qm "init"

VDGG_CWD="$TMPDIR_VDGG"
source "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"

vdgg_state_init >/tmp/vdgg-test-task-init.out 2>/tmp/vdgg-test-task-init.err
ID=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1

vdgg_task_begin "T1: demo" src/app.sh >/dev/null 2>&1
assert_file_exists ".claude/.vdgg-task-allowlist-${ID}-0" "task_begin creates allowlist"
STATE_ALLOWLIST=$(grep '^task_allowlist_file=' ".claude/.vdgg-state-${ID}" | cut -d= -f2-)
assert_ne "" "$STATE_ALLOWLIST" "task_begin records allowlist in state"

# Allowlisted change passes the check.
echo "v2" > src/app.sh
set +e
vdgg_task_check_allowlist >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "allowlisted change passes check"

# Out-of-allowlist change fails the check.
echo "x" > src/other.sh
set +e
vdgg_task_check_allowlist >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "out-of-allowlist change fails check"
rm -f src/other.sh

# Gate passes with a clean allowlist and a succeeding command.
set +e
vdgg_task_gate true >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "task gate passes"
assert_file_exists ".claude/.vdgg-task-gate-${ID}-0" "gate file recorded"

# Gate fails when the verification command fails.
set +e
vdgg_task_gate false >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "task gate propagates command failure"

# Rollback restores the baseline content and removes the gate file.
echo "v3" > src/app.sh
vdgg_task_rollback >/dev/null 2>&1
assert_eq "v1" "$(cat src/app.sh)" "rollback restores baseline content"
assert_file_not_exists ".claude/.vdgg-task-gate-${ID}-0" "rollback removes gate file"

# Task notes changes are ignored by changed-files (no allowlist violation).
mkdir -p "tasks/vdgg/${ID}"
echo "note" > "tasks/vdgg/${ID}/progress.md"
set +e
vdgg_task_check_allowlist >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "task notes are exempt from the allowlist"

vdgg_state_clear >/dev/null 2>&1
assert_file_not_exists ".claude/.vdgg-task-allowlist-${ID}-0" "clear removes task allowlist"

# rollback survives vdgg_state_loop increment (baseline_dir derived from task_base_ref).
vdgg_state_init >/tmp/vdgg-test-task-rb-init.out 2>/tmp/vdgg-test-task-rb-init.err
IDRB=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TR: rollback survival" src/app.sh >/tmp/vdgg-test-task-rb-begin.out 2>/tmp/vdgg-test-task-rb-begin.err
vdgg_state_advance 6 implementing >/dev/null 2>&1
vdgg_state_loop 6 implementing >/tmp/vdgg-test-task-rb-loop.out 2>/tmp/vdgg-test-task-rb-loop.err
printf 'broken\n' > src/app.sh
set +e
vdgg_task_rollback >/tmp/vdgg-test-task-rb-rollback.out 2>/tmp/vdgg-test-task-rb-rollback.err
RB_SURVIVAL_RC=$?
set -e
assert_exit_code 0 "$RB_SURVIVAL_RC" "task rollback succeeds after vdgg_state_loop increment"
RB_SURVIVAL_CONTENT=$(cat src/app.sh)
assert_eq "v1" "$RB_SURVIVAL_CONTENT" "task rollback restores file after vdgg_state_loop increment"

# changed-files scoping: OTHER session task notes ARE visible; ACTIVE session task notes are NOT.
OTHER_ID="99991231-2359-ffff"
mkdir -p "tasks/vdgg/${OTHER_ID}"
printf 'other note\n' > "tasks/vdgg/${OTHER_ID}/note.md"
mkdir -p "tasks/vdgg/${IDRB}"
printf 'active note\n' > "tasks/vdgg/${IDRB}/x.md"
CHANGED_SCOPE=$(vdgg_task_changed_files)
ACTIVE_HIT=$(printf '%s\n' "$CHANGED_SCOPE" | grep -c "^tasks/vdgg/${IDRB}/" || true)
assert_eq "0" "$ACTIVE_HIT" "changed-files does NOT list ACTIVE session task dir"
OTHER_HIT=$(printf '%s\n' "$CHANGED_SCOPE" | grep -c "^tasks/vdgg/${OTHER_ID}/" || true)
assert_eq "1" "$OTHER_HIT" "changed-files DOES list OTHER session task dir"
rm -rf tasks

vdgg_state_clear >/dev/null 2>&1

# Re-arm guard: vdgg_task_begin is rejected outside Step 5 (e.g. implementing)
# BEFORE any side effect — the active allowlist/baseline must survive intact —
# and re-arming with a wider allowlist works via the legal 8 -> 5 route.
vdgg_state_init >/tmp/vdgg-test-task-rearm-init.out 2>/tmp/vdgg-test-task-rearm-init.err
IDRA=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TA: rearm guard" src/app.sh >/dev/null 2>&1
vdgg_state_advance 6 implementing >/dev/null 2>&1
set +e
vdgg_task_begin "TA: widened from implementing" src/app.sh src/other.sh \
    >/tmp/vdgg-test-task-rearm-blocked.out 2>/tmp/vdgg-test-task-rearm-blocked.err
REARM_RC=$?
set -e
assert_exit_code 1 "$REARM_RC" "task_begin from implementing is rejected"
REARM_ALLOWLIST_CONTENT=$(cat ".claude/.vdgg-task-allowlist-${IDRA}-0")
assert_eq "src/app.sh" "$REARM_ALLOWLIST_CONTENT" "blocked re-arm leaves active allowlist intact"
REARM_STEP=$(grep '^step=' ".claude/.vdgg-state-${IDRA}" | cut -d= -f2)
assert_eq "6" "$REARM_STEP" "blocked re-arm leaves state untouched"
vdgg_state_advance 7 testing >/dev/null 2>&1
vdgg_state_advance 8 progress >/dev/null 2>&1
set +e
vdgg_task_begin "TA: widened via 8->5" src/app.sh src/other.sh \
    >/tmp/vdgg-test-task-rearm-ok.out 2>/tmp/vdgg-test-task-rearm-ok.err
REARM_OK_RC=$?
set -e
assert_exit_code 0 "$REARM_OK_RC" "task_begin re-arms via Step 8 -> Step 5"
REARM_WIDE_COUNT=$(wc -l < ".claude/.vdgg-task-allowlist-${IDRA}-0" | tr -d ' ')
assert_eq "2" "$REARM_WIDE_COUNT" "re-arm via 8->5 records the widened allowlist"
vdgg_state_clear >/dev/null 2>&1

# Unsafe path guard: a rejected allowlist entry must be refused BEFORE the setup
# truncates the allowlist and deletes the baseline. Otherwise the session keeps
# an armed task title with no allowlist and cannot advance (5 -> 8 is illegal).
vdgg_state_init >/tmp/vdgg-test-task-unsafe-init.out 2>/tmp/vdgg-test-task-unsafe-init.err
IDUP=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TU: armed" src/app.sh >/dev/null 2>&1
set +e
# The bad path must be the ONLY argument: with a good path first, the pre-fix
# loop wrote that one before rejecting, so the allowlist matched by accident.
vdgg_task_begin "TU: outside the repo" /etc/hosts \
    >/tmp/vdgg-test-task-unsafe.out 2>/tmp/vdgg-test-task-unsafe.err
UNSAFE_RC=$?
set -e
assert_exit_code 1 "$UNSAFE_RC" "task_begin rejects an absolute allowlist path"
UNSAFE_ALLOWLIST_CONTENT=$(cat ".claude/.vdgg-task-allowlist-${IDUP}-0")
assert_eq "src/app.sh" "$UNSAFE_ALLOWLIST_CONTENT" "rejected path leaves the allowlist intact"
UNSAFE_STATE_ALLOWLIST=$(grep '^task_allowlist_file=' ".claude/.vdgg-state-${IDUP}" | cut -d= -f2-)
assert_ne "" "$UNSAFE_STATE_ALLOWLIST" "rejected path leaves the session armed"
vdgg_state_clear >/dev/null 2>&1

# zsh regression: `local path` would empty $PATH when sourced into zsh.
if command -v zsh >/dev/null 2>&1; then
    vdgg_state_clear >/dev/null 2>&1
    zsh -c "cd '${TMPDIR_VDGG}' && export VDGG_CWD='${TMPDIR_VDGG}' && source '${ROOT}/skills/vibesdegogo/scripts/vdgg-state.sh' && vdgg_state_init && vdgg_state_advance 2 requirements && vdgg_state_advance 3 investigating && vdgg_state_advance 4 planning && vdgg_state_advance 5 task-selected && vdgg_task_begin 'TZ: zsh probe' src/app.sh" >/tmp/vdgg-test-task-zsh.out 2>/tmp/vdgg-test-task-zsh.err
    ZSH_RC=$?
    assert_exit_code 0 "$ZSH_RC" "helpers work when sourced into zsh"
    IDZ=$(cat "${TMPDIR_VDGG}/.claude/.vdgg-active")
    assert_file_exists ".claude/.vdgg-task-allowlist-${IDZ}-0" "zsh vdgg_task_begin creates allowlist"
    vdgg_state_clear >/dev/null 2>&1
fi
