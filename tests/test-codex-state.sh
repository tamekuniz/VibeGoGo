#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

cd "$TMPDIR_VDGG" || exit 1
export VDGG_CWD="$TMPDIR_VDGG"
export VDGG_CONFIG_DIR="$TMPDIR_VDGG/user-config"
git init -q
git config user.email "vdgg-test@example.com"
git config user.name "VDGG Test"
mkdir -p functions
printf 'baseline\n' > functions/index.js
git add functions/index.js
git commit -q -m "baseline"

# The Codex state script uses set -euo pipefail; load it but disable errexit
# in the test driver so we can observe non-zero returns ourselves.
source "$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-state.sh"
set +e

vdgg_state_init >/tmp/vdgg-test-codex-init.out 2>/tmp/vdgg-test-codex-init.err
ID=$(vdgg_get_id)
assert_ne "" "$ID" "Codex vdgg_state_init creates an id"
assert_file_exists ".codex/.vdgg-active" "Codex active file exists"
assert_file_exists ".codex/.vdgg-state-${ID}" "Codex state file exists"
FORMATION_DEFAULT=$(grep '^formation=' ".codex/.vdgg-state-${ID}" | cut -d= -f2-)
assert_eq "" "$FORMATION_DEFAULT" "Codex init without formation preserves legacy mode"

RAND="${ID##*-}"
assert_eq "4" "${#RAND}" "Codex id random part is 4 chars (parity with Claude)"

vdgg_state_init >/tmp/vdgg-test-codex-init2.out 2>/tmp/vdgg-test-codex-init2.err
SECOND_INIT_RC=$?
assert_exit_code 1 "$SECOND_INIT_RC" "Codex re-init refuses while a session is active"
ERR_MSG=$(cat /tmp/vdgg-test-codex-init2.err)
assert_contains "$ERR_MSG" "active VibesDeGoGo! session already exists" "Codex re-init prints active-session message"

vdgg_state_advance 2 requirements >/tmp/vdgg-test-codex-2.out 2>/tmp/vdgg-test-codex-2.err
vdgg_state_advance 3 investigating >/tmp/vdgg-test-codex-3.out 2>/tmp/vdgg-test-codex-3.err
vdgg_state_advance 4 planning >/tmp/vdgg-test-codex-4.out 2>/tmp/vdgg-test-codex-4.err
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-codex-5.out 2>/tmp/vdgg-test-codex-5.err
vdgg_task_begin "T1: allowlist probe" functions/index.js functions/new.js >/tmp/vdgg-test-codex-task.out 2>/tmp/vdgg-test-codex-task.err
assert_file_exists ".codex/.vdgg-task-allowlist-${ID}-0" "Codex task allowlist file exists"
ALLOWLIST=$(cat ".codex/.vdgg-task-allowlist-${ID}-0")
assert_contains "$ALLOWLIST" "functions/index.js" "Codex task allowlist includes tracked file"
assert_contains "$ALLOWLIST" "functions/new.js" "Codex task allowlist includes new file"
assert_file_exists ".codex/.vdgg-task-baseline-status-${ID}-0" "Codex task baseline status exists"
assert_file_exists ".codex/.vdgg-task-baseline-${ID}-0/functions/index.js" "Codex task baseline copies existing file"
STATE_CONTENT=$(cat ".codex/.vdgg-state-${ID}")
assert_contains "$STATE_CONTENT" "task_allowlist_file=" "Codex state records task allowlist field"
assert_contains "$STATE_CONTENT" "task_base_ref=" "Codex state records task baseline field"

