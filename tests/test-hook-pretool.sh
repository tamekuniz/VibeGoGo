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

# Sentinel forgery: the internal writer cannot be called directly. That call
# leaves no sidecar path in the command, so the guard below would not see it.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"source skills/vibesdegogo/scripts/vdgg-state.sh && _vdgg_write_review_sentinel"}}')
assert_exit_code 2 "$STATUS" "direct call to the internal sentinel writer is blocked"

# Sentinel forgery: a relative write after cd into the sidecar directory drops
# the .claude/ prefix from the command, so the basename must be matched too.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"cd .claude && printf started=1 > .vdgg-review-sentinel-test-id-0"}}')
assert_exit_code 2 "$STATUS" "relative sentinel write after cd is blocked"

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

# --- [Error Acknowledged] gate: mtime-anchored acknowledgement ----------------
# The flag's mtime is the anchor; timestamps far apart (2020 vs 2030) keep the
# assertions immune to local-timezone offsets in _vdgg_mtime.
ACK_TRANSCRIPT="$TMPDIR_VDGG/transcript.jsonl"
write_state implementing 6
write_ack_flag() {
    printf 'reason=exit 1\n' > "$TMPDIR_VDGG/.claude/.vdgg-error-pending"
    touch -t 202601011200 "$TMPDIR_VDGG/.claude/.vdgg-error-pending"
}

# 1) Acknowledgement AFTER the flag was recorded -> allowed, flag consumed.
write_ack_flag
cat > "$ACK_TRANSCRIPT" <<'JSONL'
{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"content":[{"type":"text","text":"[Error Acknowledged] stale ack from an earlier error"}]}}
{"type":"assistant","timestamp":"2030-01-01T00:00:00.500Z","message":{"content":[{"type":"text","text":"[Error Acknowledged] retrying with fixed flag"}]}}
JSONL
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$ACK_TRANSCRIPT"'","tool_input":{"command":"echo ok"}}')
assert_exit_code 0 "$STATUS" "ack gate: acknowledgement after flag mtime unblocks"
assert_file_not_exists "$TMPDIR_VDGG/.claude/.vdgg-error-pending" "ack gate: flag is consumed on acknowledgement"

# 2) Only an OLD acknowledgement (before the flag) -> still blocked.
write_ack_flag
cat > "$ACK_TRANSCRIPT" <<'JSONL'
{"type":"assistant","timestamp":"2020-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"[Error Acknowledged] this belongs to a previous error"}]}}
JSONL
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$ACK_TRANSCRIPT"'","tool_input":{"command":"echo ok"}}')
assert_exit_code 2 "$STATUS" "ack gate: an acknowledgement older than the flag stays blocked"

# 3) No parseable timestamps at all -> bounded tail fallback still satisfiable.
write_ack_flag
cat > "$ACK_TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"[Error Acknowledged] transcript without timestamps"}]}}
JSONL
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$ACK_TRANSCRIPT"'","tool_input":{"command":"echo ok"}}')
assert_exit_code 0 "$STATUS" "ack gate: timestamp-free transcript falls back to tail window"

# 4) No acknowledgement anywhere -> blocked.
write_ack_flag
cat > "$ACK_TRANSCRIPT" <<'JSONL'
{"type":"assistant","timestamp":"2030-01-01T00:00:00Z","message":{"content":[{"type":"text","text":"working on it"}]}}
JSONL
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$ACK_TRANSCRIPT"'","tool_input":{"command":"echo ok"}}')
assert_exit_code 2 "$STATUS" "ack gate: missing acknowledgement stays blocked"
rm -f "$TMPDIR_VDGG/.claude/.vdgg-error-pending" "$ACK_TRANSCRIPT"
