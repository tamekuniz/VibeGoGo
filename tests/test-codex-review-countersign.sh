#!/bin/bash
# Tests for Layer 3 adversarial countersign, Codex edition mirror.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

SANDBOX=$(mktemp -d -t vdgg-codex-review-countersign-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX/repo"
cd "$SANDBOX/repo"
git init -q
git config user.email test@example.com
git config user.name test
mkdir -p src
cat > src/example.txt <<'INITIAL'
line1
line2
line3
INITIAL
git add . && git commit -q -m init
cat > src/example.txt <<'MODIFIED'
line1
changedA
changedB
line3
MODIFIED

export VDGG_CWD="$SANDBOX/repo"
export VDGG_STATE_DIR="$SANDBOX/repo/.codex"
export VDGG_TASKS_DIR="$SANDBOX/repo/tasks/vdgg"
mkdir -p "$VDGG_STATE_DIR"

# shellcheck source=/dev/null
. "$REPO_ROOT/.agents/skills/vibesdegogo/scripts/vdgg-state.sh"
set +e

vdgg_state_init >/dev/null
ID=$(vdgg_get_id)
SENTINEL="$VDGG_STATE_DIR/.vdgg-review-sentinel-${ID}-0"

diff_hunk='{"file":"src/example.txt","hunk_start":2,"hunk_lines":2,"judgment":"ok"}'

write_valid_review() {
    local path="$1"
    cat > "$path" <<EOF
{
  "lens_count": 3,
  "coverage": [ $diff_hunk ],
  "findings": []
}
EOF
}

fresh() { rm -f "$SENTINEL"; }

# Case 1: primary has medium -> countersign no-ops.
fresh
cat > "$SANDBOX/primary-med.json" <<EOF
{ "lens_count": 3, "coverage": [ $diff_hunk ],
  "findings": [ {"file":"src/example.txt","line":2,"severity":"medium","summary":"x","fix":"y","cost":"low"} ] }
EOF
vdgg_review_run --review-output "$SANDBOX/primary-med.json" true
assert_eq 0 "$?" "primary med passes schema (codex)"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-med.json" \
    --countersign-output "$SANDBOX/cs-noop.json" \
    -- touch "$SANDBOX/must-not-exist"
assert_eq 0 "$?" "medium primary -> no-op success (codex)"
assert_file_not_exists "$SANDBOX/must-not-exist" "no-op skipped command (codex)"
grep -q '^countersign=none$' "$SENTINEL" || fail "sentinel none (codex)"
grep -q '^countersign_required=0$' "$SENTINEL" || fail "medium primary countersign_required=0 (codex)"
_vdgg_review_gate_ready "$SENTINEL"
assert_eq 0 "$?" "gate-ready accepts non-clean primary (codex)"

# Case 2: primary clean, countersign clean -> countersign=clean.
fresh
write_valid_review "$SANDBOX/primary-clean.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean.json" true
CS_OUT="$SANDBOX/cs-clean.json"
CS_SRC="$SANDBOX/cs-clean-src.json"
write_valid_review "$CS_SRC"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean.json" \
    --countersign-output "$CS_OUT" \
    -- cp "$CS_SRC" "$CS_OUT"
assert_eq 0 "$?" "clean countersign succeeds (codex)"
grep -q '^countersign=clean$' "$SENTINEL" || fail "sentinel flips to clean (codex)"
grep -q '^countersign_required=1$' "$SENTINEL" || fail "countersign_required stays 1 after clean cs (codex)"
_vdgg_review_gate_ready "$SENTINEL"
assert_eq 0 "$?" "gate-ready accepts clean countersign (codex)"

# Case 3: countersign refutes -> fail, sentinel unchanged.
fresh
write_valid_review "$SANDBOX/primary-clean2.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean2.json" true
CS_OUT2="$SANDBOX/cs-refute.json"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean2.json" \
    --countersign-output "$CS_OUT2" \
    -- bash -c "cat > '$CS_OUT2' <<EOF
{ \"lens_count\": 3, \"coverage\": [ $diff_hunk ],
  \"findings\": [ {\"file\":\"src/example.txt\",\"line\":2,\"severity\":\"high\",\"summary\":\"missed\",\"fix\":\"x\",\"cost\":\"low\"} ] }
EOF"
assert_ne 0 "$?" "refuted countersign fails (codex)"
grep -q '^countersign=none$' "$SENTINEL" || fail "refuted keeps sentinel none (codex)"

# Case 4: countersign bad schema
fresh
write_valid_review "$SANDBOX/primary-clean3.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean3.json" true
CS_OUT3="$SANDBOX/cs-bad.json"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean3.json" \
    --countersign-output "$CS_OUT3" \
    -- bash -c "echo prose > '$CS_OUT3'"
assert_ne 0 "$?" "bad-schema countersign fails (codex)"

# Case 5: lens<3
fresh
write_valid_review "$SANDBOX/primary-clean4.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean4.json" true
CS_OUT4="$SANDBOX/cs-lens1.json"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean4.json" \
    --countersign-output "$CS_OUT4" \
    -- bash -c "cat > '$CS_OUT4' <<EOF
{ \"lens_count\": 2, \"coverage\": [ $diff_hunk ], \"findings\": [] }
EOF"
assert_ne 0 "$?" "lens<3 countersign fails (codex)"

# Case 6: command failure
fresh
write_valid_review "$SANDBOX/primary-clean5.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean5.json" true
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean5.json" \
    --countersign-output "$SANDBOX/cs-cmdfail.json" \
    -- false
assert_ne 0 "$?" "cmd failure propagates (codex)"

# Case 7: all-low primary triggers countersign
fresh
cat > "$SANDBOX/primary-low.json" <<EOF
{ "lens_count": 3, "coverage": [ $diff_hunk ],
  "findings": [ {"file":"src/example.txt","line":2,"severity":"low","summary":"nit","fix":"z","cost":"low"} ] }
EOF
vdgg_review_run --review-output "$SANDBOX/primary-low.json" true
CS_OUT7="$SANDBOX/cs-low-primary.json"
CS_SRC7="$SANDBOX/cs-low-primary-src.json"
write_valid_review "$CS_SRC7"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-low.json" \
    --countersign-output "$CS_OUT7" \
    -- cp "$CS_SRC7" "$CS_OUT7"
assert_eq 0 "$?" "all-low primary -> countersign runs (codex)"
grep -q '^countersign=clean$' "$SENTINEL" || fail "all-low + clean cs -> clean (codex)"

# Case 8: modified/modified_files preserved (codex mirror)
fresh
write_valid_review "$SANDBOX/primary-mod.json"
vdgg_review_run --review-output "$SANDBOX/primary-mod.json" true
assert_eq 0 "$?" "primary write passes (codex mod-preserve)"
_TMP=$(mktemp)
grep -v '^modified=' "$SENTINEL" | grep -v '^modified_files=' > "$_TMP"
printf 'modified=1\nmodified_files=some/edited/file.swift\n' >> "$_TMP"
mv "$_TMP" "$SENTINEL"
CS_MOD_OUT="$SANDBOX/cs-mod.json"
CS_MOD_SRC="$SANDBOX/cs-mod-src.json"
write_valid_review "$CS_MOD_SRC"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-mod.json" \
    --countersign-output "$CS_MOD_OUT" \
    -- cp "$CS_MOD_SRC" "$CS_MOD_OUT"
assert_eq 0 "$?" "clean countersign with modified=1 (codex)"
grep -q '^modified=1$' "$SENTINEL" || fail "modified=1 preserved (codex)"
grep -q '^modified_files=some/edited/file.swift$' "$SENTINEL" || fail "modified_files preserved (codex)"

# Case 9: bad args
vdgg_review_countersign 2>/dev/null
assert_ne 0 "$?" "no args fails (codex)"
vdgg_review_countersign --original-output "$SANDBOX/primary-clean.json" 2>/dev/null
assert_ne 0 "$?" "missing --countersign-output fails (codex)"
vdgg_review_countersign --original-output "$SANDBOX/nope.json" --countersign-output "$SANDBOX/x.json" -- true 2>/dev/null
assert_ne 0 "$?" "missing original file fails (codex)"

echo "OK"
