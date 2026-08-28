#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

PRETOOL="$ROOT/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

write_state() {
    local phase="$1" step="$2" loop="${3:-0}"
    mkdir -p "$TMPDIR_VDGG/.claude" "$TMPDIR_VDGG/tasks/vdgg/test-id"
    echo "test-id" > "$TMPDIR_VDGG/.claude/.vdgg-active"
    cat > "$TMPDIR_VDGG/.claude/.vdgg-state-test-id" <<EOF
step=${step}
phase=${phase}
loop_count=${loop}
current_task=T
vdgg_id=test-id
last_updated=2026-05-25T00:00:00Z
EOF
}

run_hook() {
    local json="$1"
    set +e
    printf '%s' "$json" | bash "$PRETOOL" >/tmp/vdgg-test-pretool.out 2>/tmp/vdgg-test-pretool.err
    local status=$?
    set -e
    echo "$status"
}

write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"swift test"}}')
assert_exit_code 2 "$STATUS" "implementing blocks test commands"

write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "verified transition is blocked without simplify sentinel"

write_state reflection 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0\nvdgg_state_loop 6 implementing"}}')
assert_exit_code 2 "$STATUS" "reflection cannot return without retry investigation"

# reflection -> implementing is allowed when the retry investigation and progress
# are both newer than the state file. This exercises the mtime freshness check
# (_vdgg_mtime), which must return a real epoch on both BSD and GNU.
write_state reflection 6
printf 'retry\n' > "$TMPDIR_VDGG/tasks/vdgg/test-id/investigation-r0.md"
printf 'progress\n' > "$TMPDIR_VDGG/tasks/vdgg/test-id/progress.md"
# Make the state file old so the freshly written retry files are strictly newer
# (portable: `touch -t CCYYMMDDhhmm` behaves the same on macOS and Linux).
touch -t 202601010000 "$TMPDIR_VDGG/.claude/.vdgg-state-test-id"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0\nvdgg_state_loop 6 implementing"}}')
assert_exit_code 0 "$STATUS" "reflection returns to implementing with fresh retry investigation"

# Regression guard for the freshness check: when the retry investigation is OLDER
# than the state file (i.e. not written during this reflection), the return must
# be blocked. A broken _vdgg_mtime returns a non-numeric value, and `[ x -le y ]`
# then errors to false so the block is skipped -> the gate fails OPEN and wrongly
# allows the return. This case is what actually catches the GNU stat portability
# bug (the "fresh" case above passes even with the bug).
write_state reflection 6
printf 'stale\n' > "$TMPDIR_VDGG/tasks/vdgg/test-id/investigation-r0.md"
printf 'stale\n' > "$TMPDIR_VDGG/tasks/vdgg/test-id/progress.md"
touch -t 202601010000 \
    "$TMPDIR_VDGG/tasks/vdgg/test-id/investigation-r0.md" \
    "$TMPDIR_VDGG/tasks/vdgg/test-id/progress.md"
touch "$TMPDIR_VDGG/.claude/.vdgg-state-test-id"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0\nvdgg_state_loop 6 implementing"}}')
assert_exit_code 2 "$STATUS" "reflection with stale retry investigation is blocked (mtime freshness)"

write_state commit 9
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"git push origin main"}}')
assert_exit_code 2 "$STATUS" "branch-pr blocks pushing main"

write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.claude/.vdgg-active"}}')
assert_exit_code 2 "$STATUS" "direct active file edit is blocked"

write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Grep","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"pattern":"x"}}')
assert_exit_code 0 "$STATUS" "read-like tools pass during investigation"

# Review gate: a clean review sentinel (written by vdgg_review_run) satisfies verified.
write_state testing 7
cat > "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
started_at=2026-06-11T00:00:00Z
modified=0
modified_files=
EOF
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 0 "$STATUS" "verified transition is allowed with clean review sentinel"
assert_file_not_exists "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0" "review sentinel is consumed on verified"

