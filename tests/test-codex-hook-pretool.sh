#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

PRETOOL="$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

write_state() {
    local phase="$1" step="$2" loop="${3:-0}" allowlist_file="${4:-}"
    mkdir -p "$TMPDIR_VDGG/.codex" "$TMPDIR_VDGG/tasks/vdgg/test-id"
    echo "test-id" > "$TMPDIR_VDGG/.codex/.vdgg-active"
    cat > "$TMPDIR_VDGG/.codex/.vdgg-state-test-id" <<EOF
step=${step}
phase=${phase}
loop_count=${loop}
current_task=T
task_allowlist_file=${allowlist_file}
task_base_ref=
vdgg_id=test-id
last_updated=2026-05-25T00:00:00Z
EOF
}

write_state_with_allowlist() {
    local phase="$1" step="$2" loop="${3:-0}"
    local allowlist="$TMPDIR_VDGG/.codex/.vdgg-task-allowlist-test-id-${loop}"
    mkdir -p "$TMPDIR_VDGG/.codex"
    printf 'functions/index.js\n' > "$allowlist"
    write_state "$phase" "$step" "$loop" "$allowlist"
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

write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/functions/index.js"}}')
assert_exit_code 2 "$STATUS" "implementing blocks edits before task allowlist"

write_state_with_allowlist implementing 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/functions/index.js"}}')
assert_exit_code 0 "$STATUS" "implementing allows edits inside task allowlist"

write_state_with_allowlist implementing 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/functions/other.js"}}')
assert_exit_code 2 "$STATUS" "implementing blocks edits outside task allowlist"

write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "verified transition is blocked without review sentinel"

write_state_with_allowlist testing 7
mkdir -p "$TMPDIR_VDGG/.codex"
cat > "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
modified=0
modified_files=
EOF
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "verified transition is blocked without task gate"

write_state_with_allowlist testing 7
cat > "$TMPDIR_VDGG/.codex/.vdgg-review-sentinel-test-id-0" <<EOF
started=1
modified=0
modified_files=
EOF
cat > "$TMPDIR_VDGG/.codex/.vdgg-task-gate-test-id-0" <<EOF
passed=1
EOF
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 0 "$STATUS" "verified transition passes after task gate and review sentinel"

# P1-CX-2: reflection -> implementing requires a fresh retry investigation.
# Without investigation-r{loop}.md the return is blocked.
write_state reflection 6
rm -f "$TMPDIR_VDGG/tasks/vdgg/test-id/investigation-r0.md" "$TMPDIR_VDGG/tasks/vdgg/test-id/progress.md"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0\nvdgg_state_loop 6 implementing"}}')
assert_exit_code 2 "$STATUS" "reflection retry is blocked without a retry investigation"

# With investigation-r{loop}.md and progress.md both newer than the state file,
# the return to implementing is allowed.
write_state reflection 6
printf 'retry notes\n' > "$TMPDIR_VDGG/tasks/vdgg/test-id/investigation-r0.md"
printf 'progress\n' > "$TMPDIR_VDGG/tasks/vdgg/test-id/progress.md"
# Make the state file old so the retry files written above are strictly newer
# (mtime is seconds precision; this avoids a same-second tie without the
# non-portable `stat -f` / `date -r` epoch math, which differs on GNU vs BSD).
# `touch -t CCYYMMDDhhmm` is POSIX and behaves the same on macOS and Linux.
touch -t 202601010000 "$TMPDIR_VDGG/.codex/.vdgg-state-test-id"
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0\nvdgg_state_loop 6 implementing"}}')
assert_exit_code 0 "$STATUS" "reflection retry passes with fresh investigation-r and progress"

write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.codex/.vdgg-active"}}')
assert_exit_code 2 "$STATUS" "direct active file edit is blocked"

write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Grep","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"pattern":"x"}}')
assert_exit_code 0 "$STATUS" "read-like tools pass during investigation"

# Sentinel forgery: direct Write to a sentinel path is blocked.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Write","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.codex/.vdgg-review-sentinel-test-id-0"}}')
assert_exit_code 2 "$STATUS" "direct sentinel write is blocked"

# Sentinel forgery: Bash heredoc write to a sentinel path is blocked.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"cat > .codex/.vdgg-review-sentinel-test-id-0 <<EOF\nmodified=0\nEOF"}}')
assert_exit_code 2 "$STATUS" "bash sentinel forgery is blocked"

# P1-Both-2: a git commit segment must not shield a sidecar-mutating segment.
write_state commit 9
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"git commit -m x && rm -f .codex/.vdgg-active"}}')
assert_exit_code 2 "$STATUS" "git commit does not shield sidecar deletion"

# P1-CC-1: interpreter/tool-based sentinel forgery is blocked.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"dd of=.codex/.vdgg-review-sentinel-test-id-0"}}')
assert_exit_code 2 "$STATUS" "dd sentinel forgery is blocked"

# P0-2: .vdgg-target is write-protected (agent cannot self-author REVIEW_COMMAND).
write_state implementing 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"echo REVIEW_COMMAND=true > .vdgg-target"}}')
assert_exit_code 2 "$STATUS" "bash write to .vdgg-target is blocked"

# Regression: a genuine sidecar read stays allowed.
write_state investigating 3
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"cat .codex/.vdgg-state-test-id"}}')
assert_exit_code 0 "$STATUS" "genuine sidecar read is allowed"

# P1-CX-1: verified phase blocks code edits (arm was missing entirely).
write_state verified 7
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/functions/index.js"}}')
assert_exit_code 2 "$STATUS" "verified blocks code edits"

