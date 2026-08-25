#!/bin/bash
# Tests for Layer 1 review-output schema validation (CC edition).
# Exercises _vdgg_validate_review_output and vdgg_review_run --review-output.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

SANDBOX=$(mktemp -d -t vdgg-review-schema-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

# Fresh throwaway git repo so _vdgg_diff_hunks has something to inspect.
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
# Introduce a hunk in the working tree so coverage checks have targets.
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

vdgg_state_init >/dev/null
ID=$(vdgg_get_id)
SENTINEL="$VDGG_STATE_DIR/.vdgg-review-sentinel-${ID}-0"

# ---- helpers --------------------------------------------------------------

fresh() {
    # Remove any prior sentinel so each case starts clean.
    rm -f "$SENTINEL"
}

diff_hunk_for_example() {
    # After the modification above, git diff produces "@@ -2,2 +2,2 @@"
    # (2 lines changed starting at new-side line 2). Coverage must cite this.
    printf '{"file":"src/example.txt","hunk_start":2,"hunk_lines":2,"judgment":"ok"}'
}

valid_review() {
    # Layer 4 requires a positive lens_count when schema=1 is recorded, so
    # every valid fixture in this file names one — this is also the shape
    # Layer 2 multi-perspective reviews use in the field.
    cat <<EOF
{
  "lens_count": 3,
  "coverage": [ $(diff_hunk_for_example) ],
  "findings": []
}
EOF
}

# ---- cases ----------------------------------------------------------------

# 1) empty file -> validation fails, sentinel absent
fresh
: > "$SANDBOX/empty.json"
vdgg_review_run --review-output "$SANDBOX/empty.json" true 2>/dev/null
assert_ne 0 "$?" "empty review output must fail"
assert_file_not_exists "$SENTINEL" "sentinel must not exist after empty-file fail"

# 2) prose (non-JSON) -> validation fails
fresh
echo "just some prose, not JSON" > "$SANDBOX/prose.json"
vdgg_review_run --review-output "$SANDBOX/prose.json" true 2>/dev/null
assert_ne 0 "$?" "prose review output must fail"
assert_file_not_exists "$SENTINEL" "sentinel must not exist after prose fail"

# 3) empty object -> missing coverage/findings
fresh
echo '{}' > "$SANDBOX/empty-obj.json"
vdgg_review_run --review-output "$SANDBOX/empty-obj.json" true 2>/dev/null
assert_ne 0 "$?" "empty object must fail"
assert_file_not_exists "$SENTINEL" "sentinel must not exist after empty-obj fail"

# 4) findings entry missing required field -> fail
fresh
cat > "$SANDBOX/bad-finding.json" <<EOF
{
  "coverage": [ $(diff_hunk_for_example) ],
  "findings": [ {"file":"src/example.txt","line":2,"severity":"low","summary":"x","cost":"low"} ]
}
EOF
vdgg_review_run --review-output "$SANDBOX/bad-finding.json" true 2>/dev/null
assert_ne 0 "$?" "finding without fix must fail"
assert_file_not_exists "$SENTINEL" "sentinel must not exist for schema violation"

# 5) coverage missing the diff hunk -> fail
fresh
cat > "$SANDBOX/no-coverage.json" <<'EOF'
{
  "coverage": [ {"file":"other/file.swift","hunk_start":10,"hunk_lines":3,"judgment":"ok"} ],
  "findings": []
}
EOF
vdgg_review_run --review-output "$SANDBOX/no-coverage.json" true 2>/dev/null
assert_ne 0 "$?" "coverage that misses a diff hunk must fail"
assert_file_not_exists "$SENTINEL" "sentinel must not exist for coverage miss"

# 6) valid schema + valid coverage -> pass, sentinel exists
fresh
valid_review > "$SANDBOX/good.json"
vdgg_review_run --review-output "$SANDBOX/good.json" true
assert_eq 0 "$?" "valid review must pass"
assert_file_exists "$SENTINEL" "sentinel must exist after valid review"

# 7) --review-output not supplied -> warning + sentinel written (backward compat)
fresh
STDERR=$(vdgg_review_run true 2>&1 1>/dev/null)
echo "$STDERR" | grep -q 'skipping Layer 1' || fail "backward-compat call must warn about skipping Layer 1"
assert_file_exists "$SENTINEL" "backward-compat call must still write sentinel"

# 8) untracked new file must be included in coverage (lessons L1 regression)
fresh
echo "brand new implementation line" > "$SANDBOX/repo/src/new_impl.txt"
cat > "$SANDBOX/omit-new.json" <<EOF
{ "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/omit-new.json" true 2>/dev/null
assert_ne 0 "$?" "coverage that omits an untracked new file must fail"
assert_file_not_exists "$SENTINEL" "sentinel must not exist when new file uncovered"

# 9) same untracked file, this time covered -> pass
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
assert_eq 0 "$?" "valid coverage including untracked file must pass"
assert_file_exists "$SENTINEL" "sentinel must exist after passing coverage"
rm -f "$SANDBOX/repo/src/new_impl.txt"

# 10) Layer 4: sentinel written by --review-output has extended fields set
fresh
cat > "$SANDBOX/l4-review.json" <<EOF
{ "lens_count": 3, "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/l4-review.json" true
assert_eq 0 "$?" "Layer 4 sentinel path must succeed"
assert_file_exists "$SENTINEL" "sentinel present"
grep -q '^schema_validated=1$' "$SENTINEL" || fail "schema_validated=1 must be recorded"
grep -q '^lens_count=3$' "$SENTINEL" || fail "lens_count=3 must be read from review output"
grep -q '^countersign=none$' "$SENTINEL" || fail "countersign=none must be recorded"
grep -q '^review_output_hash=[0-9a-f]\{64\}$' "$SENTINEL" || fail "review_output_hash must be a sha256 hex string"
grep -q '^countersign_required=1$' "$SENTINEL" || fail "clean primary must record countersign_required=1"
# _vdgg_review_gate_ready: clean primary without countersign must block
_vdgg_review_gate_ready "$SENTINEL" 2>/dev/null
assert_ne 0 "$?" "gate-ready must block clean primary without countersign"

# 11) Layer 4: backward-compat call records schema_validated=0, empty hash/lens
fresh
STDERR=$(vdgg_review_run true 2>&1 1>/dev/null)
echo "$STDERR" | grep -q 'skipping Layer 1' || fail "legacy compat must warn"
assert_file_exists "$SENTINEL" "legacy compat writes sentinel"
grep -q '^schema_validated=0$' "$SENTINEL" || fail "legacy path must record schema_validated=0"
grep -q '^lens_count=$' "$SENTINEL" || fail "legacy path must leave lens_count empty"
grep -q '^countersign_required=1$' "$SENTINEL" || fail "legacy path must set countersign_required=1 (gate-block shortcut)"
_vdgg_review_gate_ready "$SENTINEL" 2>/dev/null
assert_ne 0 "$?" "gate-ready must block legacy (--review-output-less) sentinels"

# 12) Shape assertion: _vdgg_write_review_sentinel refuses schema=1 without hash
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "" 3 none 1 2>/dev/null
assert_ne 0 "$?" "schema=1 without hash must fail write"
assert_file_not_exists "$SENTINEL" "no sentinel when shape assertion fires"

# 13) Shape assertion: schema=1 with lens_count=0 fails
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "abc" 0 none 1 2>/dev/null
assert_ne 0 "$?" "schema=1 with lens=0 must fail write"
assert_file_not_exists "$SENTINEL" "no sentinel when lens=0 asserted"

# 14) Shape assertion: countersign out of domain fails
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "abc" 3 bogus 1 2>/dev/null
assert_ne 0 "$?" "countersign=bogus must fail write"

# 15) Invariant helper: schema=0 with lens>0 rejected
fresh
_vdgg_render_sentinel_body "2026-01-01T00:00:00Z" 0 "" "" 3 none 0 > "$SANDBOX/bad-sentinel"
_vdgg_validate_sentinel_fields "$SANDBOX/bad-sentinel" 2>/dev/null
assert_ne 0 "$?" "schema=0 lens>0 must fail validation"

# 16) Invariant helper: valid Layer-4 sentinel passes
fresh
_vdgg_render_sentinel_body "2026-01-01T00:00:00Z" 0 "" "deadbeef" 3 none 1 > "$SANDBOX/good-sentinel"
_vdgg_validate_sentinel_fields "$SANDBOX/good-sentinel"
assert_eq 0 "$?" "valid Layer-4 sentinel must pass validation"

# 17) Invariant helper: legacy 4-field sentinel exits 0 with tag "legacy"
fresh
cat > "$SANDBOX/legacy-sentinel" <<EOF
started=1
started_at=2026-01-01T00:00:00Z
modified=0
modified_files=
EOF
_TAG=$(_vdgg_validate_sentinel_fields "$SANDBOX/legacy-sentinel")
assert_eq 0 "$?" "legacy sentinel must exit 0"
assert_eq legacy "$_TAG" "legacy sentinel must print 'legacy' on stdout"

# 17b) Layer-4 sentinel exits 0 with tag "layer4"
_TAG=$(_vdgg_validate_sentinel_fields "$SANDBOX/good-sentinel")
assert_eq 0 "$?" "layer-4 sentinel must exit 0"
assert_eq layer4 "$_TAG" "layer-4 sentinel must print 'layer4' on stdout"

# 17c) Invariant violation exits 1 (non-zero)
_vdgg_validate_sentinel_fields "$SANDBOX/bad-sentinel" 2>/dev/null
assert_eq 1 "$?" "invariant violation must exit 1"

# 17d) countersign_required domain: bogus value rejected by validator
_vdgg_render_sentinel_body "2026-01-01T00:00:00Z" 0 "" "deadbeef" 3 none 1 bogus > "$SANDBOX/bogus-cs-req"
_vdgg_validate_sentinel_fields "$SANDBOX/bogus-cs-req" 2>/dev/null
assert_ne 0 "$?" "countersign_required=bogus must be rejected"

# 17e) unauthorized direct call is refused (breadcrumb protects Layer 3)
fresh
_vdgg_write_review_sentinel "deadbeef" 3 clean 1 1 2>/dev/null
assert_ne 0 "$?" "unauthorized _vdgg_write_review_sentinel must refuse"
assert_file_not_exists "$SENTINEL" "unauthorized write must not produce sentinel"

# 17f) legacy-shape bypass: authorized but all-empty payload must refuse.
# Regression: without this refusal, `_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1
# _vdgg_write_review_sentinel "" "" "" "" ""` produced a sentinel that
# validator classified as 'legacy' and gate_ready accepted, opening the
# verified gate with no review artifact (loop=2 verify security finding).
fresh
_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1 _vdgg_write_review_sentinel "" "" "" "" "" 2>/dev/null
assert_ne 0 "$?" "all-empty payload must be refused as legacy-shape bypass"
assert_file_not_exists "$SENTINEL" "no sentinel from bypass attempt"

# _vdgg_extract_lens_count: shared extractor smoke test
cat > "$SANDBOX/lens5.json" <<EOF
{ "lens_count": 5, "coverage": [], "findings": [] }
EOF
assert_eq 5 "$(_vdgg_extract_lens_count "$SANDBOX/lens5.json")" "extract_lens_count returns 5"
cat > "$SANDBOX/lens-missing.json" <<EOF
{ "coverage": [], "findings": [] }
EOF
assert_eq 0 "$(_vdgg_extract_lens_count "$SANDBOX/lens-missing.json")" "missing lens_count sanitizes to 0"

# Layer 2: lens_count < 3 rejected by dedicated Layer 2 validator
fresh
cat > "$SANDBOX/single-lens.json" <<EOF
{ "lens_count": 1, "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/single-lens.json" true 2>/dev/null
assert_ne 0 "$?" "lens_count=1 must be rejected by Layer 2"
assert_file_not_exists "$SENTINEL" "no sentinel when lens_count below 3"

fresh
cat > "$SANDBOX/no-lens.json" <<EOF
{ "coverage": [ $(diff_hunk_for_example) ], "findings": [] }
EOF
vdgg_review_run --review-output "$SANDBOX/no-lens.json" true 2>/dev/null
assert_ne 0 "$?" "missing lens_count must be rejected by Layer 2"

echo "OK"
