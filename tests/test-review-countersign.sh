#!/bin/bash
# Tests for Layer 3 adversarial countersign (`vdgg_review_countersign`), CC edition.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

SANDBOX=$(mktemp -d -t vdgg-review-countersign-XXXXXX)
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
export VDGG_STATE_DIR="$SANDBOX/repo/.claude"
export VDGG_TASKS_DIR="$SANDBOX/repo/tasks/vdgg"
mkdir -p "$VDGG_STATE_DIR"

# shellcheck source=/dev/null
. "$REPO_ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"
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

# --- Case 1: primary with medium finding -> countersign is a no-op (return 0),
#     command never runs, sentinel stays at countersign=none.
fresh
# Also verify: primary-with-medium sets countersign_required=0 (Layer 3 skips
# non-clean primaries), so the gate opens without any countersign call.

cat > "$SANDBOX/primary-medium.json" <<EOF
{ "lens_count": 3, "coverage": [ $diff_hunk ],
  "findings": [ {"file":"src/example.txt","line":2,"severity":"medium","summary":"x","fix":"y","cost":"low"} ] }
EOF
vdgg_review_run --review-output "$SANDBOX/primary-medium.json" true
assert_eq 0 "$?" "primary with medium must schema-pass"
touch "$SANDBOX/should-not-exist"
rm -f "$SANDBOX/should-not-exist"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-medium.json" \
    --countersign-output "$SANDBOX/cs-noop.json" \
    -- touch "$SANDBOX/should-not-exist"
assert_eq 0 "$?" "countersign is no-op when primary has medium"
assert_file_not_exists "$SANDBOX/should-not-exist" "no-op must not run command"
grep -q '^countersign=none$' "$SENTINEL" || fail "sentinel countersign still none"
grep -q '^countersign_required=0$' "$SENTINEL" || fail "medium primary must record countersign_required=0"
_vdgg_review_gate_ready "$SENTINEL"
assert_eq 0 "$?" "gate-ready must accept non-clean primary without countersign"

# --- Case 2: primary clean, countersign returns clean -> sentinel countersign=clean.
fresh
write_valid_review "$SANDBOX/primary-clean.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean.json" true
assert_eq 0 "$?" "primary clean must pass"
grep -q '^countersign=none$' "$SENTINEL" || fail "pre-countersign is none"
CS_OUT="$SANDBOX/cs-clean.json"
CS_SRC="$SANDBOX/cs-clean-src.json"
write_valid_review "$CS_SRC"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean.json" \
    --countersign-output "$CS_OUT" \
    -- cp "$CS_SRC" "$CS_OUT"
assert_eq 0 "$?" "clean countersign must succeed"
grep -q '^countersign=clean$' "$SENTINEL" || fail "sentinel must flip to countersign=clean"
grep -q '^schema_validated=1$' "$SENTINEL" || fail "schema_validated stays 1 after clean countersign"
grep -q '^countersign_required=1$' "$SENTINEL" || fail "countersign_required stays 1 after clean countersign"
# gate-read policy: after clean countersign, gate opens
_vdgg_review_gate_ready "$SENTINEL"
assert_eq 0 "$?" "gate-ready must accept clean countersign"

