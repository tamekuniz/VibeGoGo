#!/bin/bash
# Tests for Layer 1 review-output schema validation (Codex edition).
# Mirrors test-review-schema.sh but sources the .agents/ variant of the
# state helpers.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

SANDBOX=$(mktemp -d -t vdgg-codex-review-schema-XXXXXX)
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
# Codex edition writes sentinels under .codex/, so match that layout.
export VDGG_STATE_DIR="$SANDBOX/repo/.codex"
export VDGG_TASKS_DIR="$SANDBOX/repo/tasks/vdgg"
mkdir -p "$VDGG_STATE_DIR"

# The Codex state script uses `set -euo pipefail`; loading it sets errexit
# on the caller too, which would kill this test on the very first expected
# non-zero return. Turn errexit back off so we can observe failures.
# shellcheck source=/dev/null
. "$REPO_ROOT/.agents/skills/vibesdegogo/scripts/vdgg-state.sh"
set +e

vdgg_state_init >/dev/null
ID=$(vdgg_get_id)
SENTINEL="$VDGG_STATE_DIR/.vdgg-review-sentinel-${ID}-0"

fresh() { rm -f "$SENTINEL"; }
diff_hunk_for_example() { printf '{"file":"src/example.txt","hunk_start":2,"hunk_lines":2,"judgment":"ok"}'; }
valid_review() {
    cat <<EOF
{
  "lens_count": 3,
  "coverage": [ $(diff_hunk_for_example) ],
  "findings": []
}
EOF
}

fresh
: > "$SANDBOX/empty.json"
vdgg_review_run --review-output "$SANDBOX/empty.json" true 2>/dev/null
assert_ne 0 "$?" "empty review output must fail (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel after empty fail (codex)"

fresh
echo "prose" > "$SANDBOX/prose.json"
vdgg_review_run --review-output "$SANDBOX/prose.json" true 2>/dev/null
assert_ne 0 "$?" "prose must fail (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel after prose fail (codex)"

fresh
echo '{}' > "$SANDBOX/empty-obj.json"
vdgg_review_run --review-output "$SANDBOX/empty-obj.json" true 2>/dev/null
assert_ne 0 "$?" "empty object must fail (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel after empty-obj (codex)"

fresh
cat > "$SANDBOX/bad-finding.json" <<EOF
{
  "coverage": [ $(diff_hunk_for_example) ],
  "findings": [ {"file":"src/example.txt","line":2,"severity":"low","summary":"x","cost":"low"} ]
}
EOF
vdgg_review_run --review-output "$SANDBOX/bad-finding.json" true 2>/dev/null
assert_ne 0 "$?" "finding without fix must fail (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel for schema violation (codex)"

fresh
cat > "$SANDBOX/no-coverage.json" <<'EOF'
{
  "coverage": [ {"file":"other/file.swift","hunk_start":10,"hunk_lines":3,"judgment":"ok"} ],
  "findings": []
}
EOF
vdgg_review_run --review-output "$SANDBOX/no-coverage.json" true 2>/dev/null
assert_ne 0 "$?" "coverage miss must fail (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel for coverage miss (codex)"

fresh
valid_review > "$SANDBOX/good.json"
vdgg_review_run --review-output "$SANDBOX/good.json" true
assert_eq 0 "$?" "valid review must pass (codex)"
assert_file_exists "$SENTINEL" "sentinel must exist after valid review (codex)"

fresh
STDERR=$(vdgg_review_run true 2>&1 1>/dev/null)
echo "$STDERR" | grep -q 'skipping Layer 1' || fail "backward-compat call must warn (codex)"
assert_file_exists "$SENTINEL" "backward-compat must write sentinel (codex)"