# Layer 3 integration: a simplify sentinel rendered by _vdgg_render_sentinel_body
# (matching what the PostToolUse hook writes) must satisfy verified. This
# catches shape regressions in the simplify hook path that a hand-written
# legacy 4-field sentinel would not exercise.
write_state testing 7
rm -f "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0"
(
  # shellcheck source=/dev/null
  . "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"
  _vdgg_render_sentinel_body "2026-06-11T00:00:00Z" 0 "" "" "" none 0 0 \
    > "$TMPDIR_VDGG/.claude/.vdgg-simplify-sentinel-test-id-0"
)
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 0 "$STATUS" "verified transition passes with production-shape simplify sentinel"

# Layer 3 integration: a review sentinel with countersign_required=1 and
# countersign=none must BLOCK verified (Layer 3 policy — clean primary
# skipped countersign).
write_state testing 7
(
  . "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"
  _vdgg_render_sentinel_body "2026-06-11T00:00:00Z" 0 "" "deadbeef" 3 none 1 1 \
    > "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0"
)
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "verified blocked by Layer 3 when clean primary lacks countersign"
rm -f "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0"

# Layer 3 integration: same sentinel with countersign=clean must PASS.
write_state testing 7
(
  . "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"
  _vdgg_render_sentinel_body "2026-06-11T00:00:00Z" 0 "" "deadbeef" 3 clean 1 1 \
    > "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0"
)
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 0 "$STATUS" "verified passes when countersign=clean recorded"

# Review gate: a modified review sentinel blocks verified.
write_state testing 7
cat > "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
started_at=2026-06-11T00:00:00Z
modified=1
modified_files=src/foo.sh
EOF
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "verified transition is blocked when review modified code"
rm -f "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0"

# Sentinel forgery: direct Write to a sentinel path is blocked.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Write","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.claude/.vdgg-simplify-sentinel-test-id-0"}}')
assert_exit_code 2 "$STATUS" "direct sentinel write is blocked"

# Sentinel forgery: Bash heredoc write to a sentinel path is blocked.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"cat > .claude/.vdgg-simplify-sentinel-test-id-0 <<EOF\nmodified=0\nEOF"}}')
assert_exit_code 2 "$STATUS" "bash sentinel forgery is blocked"

# P1-Both-2: a `git commit` segment must not shield a sidecar-mutating segment
# in the same command line.
write_state commit 9
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"git commit -m x && rm -f .claude/.vdgg-active"}}')
assert_exit_code 2 "$STATUS" "git commit does not shield sidecar deletion in same command"

# P1-CC-1: interpreter/tool-based sentinel forgery (not in the old blacklist) is blocked.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"dd of=.claude/.vdgg-simplify-sentinel-test-id-0"}}')
assert_exit_code 2 "$STATUS" "dd sentinel forgery is blocked"

write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"install -m 644 /dev/null .claude/.vdgg-simplify-sentinel-test-id-0"}}')
assert_exit_code 2 "$STATUS" "install sentinel forgery is blocked"

# Regression: a genuine sidecar read stays allowed.
write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"cat .claude/.vdgg-state-test-id"}}')
assert_exit_code 0 "$STATUS" "genuine sidecar read is allowed"

# P1-Both-3: an unknown phase must fail closed for mutating tools.
write_state impl 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/src/whatever.sh"}}')
assert_exit_code 2 "$STATUS" "unknown phase fails closed for edits"

# P0-2: .vdgg-target is write-protected even if the agent allowlists it, so it
# cannot self-author REVIEW_COMMAND to forge the review gate.
write_state implementing 6
printf '.vdgg-target\n' > "$TMPDIR_VDGG/.claude/.vdgg-task-allowlist-test-id-0"
cat > "$TMPDIR_VDGG/.claude/.vdgg-state-test-id" <<EOF
step=6
phase=implementing
loop_count=0
current_task=T
task_allowlist_file=$TMPDIR_VDGG/.claude/.vdgg-task-allowlist-test-id-0
task_base_ref=
vdgg_id=test-id
last_updated=2026-06-11T00:00:00Z
EOF
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.vdgg-target"}}')
assert_exit_code 2 "$STATUS" "editing .vdgg-target is blocked even when allowlisted"
rm -f "$TMPDIR_VDGG/.claude/.vdgg-task-allowlist-test-id-0"