# --- Case 3: primary clean, countersign surfaces medium -> refuted, non-zero exit.
fresh
write_valid_review "$SANDBOX/primary-clean2.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean2.json" true
assert_eq 0 "$?" "primary clean 2 must pass"
CS_OUT2="$SANDBOX/cs-refute.json"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean2.json" \
    --countersign-output "$CS_OUT2" \
    -- bash -c "cat > '$CS_OUT2' <<EOF
{ \"lens_count\": 3, \"coverage\": [ $diff_hunk ],
  \"findings\": [ {\"file\":\"src/example.txt\",\"line\":2,\"severity\":\"medium\",\"summary\":\"missed by primary\",\"fix\":\"do it\",\"cost\":\"low\"} ] }
EOF"
assert_ne 0 "$?" "refuted countersign must fail"
grep -q '^countersign=none$' "$SENTINEL" || fail "refuted countersign must NOT flip sentinel"

# --- Case 4: primary clean, countersign output fails schema -> exit 1, sentinel unchanged.
fresh
write_valid_review "$SANDBOX/primary-clean3.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean3.json" true
CS_OUT3="$SANDBOX/cs-badschema.json"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean3.json" \
    --countersign-output "$CS_OUT3" \
    -- bash -c "echo prose > '$CS_OUT3'"
assert_ne 0 "$?" "bad-schema countersign must fail"
grep -q '^countersign=none$' "$SENTINEL" || fail "bad-schema must NOT flip sentinel"

# --- Case 5: primary clean, countersign output has lens_count=1 -> Layer 2 fail.
fresh
write_valid_review "$SANDBOX/primary-clean4.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean4.json" true
CS_OUT4="$SANDBOX/cs-lens1.json"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean4.json" \
    --countersign-output "$CS_OUT4" \
    -- bash -c "cat > '$CS_OUT4' <<EOF
{ \"lens_count\": 1, \"coverage\": [ $diff_hunk ], \"findings\": [] }
EOF"
assert_ne 0 "$?" "lens<3 countersign must fail"
grep -q '^countersign=none$' "$SENTINEL" || fail "lens<3 must NOT flip sentinel"

# --- Case 6: primary clean, countersign command itself fails -> exit 1.
fresh
write_valid_review "$SANDBOX/primary-clean5.json"
vdgg_review_run --review-output "$SANDBOX/primary-clean5.json" true
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-clean5.json" \
    --countersign-output "$SANDBOX/cs-cmdfail.json" \
    -- false
assert_ne 0 "$?" "command failure must propagate"
grep -q '^countersign=none$' "$SENTINEL" || fail "cmd fail must NOT flip sentinel"

# --- Case 7: primary all-low (no high/medium) -> countersign runs.
fresh
cat > "$SANDBOX/primary-low.json" <<EOF
{ "lens_count": 3, "coverage": [ $diff_hunk ],
  "findings": [ {"file":"src/example.txt","line":2,"severity":"low","summary":"nit","fix":"tweak","cost":"low"} ] }
EOF
vdgg_review_run --review-output "$SANDBOX/primary-low.json" true
CS_OUT7="$SANDBOX/cs-low-primary.json"
CS_SRC7="$SANDBOX/cs-low-primary-src.json"
write_valid_review "$CS_SRC7"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-low.json" \
    --countersign-output "$CS_OUT7" \
    -- cp "$CS_SRC7" "$CS_OUT7"
assert_eq 0 "$?" "all-low primary must trigger countersign successfully"
grep -q '^countersign=clean$' "$SENTINEL" || fail "all-low primary + clean cs -> countersign=clean"

# --- Case 8: modified/modified_files preserved across countersign write
#     Regression: a posttool-set modified=1 must NOT be silently cleared when
#     vdgg_review_countersign overwrites the sentinel with countersign=clean.
fresh
write_valid_review "$SANDBOX/primary-mod.json"
vdgg_review_run --review-output "$SANDBOX/primary-mod.json" true
assert_eq 0 "$?" "primary write passes (mod-preserve case)"
# Simulate what the PostToolUse hook does: append modified=1 to the sentinel.
# Emulate the hook's grep-v-and-append pattern.
_TMP=$(mktemp)
grep -v '^modified=' "$SENTINEL" | grep -v '^modified_files=' > "$_TMP"
printf 'modified=1\nmodified_files=some/edited/file.swift\n' >> "$_TMP"
mv "$_TMP" "$SENTINEL"
grep -q '^modified=1$' "$SENTINEL" || fail "test setup: modified=1 seeded"
CS_MOD_OUT="$SANDBOX/cs-mod.json"
CS_MOD_SRC="$SANDBOX/cs-mod-src.json"
write_valid_review "$CS_MOD_SRC"
vdgg_review_countersign \
    --original-output "$SANDBOX/primary-mod.json" \
    --countersign-output "$CS_MOD_OUT" \
    -- cp "$CS_MOD_SRC" "$CS_MOD_OUT"
assert_eq 0 "$?" "clean countersign succeeds when modified=1"
grep -q '^modified=1$' "$SENTINEL" || fail "modified=1 must be preserved across countersign write"
grep -q '^modified_files=some/edited/file.swift$' "$SENTINEL" || fail "modified_files must be preserved across countersign write"
grep -q '^countersign=clean$' "$SENTINEL" || fail "countersign flipped to clean"

# --- Case 9: bad args
vdgg_review_countersign 2>/dev/null
assert_ne 0 "$?" "no args must fail"
vdgg_review_countersign --original-output "$SANDBOX/primary-clean.json" 2>/dev/null
assert_ne 0 "$?" "missing --countersign-output must fail"
vdgg_review_countersign --original-output "$SANDBOX/nope.json" --countersign-output "$SANDBOX/x.json" -- true 2>/dev/null
assert_ne 0 "$?" "missing original file must fail"

echo "OK"