# untracked file regression (mirrors CC edition, lessons L1)
fresh
echo "brand new implementation line" > "$SANDBOX/repo/src/new_impl.txt"
cat > "$SANDBOX/omit-new.json" <<EOF
{ "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/omit-new.json" true 2>/dev/null
assert_ne 0 "$?" "coverage that omits untracked new file must fail (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel when untracked missing (codex)"

fresh
cat > "$SANDBOX/cover-new.json" <<EOF
{
  "lens_count": 3,
  "coverage": [
    $(diff_hunk_for_example),
    {"file":"src/new_impl.txt","hunk_start":1,"hunk_lines":1,"judgment":"ok"}
  ],
  "findings": []
}
EOF
vdgg_review_run --review-output "$SANDBOX/cover-new.json" true
assert_eq 0 "$?" "coverage including untracked file must pass (codex)"
assert_file_exists "$SENTINEL" "sentinel exists after passing coverage (codex)"
rm -f "$SANDBOX/repo/src/new_impl.txt"

# Layer 4: sentinel extended fields (codex mirror of CC test 10)
fresh
cat > "$SANDBOX/l4-review.json" <<EOF
{ "lens_count": 3, "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/l4-review.json" true
assert_eq 0 "$?" "Layer 4 sentinel path must succeed (codex)"
assert_file_exists "$SENTINEL" "sentinel present (codex)"
grep -q '^schema_validated=1$' "$SENTINEL" || fail "schema_validated=1 (codex)"
grep -q '^lens_count=3$' "$SENTINEL" || fail "lens_count=3 (codex)"
grep -q '^countersign=none$' "$SENTINEL" || fail "countersign=none (codex)"
grep -q '^review_output_hash=[0-9a-f]\{64\}$' "$SENTINEL" || fail "hash sha256 (codex)"
grep -q '^countersign_required=1$' "$SENTINEL" || fail "clean primary countersign_required=1 (codex)"
_vdgg_review_gate_ready "$SENTINEL" 2>/dev/null
assert_ne 0 "$?" "gate-ready blocks clean primary without countersign (codex)"

# Layer 4: backward-compat path (codex mirror of CC test 11)
fresh
STDERR=$(vdgg_review_run true 2>&1 1>/dev/null)
echo "$STDERR" | grep -q 'skipping Layer 1' || fail "legacy warn (codex)"
assert_file_exists "$SENTINEL" "legacy writes sentinel (codex)"
grep -q '^schema_validated=0$' "$SENTINEL" || fail "legacy schema_validated=0 (codex)"
grep -q '^countersign_required=1$' "$SENTINEL" || fail "legacy countersign_required=1 (codex)"
_vdgg_review_gate_ready "$SENTINEL" 2>/dev/null
assert_ne 0 "$?" "gate-ready blocks legacy sentinels (codex)"

# Shape assertion (codex mirror of CC tests 12-14)
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "" 3 none 1 2>/dev/null
assert_ne 0 "$?" "schema=1 no hash must fail (codex)"
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "abc" 0 none 1 2>/dev/null
assert_ne 0 "$?" "schema=1 lens=0 must fail (codex)"
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "abc" 3 bogus 1 2>/dev/null
assert_ne 0 "$?" "bogus countersign must fail (codex)"

# Invariant helper (codex mirror of CC tests 15-17)
_vdgg_render_sentinel_body "2026-01-01T00:00:00Z" 0 "" "" 3 none 0 > "$SANDBOX/bad-sentinel"
_vdgg_validate_sentinel_fields "$SANDBOX/bad-sentinel" 2>/dev/null
assert_ne 0 "$?" "schema=0 lens>0 rejected (codex)"

_vdgg_render_sentinel_body "2026-01-01T00:00:00Z" 0 "" "deadbeef" 3 none 1 > "$SANDBOX/good-sentinel"
_vdgg_validate_sentinel_fields "$SANDBOX/good-sentinel"
assert_eq 0 "$?" "valid L4 sentinel passes (codex)"

cat > "$SANDBOX/legacy-sentinel" <<EOF
started=1
started_at=2026-01-01T00:00:00Z
modified=0
modified_files=
EOF
_TAG=$(_vdgg_validate_sentinel_fields "$SANDBOX/legacy-sentinel")
assert_eq 0 "$?" "legacy exits 0 (codex)"
assert_eq legacy "$_TAG" "legacy tag on stdout (codex)"
_TAG=$(_vdgg_validate_sentinel_fields "$SANDBOX/good-sentinel")
assert_eq 0 "$?" "layer-4 exits 0 (codex)"
assert_eq layer4 "$_TAG" "layer4 tag on stdout (codex)"
_vdgg_validate_sentinel_fields "$SANDBOX/bad-sentinel" 2>/dev/null
assert_eq 1 "$?" "violation exits 1 (codex)"

_vdgg_render_sentinel_body "2026-01-01T00:00:00Z" 0 "" "deadbeef" 3 none 1 bogus > "$SANDBOX/bogus-cs-req"
_vdgg_validate_sentinel_fields "$SANDBOX/bogus-cs-req" 2>/dev/null
assert_ne 0 "$?" "countersign_required=bogus rejected (codex)"

fresh
_vdgg_write_review_sentinel "deadbeef" 3 clean 1 1 2>/dev/null
assert_ne 0 "$?" "unauthorized _vdgg_write_review_sentinel refused (codex)"
assert_file_not_exists "$SENTINEL" "unauthorized write no sentinel (codex)"

fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "" "" "" "" "" 2>/dev/null
assert_ne 0 "$?" "all-empty payload refused as legacy-shape bypass (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel from bypass (codex)"

# _vdgg_extract_lens_count smoke (codex mirror)
cat > "$SANDBOX/lens5.json" <<EOF
{ "lens_count": 5, "coverage": [], "findings": [] }
EOF
assert_eq 5 "$(_vdgg_extract_lens_count "$SANDBOX/lens5.json")" "extract_lens_count returns 5 (codex)"
cat > "$SANDBOX/lens-missing.json" <<EOF
{ "coverage": [], "findings": [] }
EOF
assert_eq 0 "$(_vdgg_extract_lens_count "$SANDBOX/lens-missing.json")" "missing lens_count -> 0 (codex)"

# Layer 2: lens_count < 3 rejected (codex mirror)
fresh
cat > "$SANDBOX/single-lens.json" <<EOF
{ "lens_count": 1, "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/single-lens.json" true 2>/dev/null
assert_ne 0 "$?" "lens_count=1 rejected by Layer 2 (codex)"
assert_file_not_exists "$SENTINEL" "no sentinel when lens<3 (codex)"

fresh
cat > "$SANDBOX/no-lens.json" <<EOF
{ "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/no-lens.json" true 2>/dev/null
assert_ne 0 "$?" "missing lens_count rejected by Layer 2 (codex)"

echo "OK"