write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"echo REVIEW_COMMAND=true > .vdgg-target"}}')
assert_exit_code 2 "$STATUS" "bash write to .vdgg-target is blocked"

# Regression: reading .vdgg-target stays allowed.
write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"grep -m1 ^REVIEW_COMMAND= .vdgg-target"}}')
assert_exit_code 0 "$STATUS" "reading .vdgg-target is allowed"

# P1-CC-2: NotebookEdit is gated like Edit/Write (no allowlist bypass).
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"NotebookEdit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"notebook_path":"'"$TMPDIR_VDGG"'/src/nb.ipynb"}}')
assert_exit_code 2 "$STATUS" "NotebookEdit without allowlist is blocked in implementing"

# P1-CC-2: an unknown mutating tool with a file_path is also gated (fail-closed).
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"SomeFutureWriteTool","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/src/x.py"}}')
assert_exit_code 2 "$STATUS" "unknown write tool without allowlist is blocked"

# Regression: a known read-only tool still passes.
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Glob","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"pattern":"*.py"}}')
assert_exit_code 0 "$STATUS" "read-only tool passes in implementing"

write_state_with_allowlist() {
    local phase="$1" step="$2" loop="${3:-0}"
    write_state "$phase" "$step" "$loop"
    printf 'src/app.sh\n' > "$TMPDIR_VDGG/.claude/.vdgg-task-allowlist-test-id-${loop}"
    cat > "$TMPDIR_VDGG/.claude/.vdgg-state-test-id" <<EOF
step=${step}
phase=${phase}
loop_count=${loop}
current_task=T
task_allowlist_file=$TMPDIR_VDGG/.claude/.vdgg-task-allowlist-test-id-${loop}
task_base_ref=
vdgg_id=test-id
last_updated=2026-06-11T00:00:00Z
EOF
}

# Task allowlist: implementing edits are blocked without vdgg_task_begin.
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/src/app.sh"}}')
assert_exit_code 2 "$STATUS" "implementing edit without allowlist is blocked"

# Task allowlist: allowlisted path is editable, others are not.
write_state_with_allowlist implementing 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/src/app.sh"}}')
assert_exit_code 0 "$STATUS" "allowlisted edit passes"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/src/other.sh"}}')
assert_exit_code 2 "$STATUS" "non-allowlisted edit is blocked"

# Task allowlist: task notes stay editable without allowlisting.
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/tasks/vdgg/test-id/progress.md"}}')
assert_exit_code 0 "$STATUS" "task notes edit passes without allowlist"

# Task gate: verified is blocked when the allowlist is active but the gate has not passed.
write_state_with_allowlist testing 7
cat > "$TMPDIR_VDGG/.claude/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
started_at=2026-06-11T00:00:00Z
modified=0
modified_files=
EOF
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "verified is blocked without task gate pass"

# Task gate: verified passes once the gate file exists alongside a clean sentinel.
printf 'passed=1\n' > "$TMPDIR_VDGG/.claude/.vdgg-task-gate-test-id-0"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 0 "$STATUS" "verified passes with task gate and clean sentinel"
rm -f "$TMPDIR_VDGG/.claude/.vdgg-task-gate-test-id-0" "$TMPDIR_VDGG/.claude/.vdgg-task-allowlist-test-id-0"

# jq missing: hooks stay out of the way when no VDGG session is active.
FAKEBIN=$(mktemp -d)
for tool in cat grep sed head; do
    ln -s "$(command -v $tool)" "$FAKEBIN/$tool"
done
BASH_BIN="$(command -v bash)"
NO_VDGG_DIR=$(mktemp -d)
set +e
printf '%s' '{"tool_name":"Bash","cwd":"'"$NO_VDGG_DIR"'","tool_input":{"command":"echo hi"}}' \
    | env PATH="$FAKEBIN" "$BASH_BIN" "$PRETOOL" >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "jq missing + inactive session does not block"