# P1-Both-3: an unknown phase fails closed for mutating tools.
write_state bogusphase 6
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/functions/index.js"}}')
assert_exit_code 2 "$STATUS" "unknown phase fails closed for edits"

# P1-CX-3: testing must go through reflection before returning to implementing.
write_state testing 7
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0\nvdgg_state_loop 6 implementing"}}')
assert_exit_code 2 "$STATUS" "testing cannot return to implementing directly"

# P1-CX-2 (partial): reflection cannot jump straight to verified.
write_state reflection 6
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0\nvdgg_state_advance 7 verified"}}')
assert_exit_code 2 "$STATUS" "reflection cannot jump to verified"

# P1-CX-4: branch-pr forbids pushing the base branch during commit.
write_state commit 9
STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"git push origin main"}}')
assert_exit_code 2 "$STATUS" "branch-pr blocks pushing base branch"

# jq missing: build a fakebin that exposes only the tools the fallback path uses.
# The fallback needs: cat grep sed head git.
FAKEBIN=$(mktemp -d)
BASH_BIN="$(command -v bash)"
for _tool in cat grep sed head git; do
  ln -s "$(command -v "$_tool")" "$FAKEBIN/$_tool"
done

# Case A: directory with no .codex/.vdgg-active and not a git repo -> exit 0.
NO_VDGG_DIR=$(mktemp -d)
set +e
printf '%s' '{"tool_name":"Bash","cwd":"'"$NO_VDGG_DIR"'","tool_input":{"command":"echo hi"}}' \
  | env PATH="$FAKEBIN" "$BASH_BIN" "$PRETOOL" >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "jq missing + inactive session (no .codex/.vdgg-active) does not block"

# Case B: $TMPDIR_VDGG has .codex/.vdgg-active (write_state implementing 6 above
# left it in place). Not a git repo, so git toplevel resolution leaves cwd as-is,
# meaning the active file is found at $TMPDIR_VDGG/.codex/.vdgg-active -> exit 2.
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

STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/functions/index.js"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed Edit is denied"

STATUS=$(run_hook '{"tool_name":"apply_patch","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"*** Add File: functions/index.js"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed apply_patch tool is denied"

STATUS=$(run_hook '{"tool_name":"Write","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/.vdgg-target"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed write to .vdgg-target is denied (no self-disable)"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"git commit -m x"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed git commit is denied"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"echo VDGG_REQUIRED=off > .vdgg-target"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed redirect write is denied"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"sed -i.bak s/on/off/ .vdgg-target"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed sed -i is denied"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"apply_patch <<PATCH_EOF"}}')
assert_exit_code 2 "$STATUS" "entry gate: unarmed shell-mediated apply_patch is denied"

STATUS=$(run_hook '{"tool_name":"Read","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/functions/index.js"}}')
assert_exit_code 0 "$STATUS" "entry gate: unarmed Read passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"git status && grep -m1 ^VDGG_REQUIRED= .vdgg-target"}}')
assert_exit_code 0 "$STATUS" "entry gate: unarmed read-only bash passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"grep -r pattern src 2>/dev/null"}}')
assert_exit_code 0 "$STATUS" "entry gate: harmless stderr redirect to /dev/null passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"npm run build > /dev/null 2>&1"}}')
assert_exit_code 0 "$STATUS" "entry gate: build with output discarded to /dev/null passes"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"grep pattern functions/index.js 2>/dev/null > out.txt"}}')
assert_exit_code 2 "$STATUS" "entry gate: real file redirect is still denied alongside /dev/null"

STATUS=$(run_hook '{"tool_name":"Bash","cwd":"'"$ENTRY_DIR"'","tool_input":{"command":"source .agents/skills/vibesdegogo/scripts/vdgg-state.sh\nvdgg_state_init"}}')
assert_exit_code 0 "$STATUS" "entry gate: the arming command itself passes"

# Armed session in the same repository: entry gate steps aside, phase guards rule.
mkdir -p "$ENTRY_DIR/.codex" "$ENTRY_DIR/tasks/vdgg/entry-id"
printf 'entry-id\n' > "$ENTRY_DIR/.codex/.vdgg-active"
cat > "$ENTRY_DIR/.codex/.vdgg-state-entry-id" <<EOF
step=3
phase=investigating
loop_count=0
current_task=T
task_allowlist_file=
task_base_ref=
vdgg_id=entry-id
last_updated=2026-07-05T00:00:00Z
EOF
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/tasks/vdgg/entry-id/investigation.md"}}')
assert_exit_code 0 "$STATUS" "entry gate: armed session follows normal phase rules (task notes pass)"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/functions/index.js"}}')
assert_exit_code 2 "$STATUS" "entry gate: armed session still phase-blocks implementation edits"
rm -f "$ENTRY_DIR/.codex/.vdgg-active" "$ENTRY_DIR/.codex/.vdgg-state-entry-id"

# Off / absent key: historical fail-open behavior is unchanged.
printf 'VDGG_REQUIRED=off\n' > "$ENTRY_DIR/.vdgg-target"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/functions/index.js"}}')
assert_exit_code 0 "$STATUS" "entry gate: VDGG_REQUIRED=off keeps fail-open"

rm -f "$ENTRY_DIR/.vdgg-target"
STATUS=$(run_hook '{"tool_name":"Edit","cwd":"'"$ENTRY_DIR"'","tool_input":{"file_path":"'"$ENTRY_DIR"'/functions/index.js"}}')
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