printf 'changed\n' > functions/index.js
printf 'new\n' > functions/new.js
CHANGED=$(vdgg_task_changed_files)
assert_contains "$CHANGED" "functions/index.js" "Codex task changed files include modified allowlisted file"
assert_contains "$CHANGED" "functions/new.js" "Codex task changed files include new allowlisted file"
vdgg_task_check_allowlist >/tmp/vdgg-test-codex-allow.out 2>/tmp/vdgg-test-codex-allow.err
ALLOW_RC=$?
assert_exit_code 0 "$ALLOW_RC" "Codex task allowlist passes allowed changes"
vdgg_task_gate true >/tmp/vdgg-test-codex-gate.out 2>/tmp/vdgg-test-codex-gate.err
GATE_RC=$?
assert_exit_code 0 "$GATE_RC" "Codex task gate passes after allowlist and command"
assert_file_exists ".codex/.vdgg-task-gate-${ID}-0" "Codex task gate writes success sentinel"
vdgg_task_rollback >/tmp/vdgg-test-codex-rollback.out 2>/tmp/vdgg-test-codex-rollback.err
ROLLBACK_RC=$?
assert_exit_code 0 "$ROLLBACK_RC" "Codex task rollback succeeds for allowed changes"
INDEX_CONTENT=$(cat functions/index.js)
assert_eq "baseline" "$INDEX_CONTENT" "Codex task rollback restores modified file"
assert_file_not_exists "functions/new.js" "Codex task rollback removes newly-created file"
assert_file_not_exists ".codex/.vdgg-task-gate-${ID}-0" "Codex task rollback clears gate sentinel"
printf 'outside\n' > functions/other.js
vdgg_task_check_allowlist >/tmp/vdgg-test-codex-deny.out 2>/tmp/vdgg-test-codex-deny.err
DENY_RC=$?
assert_exit_code 1 "$DENY_RC" "Codex task allowlist rejects disallowed changes"
rm -f functions/other.js
vdgg_state_advance 6 implementing >/tmp/vdgg-test-codex-6.out 2>/tmp/vdgg-test-codex-6.err
vdgg_state_loop 6 implementing >/tmp/vdgg-test-codex-loop.out 2>/tmp/vdgg-test-codex-loop.err
LOOP_COUNT=$(grep '^loop_count=' ".codex/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "1" "$LOOP_COUNT" "Codex vdgg_state_loop increments loop_count"

vdgg_state_advance 7 testing >/tmp/vdgg-test-codex-7.out 2>/tmp/vdgg-test-codex-7.err
vdgg_state_mark_reviewed >/tmp/vdgg-test-codex-review.out 2>/tmp/vdgg-test-codex-review.err
assert_file_exists ".codex/.vdgg-review-sentinel-${ID}-1" "Codex mark_reviewed creates review sentinel"
MODIFIED=$(grep '^modified=' ".codex/.vdgg-review-sentinel-${ID}-1" | cut -d= -f2)
assert_eq "0" "$MODIFIED" "Codex review sentinel starts with modified=0"

vdgg_state_clear >/tmp/vdgg-test-codex-clear.out 2>/tmp/vdgg-test-codex-clear.err
assert_file_not_exists ".codex/.vdgg-active" "Codex clear removes active file"
assert_file_not_exists ".codex/.vdgg-state-${ID}" "Codex clear removes state file"
assert_file_not_exists ".codex/.vdgg-review-sentinel-${ID}-1" "Codex clear removes review sentinels"

# Formation: complete Step-to-AI mappings live outside the repository, are
# validated without sourcing, and persist in state across transitions.
mkdir -p "$VDGG_CONFIG_DIR/formations" "$VDGG_CONFIG_DIR/executors" "$TMPDIR_VDGG/bin"
EXECUTOR="$TMPDIR_VDGG/bin/test-executor"
cat > "$EXECUTOR" <<'EOF'
#!/bin/sh
if [ "$VDGG_EXECUTOR_STEP" = "STEP_0_GRILL_AI" ]; then
  cat > "$VDGG_EXECUTOR_OUTPUT" <<'RESULT'
## Goal
goal
## Constraints
constraints
## Acceptance criteria
acceptance
## Decisions
decisions
## Unresolved questions
none
RESULT
else
  printf 'formation=%s\nai=%s\nstep=%s\ninput=%s\n' \
    "$VDGG_EXECUTOR_FORMATION" "$VDGG_EXECUTOR_AI" \
    "$VDGG_EXECUTOR_STEP" "$VDGG_EXECUTOR_INPUT" > "$VDGG_EXECUTOR_OUTPUT"
fi
EOF
chmod +x "$EXECUTOR"
printf 'COMMAND=%s\n' "$EXECUTOR" > "$VDGG_CONFIG_DIR/executors/qwen.conf"
cat > "$VDGG_CONFIG_DIR/formations/balanced.conf" <<'EOF'
# friendly syntax: unlisted seats stay inline
3: qwen
4: qwen
6: qwen
7: qwen
grill: qwen
EOF

vdgg_formation_preflight balanced >/tmp/vdgg-test-formation-preflight.out 2>/tmp/vdgg-test-formation-preflight.err
PREFLIGHT_RC=$?
assert_exit_code 0 "$PREFLIGHT_RC" "Codex accepts a complete trusted formation"
RESOLVED=$(vdgg_formation_resolve STEP_6_AI balanced)
assert_eq "qwen" "$RESOLVED" "Codex resolves a Step AI from an explicit formation"
RESOLVED_UNLISTED=$(vdgg_formation_resolve STEP_0_AI balanced)
assert_eq "inline" "$RESOLVED_UNLISTED" "Codex defaults an unlisted seat to inline"
RESOLVED_6R=$(vdgg_formation_resolve STEP_6R_AI balanced)
assert_eq "inline" "$RESOLVED_6R" "Codex defaults unlisted 6R to inline"

vdgg_state_init --formation balanced >/tmp/vdgg-test-formation-init.out 2>/tmp/vdgg-test-formation-init.err
IDF=$(vdgg_get_id)
FORMATION_STORED=$(grep '^formation=' ".codex/.vdgg-state-${IDF}" | cut -d= -f2-)
assert_eq "balanced" "$FORMATION_STORED" "Codex stores the selected formation in state"
vdgg_state_advance 2 requirements >/dev/null 2>&1
FORMATION_AFTER_ADVANCE=$(grep '^formation=' ".codex/.vdgg-state-${IDF}" | cut -d= -f2-)
assert_eq "balanced" "$FORMATION_AFTER_ADVANCE" "Codex preserves formation across state writes"

printf 'implement task\n' > "$TMPDIR_VDGG/executor-input.md"
vdgg_executor_run STEP_6_AI "$TMPDIR_VDGG/executor-input.md" "$TMPDIR_VDGG/executor-output.md" \
  >/tmp/vdgg-test-executor-run.out 2>/tmp/vdgg-test-executor-run.err
EXECUTOR_RC=$?
assert_exit_code 0 "$EXECUTOR_RC" "Codex runs a validated executor directly"
EXECUTOR_OUTPUT=$(cat "$TMPDIR_VDGG/executor-output.md")
assert_contains "$EXECUTOR_OUTPUT" "formation=balanced" "Codex passes formation to executor"
assert_contains "$EXECUTOR_OUTPUT" "ai=qwen" "Codex passes AI name to executor"
assert_contains "$EXECUTOR_OUTPUT" "step=STEP_6_AI" "Codex passes Step key to executor"

vdgg_executor_run STEP_0_GRILL_AI "$TMPDIR_VDGG/executor-input.md" "$TMPDIR_VDGG/grill-output.md" \
  >/tmp/vdgg-test-grill-run.out 2>/tmp/vdgg-test-grill-run.err
GRILL_RC=$?
assert_exit_code 0 "$GRILL_RC" "Codex accepts structured Grill Me output"
vdgg_grill_validate_output "$TMPDIR_VDGG/grill-output.md" >/dev/null 2>&1
GRILL_VALIDATE_RC=$?
assert_exit_code 0 "$GRILL_VALIDATE_RC" "Codex validates the five Grill Me handoff headings"
vdgg_state_clear >/dev/null 2>&1

# Wildcard "*" assigns the non-interactive seats; an explicit seat wins.
cat > "$VDGG_CONFIG_DIR/formations/wild.conf" <<'EOF'
*: qwen
6: inline
EOF
RESOLVED_WILD=$(vdgg_formation_resolve STEP_3_AI wild)
assert_eq "qwen" "$RESOLVED_WILD" "Codex expands * to the non-interactive seats"
RESOLVED_WILD6=$(vdgg_formation_resolve STEP_6_AI wild)
assert_eq "inline" "$RESOLVED_WILD6" "Codex lets an explicit seat override *"
RESOLVED_WILD0=$(vdgg_formation_resolve STEP_0_AI wild)
assert_eq "inline" "$RESOLVED_WILD0" "Codex keeps seat 0 out of * expansion"

# Builtin claude/codex values resolve to the bundled wrappers and carry
# model/effort tokens through to the executor environment.
cat > "$VDGG_CONFIG_DIR/formations/mixed.conf" <<'EOF'
6: claude sonnet low
6R: claude high
7: codex xhigh
EOF
vdgg_formation_preflight mixed >/tmp/vdgg-test-formation-mixed.out 2>/tmp/vdgg-test-formation-mixed.err
MIXED_RC=$?
assert_exit_code 0 "$MIXED_RC" "Codex accepts builtin claude/codex with model/effort tokens"

REAL_SCRIPT_DIR="$_VDGG_SCRIPT_DIR"
mkdir -p "$TMPDIR_VDGG/fakebundle"
for fake in vdgg-exec-claude.sh vdgg-exec-codex.sh; do
  cat > "$TMPDIR_VDGG/fakebundle/$fake" <<'EOF'
#!/bin/sh
printf 'ai=%s model=%s effort=%s\n' \
  "$VDGG_EXECUTOR_AI" "$VDGG_EXECUTOR_MODEL" "$VDGG_EXECUTOR_EFFORT" > "$VDGG_EXECUTOR_OUTPUT"
EOF
  chmod +x "$TMPDIR_VDGG/fakebundle/$fake"
done
_VDGG_SCRIPT_DIR="$TMPDIR_VDGG/fakebundle"
vdgg_state_init --formation mixed >/dev/null 2>&1
vdgg_executor_run STEP_6_AI "$TMPDIR_VDGG/executor-input.md" "$TMPDIR_VDGG/mixed-6.md" >/dev/null 2>&1
assert_contains "$(cat "$TMPDIR_VDGG/mixed-6.md")" "ai=claude model=sonnet effort=low" "Codex splits 'claude sonnet low' into model and effort"
vdgg_executor_run STEP_6R_AI "$TMPDIR_VDGG/executor-input.md" "$TMPDIR_VDGG/mixed-6r.md" >/dev/null 2>&1
assert_contains "$(cat "$TMPDIR_VDGG/mixed-6r.md")" "ai=claude model= effort=high" "Codex reads 'claude high' as effort with default model"
vdgg_state_clear >/dev/null 2>&1
_VDGG_SCRIPT_DIR="$REAL_SCRIPT_DIR"

# Invalid formations fail before state is armed.
printf '1: qwen\n' > "$VDGG_CONFIG_DIR/formations/seat1.conf"
vdgg_formation_preflight seat1 >/tmp/vdgg-test-formation-seat1.out 2>/tmp/vdgg-test-formation-seat1.err
SEAT1_RC=$?
assert_exit_code 0 "$SEAT1_RC" "Codex accepts an AI on every seat"
assert_eq "qwen" "$(vdgg_formation_resolve STEP_1_AI seat1)" "Codex resolves an AI on seat 1"

printf '9: sonnet5\n' > "$VDGG_CONFIG_DIR/formations/seat9.conf"
vdgg_formation_preflight seat9 >/tmp/vdgg-test-formation-seat9.out 2>/tmp/vdgg-test-formation-seat9.err
SEAT9_RC=$?
assert_exit_code 0 "$SEAT9_RC" "Codex accepts a model shorthand on seat 9"
assert_eq "sonnet5" "$(vdgg_formation_resolve STEP_9_AI seat9)" "Codex resolves a model shorthand on seat 9"

# Every step can be written; the workflow-owned ones take "primary".
cat > "$VDGG_CONFIG_DIR/formations/allsteps.conf" <<'EOF'
0: primary
0G: qwen
1: primary
2: primary
3: qwen
4: qwen
5: primary
6: qwen
6R: primary
7: qwen
8: primary
9: primary
EOF
vdgg_formation_preflight allsteps >/tmp/vdgg-test-formation-allsteps.out 2>/tmp/vdgg-test-formation-allsteps.err
ALLSTEPS_RC=$?
assert_exit_code 0 "$ALLSTEPS_RC" "Codex accepts primary on every workflow-owned seat"
assert_eq "inline" "$(vdgg_formation_resolve STEP_1_AI allsteps)" "Codex resolves primary to inline"
assert_eq "qwen" "$(vdgg_formation_resolve STEP_3_AI allsteps)" "Codex resolves a delegated seat"
assert_eq "qwen" "$(vdgg_formation_resolve STEP_0_GRILL_AI allsteps)" "Codex accepts 0G as the Grill Me seat"

# Model shorthands expand to the bundled claude wrapper plus a full model id.
printf '6: sonnet5\n' > "$VDGG_CONFIG_DIR/formations/alias.conf"
vdgg_formation_preflight alias >/tmp/vdgg-test-formation-alias.out 2>/tmp/vdgg-test-formation-alias.err
ALIAS_RC=$?
assert_exit_code 0 "$ALIAS_RC" "Codex accepts a model shorthand"
_vdgg_parse_seat_value "sonnet5" "STEP_6_AI"
assert_eq "claude" "$_VDGG_SEAT_NAME" "Codex expands sonnet5 to the claude wrapper"
assert_eq "claude-sonnet-5" "$_VDGG_SEAT_MODEL" "Codex expands sonnet5 to a full model id"

# Everything below a lone "--" is a free-form memo.
printf '3: qwen\n--\nfree text, no comment marker\n9: ignored\n' > "$VDGG_CONFIG_DIR/formations/memo.conf"
vdgg_formation_preflight memo >/tmp/vdgg-test-formation-memo.out 2>/tmp/vdgg-test-formation-memo.err
MEMO_RC=$?
assert_exit_code 0 "$MEMO_RC" "Codex ignores everything below the memo separator"
assert_eq "inline" "$(vdgg_formation_resolve STEP_9_AI memo)" "Codex does not read seats from the memo"

printf '0: codex\n' > "$VDGG_CONFIG_DIR/formations/seat0.conf"
vdgg_formation_preflight seat0 >/tmp/vdgg-test-formation-seat0.out 2>/tmp/vdgg-test-formation-seat0.err
SEAT0_RC=$?
assert_exit_code 0 "$SEAT0_RC" "Codex accepts an AI on the conversational seat 0"
assert_eq "codex" "$(vdgg_formation_resolve STEP_0_AI seat0)" "Codex resolves an AI on seat 0"

printf '6: qwen low\n' > "$VDGG_CONFIG_DIR/formations/baretok.conf"
vdgg_formation_preflight baretok >/tmp/vdgg-test-formation-baretok.out 2>/tmp/vdgg-test-formation-baretok.err
BARETOK_RC=$?
assert_exit_code 1 "$BARETOK_RC" "Codex rejects tokens on a user-defined executor"

printf '6: claude so/nnet\n' > "$VDGG_CONFIG_DIR/formations/badtok.conf"
vdgg_formation_preflight badtok >/tmp/vdgg-test-formation-badtok.out 2>/tmp/vdgg-test-formation-badtok.err
BADTOK_RC=$?
assert_exit_code 1 "$BADTOK_RC" "Codex rejects an unsafe model token"

printf '6: claude --dangerously-skip-permissions\n' > "$VDGG_CONFIG_DIR/formations/flagtok.conf"
vdgg_formation_preflight flagtok >/tmp/vdgg-test-formation-flagtok.out 2>/tmp/vdgg-test-formation-flagtok.err
FLAGTOK_RC=$?
assert_exit_code 1 "$FLAGTOK_RC" "Codex rejects a leading-dash token (flag injection)"

printf '3: qwen\n3: qwen\n' > "$VDGG_CONFIG_DIR/formations/dup.conf"
vdgg_formation_preflight dup >/tmp/vdgg-test-formation-dup.out 2>/tmp/vdgg-test-formation-dup.err
DUP_RC=$?
assert_exit_code 1 "$DUP_RC" "Codex rejects a duplicate seat"

printf 'STEP_3_AI=qwen\n' > "$VDGG_CONFIG_DIR/formations/oldfmt.conf"
vdgg_state_init --formation oldfmt >/tmp/vdgg-test-formation-oldfmt.out 2>/tmp/vdgg-test-formation-oldfmt.err
OLDFMT_RC=$?
assert_exit_code 1 "$OLDFMT_RC" "Codex rejects the old 13-key format"
assert_contains "$(cat /tmp/vdgg-test-formation-oldfmt.err)" "old KEY=VALUE format" "Codex explains the old-format rewrite"
assert_file_not_exists ".codex/.vdgg-active" "Codex does not arm state for an invalid formation"

sed 's/^6: qwen/6: unknown/' "$VDGG_CONFIG_DIR/formations/balanced.conf" > "$VDGG_CONFIG_DIR/formations/unknown.conf"
vdgg_state_init --formation unknown >/tmp/vdgg-test-formation-unknown.out 2>/tmp/vdgg-test-formation-unknown.err
UNKNOWN_RC=$?
assert_exit_code 1 "$UNKNOWN_RC" "Codex rejects an unknown AI"
assert_file_not_exists ".codex/.vdgg-active" "Codex keeps state unarmed for an unknown AI"

printf 'COMMAND=%s\n' "$TMPDIR_VDGG/bin/not-executable" > "$VDGG_CONFIG_DIR/executors/broken.conf"
sed 's/^7: qwen/7: broken/' "$VDGG_CONFIG_DIR/formations/balanced.conf" > "$VDGG_CONFIG_DIR/formations/broken.conf"
vdgg_formation_preflight broken >/tmp/vdgg-test-formation-broken.out 2>/tmp/vdgg-test-formation-broken.err
BROKEN_RC=$?
assert_exit_code 1 "$BROKEN_RC" "Codex rejects a non-executable executor command"

cat > "$TMPDIR_VDGG/bad-grill.md" <<'EOF'
## Goal
goal
## Transcript
must not cross the handoff
EOF
vdgg_grill_validate_output "$TMPDIR_VDGG/bad-grill.md" >/tmp/vdgg-test-grill-bad.out 2>/tmp/vdgg-test-grill-bad.err
BAD_GRILL_RC=$?
assert_exit_code 1 "$BAD_GRILL_RC" "Codex rejects Grill Me transcript leakage headings"

vdgg_state_init --formation '../balanced' >/tmp/vdgg-test-formation-name.out 2>/tmp/vdgg-test-formation-name.err
NAME_RC=$?
assert_exit_code 1 "$NAME_RC" "Codex rejects an unsafe formation name"
assert_file_not_exists ".codex/.vdgg-active" "Codex does not arm state for an unsafe formation name"

FAIL_EXECUTOR="$TMPDIR_VDGG/bin/fail-executor"
printf '#!/bin/sh\nexit 7\n' > "$FAIL_EXECUTOR"
chmod +x "$FAIL_EXECUTOR"
printf 'COMMAND=%s\n' "$FAIL_EXECUTOR" > "$VDGG_CONFIG_DIR/executors/failing.conf"
sed 's/^6: qwen/6: failing/' "$VDGG_CONFIG_DIR/formations/balanced.conf" > "$VDGG_CONFIG_DIR/formations/failing.conf"
vdgg_state_init --formation failing >/dev/null 2>&1
IDFAIL=$(vdgg_get_id)
vdgg_executor_run STEP_6_AI "$TMPDIR_VDGG/executor-input.md" \
  >/tmp/vdgg-test-executor-fail.out 2>/tmp/vdgg-test-executor-fail.err
FAIL_EXECUTOR_RC=$?
assert_exit_code 7 "$FAIL_EXECUTOR_RC" "Codex propagates executor failure without fallback"
assert_file_exists ".codex/.vdgg-state-${IDFAIL}" "Codex preserves state after executor failure"
FAIL_STEP=$(grep '^step=' ".codex/.vdgg-state-${IDFAIL}" | cut -d= -f2)
assert_eq "1" "$FAIL_STEP" "Codex does not advance state after executor failure"
vdgg_state_clear >/dev/null 2>&1

# Parity: 8 -> 5 resets loop_count and clears the previous task's scope.
vdgg_state_init >/tmp/vdgg-test-codex-initb.out 2>/tmp/vdgg-test-codex-initb.err
IDB=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TB: scope probe" functions/index.js >/dev/null 2>&1
vdgg_state_advance 6 implementing >/dev/null 2>&1
vdgg_state_loop 6 implementing >/dev/null 2>&1
vdgg_state_advance 7 testing >/dev/null 2>&1
vdgg_state_advance 8 progress >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
LOOP_COUNT=$(grep '^loop_count=' ".codex/.vdgg-state-${IDB}" | cut -d= -f2)
assert_eq "0" "$LOOP_COUNT" "Codex 8 to 5 resets loop_count"
ALLOW_FIELD=$(grep '^task_allowlist_file=' ".codex/.vdgg-state-${IDB}" | cut -d= -f2-)
assert_eq "" "$ALLOW_FIELD" "Codex 8 to 5 clears task allowlist field"
BASE_FIELD=$(grep '^task_base_ref=' ".codex/.vdgg-state-${IDB}" | cut -d= -f2-)
assert_eq "" "$BASE_FIELD" "Codex 8 to 5 clears task baseline field"

# Task notes are exempt from changed-files (and therefore from the allowlist).
mkdir -p "tasks/vdgg/${IDB}"
printf 'note\n' > "tasks/vdgg/${IDB}/progress.md"
CHANGED=$(vdgg_task_changed_files)
NOTES_HIT=$(printf '%s\n' "$CHANGED" | grep -c '^tasks/vdgg/' || true)
assert_eq "0" "$NOTES_HIT" "Codex changed-files exempts task notes"
rm -rf tasks
vdgg_state_clear >/dev/null 2>&1

# Re-arm guard: vdgg_task_begin is rejected outside Step 5 (e.g. implementing)
# BEFORE any side effect — the active allowlist/baseline must survive intact —
# and re-arming with a wider allowlist works via the legal 8 -> 5 route.
vdgg_state_init >/tmp/vdgg-test-codex-rearm-init.out 2>/tmp/vdgg-test-codex-rearm-init.err
IDRA=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TA: rearm guard" functions/index.js >/dev/null 2>&1
vdgg_state_advance 6 implementing >/dev/null 2>&1
vdgg_task_begin "TA: widened from implementing" functions/index.js functions/new.js \
    >/tmp/vdgg-test-codex-rearm-blocked.out 2>/tmp/vdgg-test-codex-rearm-blocked.err
REARM_RC=$?
assert_exit_code 1 "$REARM_RC" "Codex task_begin from implementing is rejected"
REARM_ALLOWLIST_CONTENT=$(cat ".codex/.vdgg-task-allowlist-${IDRA}-0")
assert_eq "functions/index.js" "$REARM_ALLOWLIST_CONTENT" "Codex blocked re-arm leaves active allowlist intact"
REARM_STEP=$(grep '^step=' ".codex/.vdgg-state-${IDRA}" | cut -d= -f2)
assert_eq "6" "$REARM_STEP" "Codex blocked re-arm leaves state untouched"
vdgg_state_advance 7 testing >/dev/null 2>&1
vdgg_state_advance 8 progress >/dev/null 2>&1
vdgg_task_begin "TA: widened via 8->5" functions/index.js functions/new.js \
    >/tmp/vdgg-test-codex-rearm-ok.out 2>/tmp/vdgg-test-codex-rearm-ok.err
REARM_OK_RC=$?
assert_exit_code 0 "$REARM_OK_RC" "Codex task_begin re-arms via Step 8 -> Step 5"
REARM_WIDE_COUNT=$(wc -l < ".codex/.vdgg-task-allowlist-${IDRA}-0" | tr -d ' ')
assert_eq "2" "$REARM_WIDE_COUNT" "Codex re-arm via 8->5 records the widened allowlist"
vdgg_state_clear >/dev/null 2>&1

# Unsafe path guard: a rejected allowlist entry must be refused BEFORE the setup
# truncates the allowlist and deletes the baseline. Otherwise the session keeps
# an armed task title with no allowlist and cannot advance (5 -> 8 is illegal).
vdgg_state_init >/tmp/vdgg-test-codex-unsafe-init.out 2>/tmp/vdgg-test-codex-unsafe-init.err
IDUP=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TU: armed" functions/index.js >/dev/null 2>&1
# The bad path must be the ONLY argument: with a good path first, the pre-fix
# loop wrote that one before rejecting, so the allowlist matched by accident.
vdgg_task_begin "TU: outside the repo" /etc/hosts \
    >/tmp/vdgg-test-codex-unsafe.out 2>/tmp/vdgg-test-codex-unsafe.err
UNSAFE_RC=$?
assert_exit_code 1 "$UNSAFE_RC" "Codex task_begin rejects an absolute allowlist path"
UNSAFE_ALLOWLIST_CONTENT=$(cat ".codex/.vdgg-task-allowlist-${IDUP}-0")
assert_eq "functions/index.js" "$UNSAFE_ALLOWLIST_CONTENT" "Codex rejected path leaves the allowlist intact"
UNSAFE_STATE_ALLOWLIST=$(grep '^task_allowlist_file=' ".codex/.vdgg-state-${IDUP}" | cut -d= -f2-)
assert_ne "" "$UNSAFE_STATE_ALLOWLIST" "Codex rejected path leaves the session armed"
vdgg_state_clear >/dev/null 2>&1

# zsh regression: `local path` would empty $PATH when sourced into zsh.
if command -v zsh >/dev/null 2>&1; then
    zsh -c "cd '$TMPDIR_VDGG' && export VDGG_CWD='$TMPDIR_VDGG' VDGG_CONFIG_DIR='$VDGG_CONFIG_DIR' && source '$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-state.sh' && vdgg_state_init --formation balanced && vdgg_state_advance 2 requirements && vdgg_state_advance 3 investigating && vdgg_state_advance 4 planning && vdgg_state_advance 5 task-selected && vdgg_task_begin 'TZ: zsh probe' functions/index.js" >/tmp/vdgg-test-codex-zsh.out 2>/tmp/vdgg-test-codex-zsh.err
    ZSH_RC=$?
    assert_exit_code 0 "$ZSH_RC" "Codex formation helpers work when sourced into zsh"
    IDZ=$(cat .codex/.vdgg-active)
    assert_file_exists ".codex/.vdgg-task-allowlist-${IDZ}-0" "zsh vdgg_task_begin creates allowlist"
    ZSH_FORMATION=$(grep '^formation=' ".codex/.vdgg-state-${IDZ}" | cut -d= -f2-)
    assert_eq "balanced" "$ZSH_FORMATION" "zsh state preserves formation"
    vdgg_state_clear >/dev/null 2>&1
fi

# vdgg_review_run: success writes the review sentinel, failure does not.
vdgg_state_init >/tmp/vdgg-test-codex-review-init.out 2>/tmp/vdgg-test-codex-review-init.err
IDR=$(vdgg_get_id)
vdgg_review_run false >/tmp/vdgg-test-codex-review-false.out 2>/tmp/vdgg-test-codex-review-false.err
REVIEW_FAIL_RC=$?
assert_exit_code 1 "$REVIEW_FAIL_RC" "Codex review_run propagates failing review exit code"
assert_file_not_exists ".codex/.vdgg-review-sentinel-${IDR}-0" "Codex failing review writes no sentinel"

vdgg_review_run true >/tmp/vdgg-test-codex-review-true.out 2>/tmp/vdgg-test-codex-review-true.err
REVIEW_PASS_RC=$?
assert_exit_code 0 "$REVIEW_PASS_RC" "Codex review_run succeeds with passing review"
assert_file_exists ".codex/.vdgg-review-sentinel-${IDR}-0" "Codex passing review writes sentinel"

# vdgg_review_run with REVIEW_COMMAND from .vdgg-target.
rm -f ".codex/.vdgg-review-sentinel-${IDR}-0"
printf 'REVIEW_COMMAND="true"\n' > .vdgg-target
vdgg_review_run >/tmp/vdgg-test-codex-review-target.out 2>/tmp/vdgg-test-codex-review-target.err
REVIEW_TARGET_RC=$?
assert_exit_code 0 "$REVIEW_TARGET_RC" "Codex review_run uses REVIEW_COMMAND from .vdgg-target"
assert_file_exists ".codex/.vdgg-review-sentinel-${IDR}-0" "Codex target-config review writes sentinel"
rm -f .vdgg-target

vdgg_state_clear >/dev/null 2>&1

# _vdgg_ensure_gitignore: appends marker once; idempotent on second call.
printf '# existing\n' > .gitignore
vdgg_state_init >/tmp/vdgg-test-codex-gitignore-init.out 2>/tmp/vdgg-test-codex-gitignore-init.err
IDG=$(vdgg_get_id)
MARKER_COUNT=$(grep -c '# Codex / VibesDeGoGo!' .gitignore || true)
assert_eq "1" "$MARKER_COUNT" "Codex ensure_gitignore appends marker exactly once"
PATTERN_COUNT=$(grep -c '\.codex/\.vdgg-\*' .gitignore || true)
assert_eq "1" "$PATTERN_COUNT" "Codex ensure_gitignore appends .codex/.vdgg-* pattern"

# Second init would fail (session active); call the function directly to check idempotency.
_vdgg_ensure_gitignore >/dev/null 2>&1
MARKER_COUNT2=$(grep -c '# Codex / VibesDeGoGo!' .gitignore || true)
assert_eq "1" "$MARKER_COUNT2" "Codex ensure_gitignore is idempotent (marker appears exactly once)"

vdgg_state_clear >/dev/null 2>&1
rm -f .gitignore

# Changed-files scoping: OTHER session task notes ARE visible; ACTIVE session task notes are NOT.
vdgg_state_init >/dev/null 2>&1
IDSCOPE=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TS: scope test" functions/index.js >/dev/null 2>&1
# File under the ACTIVE session id — must be excluded.
mkdir -p "tasks/vdgg/${IDSCOPE}"
printf 'active note\n' > "tasks/vdgg/${IDSCOPE}/progress.md"
# File under a DIFFERENT (simulated) session id — must be included.
OTHER_ID="99991231-2359-ffff"
mkdir -p "tasks/vdgg/${OTHER_ID}"
printf 'other note\n' > "tasks/vdgg/${OTHER_ID}/progress.md"
CHANGED_SCOPE=$(vdgg_task_changed_files)
ACTIVE_HIT=$(printf '%s\n' "$CHANGED_SCOPE" | grep -c "^tasks/vdgg/${IDSCOPE}/" || true)
assert_eq "0" "$ACTIVE_HIT" "Codex changed-files does NOT list ACTIVE session task dir"
OTHER_HIT=$(printf '%s\n' "$CHANGED_SCOPE" | grep -c "^tasks/vdgg/${OTHER_ID}/" || true)
assert_eq "1" "$OTHER_HIT" "Codex changed-files DOES list OTHER session task dir"
rm -rf tasks
vdgg_state_clear >/dev/null 2>&1

# review_run guard: missing REVIEW_COMMAND in .vdgg-target must not kill a strict shell.
printf 'WORKFLOW=branch-pr\n' > .vdgg-target
REVIEW_ERR_FILE=$(mktemp)
bash -c "set -euo pipefail; export VDGG_CWD='${TMPDIR_VDGG}'; source '${ROOT}/.agents/skills/vibesdegogo/scripts/vdgg-state.sh'; vdgg_review_run" \
  >/dev/null 2>"$REVIEW_ERR_FILE"
REVIEW_GUARD_RC=$?
assert_exit_code 1 "$REVIEW_GUARD_RC" "Codex review_run absent REVIEW_COMMAND exits 1 under set -euo pipefail"
REVIEW_GUARD_ERR=$(cat "$REVIEW_ERR_FILE")
assert_contains "$REVIEW_GUARD_ERR" "no command given" "Codex review_run absent REVIEW_COMMAND prints no-command message"
rm -f "$REVIEW_ERR_FILE" .vdgg-target

# allowlist survives vdgg_state_loop increment (loop counter advances but path stays valid).
vdgg_state_init >/tmp/vdgg-test-codex-loop-survival-init.out 2>/tmp/vdgg-test-codex-loop-survival-init.err
IDLS=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TL: loop survival" functions/index.js >/tmp/vdgg-test-codex-loop-survival-begin.out 2>/tmp/vdgg-test-codex-loop-survival-begin.err
vdgg_state_advance 6 implementing >/dev/null 2>&1
vdgg_state_loop 6 implementing >/tmp/vdgg-test-codex-loop-survival-loop.out 2>/tmp/vdgg-test-codex-loop-survival-loop.err
printf 'loop survival change\n' > functions/index.js
vdgg_task_check_allowlist >/tmp/vdgg-test-codex-loop-survival-check.out 2>/tmp/vdgg-test-codex-loop-survival-check.err
LOOP_ALLOW_RC=$?
assert_exit_code 0 "$LOOP_ALLOW_RC" "Codex task allowlist passes after vdgg_state_loop increment"
vdgg_task_gate true >/tmp/vdgg-test-codex-loop-survival-gate.out 2>/tmp/vdgg-test-codex-loop-survival-gate.err
LOOP_GATE_RC=$?
assert_exit_code 0 "$LOOP_GATE_RC" "Codex task gate passes after vdgg_state_loop increment"
git -C . checkout -- functions/index.js
vdgg_state_clear >/dev/null 2>&1

# rollback survives vdgg_state_loop increment (baseline_dir derived from task_base_ref).
vdgg_state_init >/tmp/vdgg-test-codex-rb-survival-init.out 2>/tmp/vdgg-test-codex-rb-survival-init.err
IDRB=$(vdgg_get_id)
vdgg_state_advance 2 requirements >/dev/null 2>&1
vdgg_state_advance 3 investigating >/dev/null 2>&1
vdgg_state_advance 4 planning >/dev/null 2>&1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
vdgg_task_begin "TR: rollback survival" functions/index.js >/tmp/vdgg-test-codex-rb-survival-begin.out 2>/tmp/vdgg-test-codex-rb-survival-begin.err
vdgg_state_advance 6 implementing >/dev/null 2>&1
vdgg_state_loop 6 implementing >/tmp/vdgg-test-codex-rb-survival-loop.out 2>/tmp/vdgg-test-codex-rb-survival-loop.err
printf 'broken\n' > functions/index.js
vdgg_task_rollback >/tmp/vdgg-test-codex-rb-survival-rollback.out 2>/tmp/vdgg-test-codex-rb-survival-rollback.err
RB_SURVIVAL_RC=$?
assert_exit_code 0 "$RB_SURVIVAL_RC" "Codex task rollback succeeds after vdgg_state_loop increment"
RB_SURVIVAL_CONTENT=$(cat functions/index.js)
assert_eq "baseline" "$RB_SURVIVAL_CONTENT" "Codex task rollback restores file after vdgg_state_loop increment"
vdgg_state_clear >/dev/null 2>&1