# jq missing: an active session still fails closed.
write_state implementing 6
set +e
printf '%s' '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"echo hi"}}' \
    | env PATH="$FAKEBIN" "$BASH_BIN" "$PRETOOL" >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 2 "$STATUS" "jq missing + active session fails closed"

# --- VDGG_REQUIRED entry gate: unarmed sessions in an opted-in repository ---

ENTRY_DIR=$(mktemp -d)
printf 'VDGG_REQUIRED=on\n' > "$ENTRY_DIR/.vdgg-target"

STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/src/app.sh"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed Edit is denied"

STATUS=$(run_hook '{"tool_name":"Write","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/.vdgg-target"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed write to .vdgg-target is denied (no self-disable)"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"git commit -m x"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed git commit is denied"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"echo VDGG_REQUIRED=off > .vdgg-target"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed redirect write is denied"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"sed -i.bak s/on/off/ .vdgg-target"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed sed -i is denied"

STATUS=$(run_hook '{"tool_name":"SomeFutureWriteTool","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/src/x.py"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed unknown write tool is denied (fail-closed)"

STATUS=$(run_hook '{"tool_name":"Read","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/src/app.sh"}}')
assert_exit_code 0 "$STATUS" "entry gate: unarmed Read passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"git status && grep -m1 ^VDGG_REQUIRED= .vdgg-target"}}')
assert_exit_code 0 "$STATUS" "entry gate: unarmed read-only bash passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"grep -r pattern src 2>/dev/null"}}')
assert_exit_code 0 "$STATUS" "entry gate: harmless stderr redirect to /dev/null passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"xcodebuild build > /dev/null 2>&1"}}')
assert_exit_code 0 "$STATUS" "entry gate: build with output discarded to /dev/null passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"grep pattern src/app.sh 2>/dev/null > out.txt"}}')
assert_exit_code 2 "$STATUS" "entry gate: real file redirect is still denied alongside /dev/null"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"VDGG_SKILL_DIR=$HOME/.claude/skills/vibesdegogo\nsource \"$VDGG_SKILL_DIR/scripts/vdgg-state.sh\"\nvdgg_state_init"}}')
assert_exit_code 0 "$STATUS" "entry gate: the arming command itself passes"

# Armed session in the same repository: entry gate steps aside, phase guards rule.
mkdir -p "$ENTRY_DIR/.claude" "$ENTRY_DIR/tasks/vdgg/entry-id"
printf 'entry-id\n' > "$ENTRY_DIR/.claude/.vdgg-active"
cat > "$ENTRY_DIR/.claude/.vdgg-state-entry-id" <<EOF
step=3
phase=investigating
loop_count=0
current_task=T
vdgg_id=entry-id
last_updated=2026-07-05T00:00:00Z
EOF
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/tasks/vdgg/entry-id/investigation.md"}}')
assert_exit_code 0 "$STATUS" "entry gate: armed session follows normal phase rules (task notes pass)"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/src/app.sh"}}')
assert_exit_code 2 "$STATUS" "entry gate: armed session still phase-blocks implementation edits"
rm -f "$ENTRY_DIR/.claude/.vdgg-active" "$ENTRY_DIR/.claude/.vdgg-state-entry-id"

# Off / absent key: historical fail-open behavior is unchanged.
printf 'VDGG_REQUIRED=off\n' > "$ENTRY_DIR/.vdgg-target"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/src/app.sh"}}')
assert_exit_code 0 "$STATUS" "entry gate: VDGG_REQUIRED=off keeps fail-open"

rm -f "$ENTRY_DIR/.vdgg-target"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/src/app.sh"}}')
assert_exit_code 0 "$STATUS" "entry gate: absent .vdgg-target keeps fail-open"

# jq missing + VDGG_REQUIRED=on + unarmed: fail closed (tools cannot be classified).
printf 'VDGG_REQUIRED=on\n' > "$ENTRY_DIR/.vdgg-target"
set +e
printf '%s' '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"echo hi"}}' \
    | env PATH="$FAKEBIN" "$BASH_BIN" "$PRETOOL" >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 2 "$STATUS" "entry gate: jq missing + required + unarmed fails closed"

rm -rf "$ENTRY_DIR"
rm -rf "$FAKEBIN" "$NO_VDGG_DIR"

# --- [Error Acknowledged] gate: marker in the next Bash command ---------------
write_state implementing 6
write_ack_flag() {
    printf 'reason=exit 1\n' > "$TMPDIR_VDGG/.claude/.vdgg-error-pending"
}

# 1) Next Bash command without the marker -> blocked.
write_ack_flag
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"echo ok"}}')
assert_exit_code 2 "$STATUS" "ack gate: Bash without the marker stays blocked"

# 2) Next Bash command carrying the marker -> allowed, flag consumed.
write_ack_flag
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [Error Acknowledged] retrying with fixed flag\necho ok"}}')
assert_exit_code 0 "$STATUS" "ack gate: marker in the command unblocks"
assert_file_not_exists "$TMPDIR_VDGG/.claude/.vdgg-error-pending" "ack gate: flag is consumed on acknowledgement"

# --- Step 2 -> 3 gate: '## Lessons Applied' heading with a non-empty body ----
# The hook enforces the section at the earliest structural point where user-memory
# / AIB lessons still shape the requirements. Missing heading or empty body must
# block Step 3; a heading with any non-empty body passes.
LESSONS_REQ="$TMPDIR_VDGG/tasks/vdgg/test-id/requirements.md"
ADVANCE_CMD='# [VibesDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0\nvdgg_state_advance 3 investigating'

# The 3-section prefix is identical across the 4 cases below; hoisting it into a
# single variable keeps each case focused on the '## Lessons Applied' shape it
# actually exercises.
REQ_COMMON=$'## Goal\ngoal\n\n## Constraints\nnone\n\n## Acceptance criteria\nnone\n'

# Case 1: requirements.md without a '## Lessons Applied' heading -> blocked.
write_state requirements 2
printf '%s' "$REQ_COMMON" > "$LESSONS_REQ"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"'"$ADVANCE_CMD"'"}}')
assert_exit_code 2 "$STATUS" "Step 3 gate: missing '## Lessons Applied' heading is blocked"

# Case 2: '## Lessons Applied' with a non-empty body -> allowed.
write_state requirements 2
{ printf '%s' "$REQ_COMMON"; printf '\n## Lessons Applied\nNone applicable\n'; } > "$LESSONS_REQ"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"'"$ADVANCE_CMD"'"}}')
assert_exit_code 0 "$STATUS" "Step 3 gate: '## Lessons Applied' with non-empty body passes"

# Case 3: '## Lessons Applied' with an empty body (only blank lines before EOF
# or before the next heading) -> blocked. Prevents the "heading-only" escape
# hatch where the writer taps the header but skips the actual review.
write_state requirements 2
{ printf '%s' "$REQ_COMMON"; printf '\n## Lessons Applied\n\n\n'; } > "$LESSONS_REQ"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"'"$ADVANCE_CMD"'"}}')
assert_exit_code 2 "$STATUS" "Step 3 gate: '## Lessons Applied' with an empty body is blocked"

# Case 4: heading present but body is empty because a later '## ' heading
# follows immediately (e.g. '## Notes' after a blank line) -> blocked. Catches
# the misordering where Lessons Applied is written last but with no body before
# a trailing section like '## Notes'.
write_state requirements 2
{ printf '%s' "$REQ_COMMON"; printf '\n## Lessons Applied\n\n## Notes\nfree-form\n'; } > "$LESSONS_REQ"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"'"$ADVANCE_CMD"'"}}')
assert_exit_code 2 "$STATUS" "Step 3 gate: '## Lessons Applied' followed by another heading with no body between is blocked"

rm -f "$LESSONS_REQ"
