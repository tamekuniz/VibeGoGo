#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

cd "$TMPDIR_VDGG" || exit 1
VDGG_CWD="$TMPDIR_VDGG"
source "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"

vdgg_state_init >/tmp/vdgg-test-state-init.out 2>/tmp/vdgg-test-state-init.err
ID=$(vdgg_get_id)
assert_ne "" "$ID" "vdgg_state_init creates an id"
assert_file_exists ".claude/.vdgg-active" "active file exists"
assert_file_exists ".claude/.vdgg-state-${ID}" "state file exists"

set +e
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-state-bad.out 2>/tmp/vdgg-test-state-bad.err
BAD_STATUS=$?
set -e
assert_exit_code 1 "$BAD_STATUS" "invalid step jump is rejected"
CURRENT_STEP=$(grep '^step=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "1" "$CURRENT_STEP" "invalid transition leaves state unchanged"

vdgg_state_advance 2 requirements >/tmp/vdgg-test-state-2.out 2>/tmp/vdgg-test-state-2.err
vdgg_state_advance 3 investigating >/tmp/vdgg-test-state-3.out 2>/tmp/vdgg-test-state-3.err
vdgg_state_advance 4 planning >/tmp/vdgg-test-state-4.out 2>/tmp/vdgg-test-state-4.err
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-state-5.out 2>/tmp/vdgg-test-state-5.err
vdgg_state_advance 6 implementing >/tmp/vdgg-test-state-6.out 2>/tmp/vdgg-test-state-6.err
vdgg_state_loop 6 implementing >/tmp/vdgg-test-state-loop.out 2>/tmp/vdgg-test-state-loop.err
LOOP_COUNT=$(grep '^loop_count=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "1" "$LOOP_COUNT" "vdgg_state_loop increments loop_count"

vdgg_state_advance 7 testing >/tmp/vdgg-test-state-7.out 2>/tmp/vdgg-test-state-7.err
# The manual review marker is gone. The only way to write a review sentinel is
# vdgg_review_run, which requires a review command that actually exits 0.
set +e
type vdgg_state_mark_reviewed >/dev/null 2>&1
STATUS=$?
set -e
assert_ne "0" "$STATUS" "vdgg_state_mark_reviewed is no longer a public helper"
vdgg_review_run true >/tmp/vdgg-test-state-review.out 2>/tmp/vdgg-test-state-review.err
assert_file_exists ".claude/.vdgg-review-sentinel-${ID}-1" "review_run creates review sentinel"
MODIFIED=$(grep '^modified=' ".claude/.vdgg-review-sentinel-${ID}-1" | cut -d= -f2)
assert_eq "0" "$MODIFIED" "review sentinel records modified=0"

vdgg_state_write 7 testing 1 "T" "/tmp/vdgg-al" "/tmp/vdgg-bs" >/tmp/vdgg-test-state-fields.out 2>/tmp/vdgg-test-state-fields.err
ALLOWLIST_FIELD=$(grep '^task_allowlist_file=' ".claude/.vdgg-state-${ID}" | cut -d= -f2-)
assert_eq "/tmp/vdgg-al" "$ALLOWLIST_FIELD" "task fields can be set via vdgg_state_write"

vdgg_state_advance 8 progress >/tmp/vdgg-test-state-8.out 2>/tmp/vdgg-test-state-8.err
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-state-8to5.out 2>/tmp/vdgg-test-state-8to5.err
LOOP_COUNT=$(grep '^loop_count=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "0" "$LOOP_COUNT" "8 to 5 resets loop_count"
ALLOWLIST_FIELD=$(grep '^task_allowlist_file=' ".claude/.vdgg-state-${ID}" | cut -d= -f2-)
assert_eq "" "$ALLOWLIST_FIELD" "8 to 5 clears the previous task allowlist"
BASE_REF_FIELD=$(grep '^task_base_ref=' ".claude/.vdgg-state-${ID}" | cut -d= -f2-)
assert_eq "" "$BASE_REF_FIELD" "8 to 5 clears the previous task baseline"

vdgg_state_advance 6 implementing >/tmp/vdgg-test-state-6b.out 2>/tmp/vdgg-test-state-6b.err
vdgg_state_write 7 testing 2 >/tmp/vdgg-test-state-write7.out 2>/tmp/vdgg-test-state-write7.err
vdgg_state_advance 6 reflection >/tmp/vdgg-test-state-7to6.out 2>/tmp/vdgg-test-state-7to6.err
LOOP_COUNT=$(grep '^loop_count=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "2" "$LOOP_COUNT" "7 to 6 preserves loop_count"

vdgg_state_clear >/tmp/vdgg-test-state-clear.out 2>/tmp/vdgg-test-state-clear.err
assert_file_not_exists ".claude/.vdgg-active" "clear removes active file"
assert_file_not_exists ".claude/.vdgg-state-${ID}" "clear removes state file"
assert_file_not_exists ".claude/.vdgg-review-sentinel-${ID}-1" "clear removes review sentinels"

# vdgg_review_run: success writes the review sentinel, failure does not.
vdgg_state_init >/tmp/vdgg-test-review-init.out 2>/tmp/vdgg-test-review-init.err
ID2=$(vdgg_get_id)
set +e
vdgg_review_run false >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "review_run propagates failing review"
assert_file_not_exists ".claude/.vdgg-review-sentinel-${ID2}-0" "failing review writes no sentinel"
set +e
vdgg_review_run true >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "review_run succeeds with passing review"
assert_file_exists ".claude/.vdgg-review-sentinel-${ID2}-0" "passing review writes sentinel"

# vdgg_review_run with REVIEW_COMMAND from .vdgg-target.
rm -f ".claude/.vdgg-review-sentinel-${ID2}-0"
printf 'REVIEW_COMMAND="true"\n' > .vdgg-target
set +e
vdgg_review_run >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "review_run uses REVIEW_COMMAND from .vdgg-target"
assert_file_exists ".claude/.vdgg-review-sentinel-${ID2}-0" "target-config review writes sentinel"
rm -f .vdgg-target

# P1-Both-3: vdgg_state_write rejects an unknown phase (enumeration, not regex).
CUR_STEP=$(grep '^step=' ".claude/.vdgg-state-${ID2}" | cut -d= -f2)
set +e
vdgg_state_write "$CUR_STEP" bogusphase 0 >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "unknown phase is rejected by vdgg_state_write"

vdgg_state_clear >/dev/null 2>&1

# --- Formation: every step can name the AI (and model) that runs it ----------
export VDGG_CONFIG_DIR="$TMPDIR_VDGG/user-config"
mkdir -p "$VDGG_CONFIG_DIR/formations" "$VDGG_CONFIG_DIR/executors" "$TMPDIR_VDGG/bin"
EXECUTOR="$TMPDIR_VDGG/bin/test-executor"
printf '#!/bin/sh\nprintf "ran\\n" > "$VDGG_EXECUTOR_OUTPUT"\n' > "$EXECUTOR"
chmod +x "$EXECUTOR"
printf 'COMMAND=%s\n' "$EXECUTOR" > "$VDGG_CONFIG_DIR/executors/qwen.conf"

cat > "$VDGG_CONFIG_DIR/formations/allsteps.conf" <<'CONF'
0: primary
0G: qwen
1: primary
2: primary
3: qwen
4: qwen
5: primary
6: qwen
6R: primary
7: sonnet5
8: primary
9: haiku45
--
free-form memo below the separator
9: ignored
CONF

set +e
vdgg_formation_preflight allsteps >/tmp/vdgg-test-formation.out 2>/tmp/vdgg-test-formation.err
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "formation with every step listed is accepted"
assert_eq "inline" "$(vdgg_formation_resolve STEP_1_AI allsteps)" "primary resolves to inline"
assert_eq "qwen" "$(vdgg_formation_resolve STEP_3_AI allsteps)" "a delegated seat resolves to its executor"
assert_eq "qwen" "$(vdgg_formation_resolve STEP_0_GRILL_AI allsteps)" "0G is the Grill Me seat"
assert_eq "sonnet5" "$(vdgg_formation_resolve STEP_7_AI allsteps)" "a model shorthand resolves on seat 7"
assert_eq "haiku45" "$(vdgg_formation_resolve STEP_9_AI allsteps)" "seat 9 accepts a model shorthand"

_vdgg_parse_seat_value "sonnet5" "STEP_7_AI"
assert_eq "claude" "$_VDGG_SEAT_NAME" "sonnet5 expands to the claude wrapper"
assert_eq "claude-sonnet-5" "$_VDGG_SEAT_MODEL" "sonnet5 expands to a full model id"

printf '3: unknown-ai\n' > "$VDGG_CONFIG_DIR/formations/badai.conf"
set +e
vdgg_formation_preflight badai >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "an unknown AI is rejected"

set +e
vdgg_state_init --formation allsteps >/tmp/vdgg-test-formation-init.out 2>/tmp/vdgg-test-formation-init.err
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "state init accepts a formation"
IDF=$(vdgg_get_id)
assert_eq "allsteps" "$(grep '^formation=' ".claude/.vdgg-state-${IDF}" | cut -d= -f2-)" "state records the formation"

# Regression: formation must survive state rewrites (it was dropped on advance).
vdgg_state_advance 2 requirements >/dev/null 2>&1
assert_eq "allsteps" "$(grep '^formation=' ".claude/.vdgg-state-${IDF}" | cut -d= -f2-)" "formation survives a state advance"

# A pre-fix state file has no formation line; the env var recovers the session.
grep -v '^formation=' ".claude/.vdgg-state-${IDF}" > ".claude/.vdgg-state-${IDF}.tmp"
mv ".claude/.vdgg-state-${IDF}.tmp" ".claude/.vdgg-state-${IDF}"
export VDGG_FORMATION=allsteps
vdgg_state_advance 3 investigating >/dev/null 2>&1
unset VDGG_FORMATION
assert_eq "allsteps" "$(grep '^formation=' ".claude/.vdgg-state-${IDF}" | cut -d= -f2-)" "missing formation line falls back to VDGG_FORMATION"
vdgg_state_clear >/dev/null 2>&1

set +e
vdgg_state_init --formation badai >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "state init refuses an invalid formation"
assert_file_not_exists ".claude/.vdgg-active" "state stays unarmed for an invalid formation"

# --- MAGI seats: MELCHIOR / BALTHASAR / CASPER are addressable in formation --
cat > "$VDGG_CONFIG_DIR/formations/magi-seats.conf" <<'CONF'
0: primary
3: qwen
* : sonnet5
MAGI-M: qwen
magi-b: sonnet5
Magi-C: primary
CONF

set +e
vdgg_formation_preflight magi-seats >/tmp/vdgg-test-magi-formation.out 2>/tmp/vdgg-test-magi-formation.err
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "formation with MAGI seats is accepted"
assert_eq "qwen" "$(vdgg_formation_resolve MAGI_MELCHIOR_AI magi-seats)" "MAGI-M resolves to its executor"
assert_eq "sonnet5" "$(vdgg_formation_resolve MAGI_BALTHASAR_AI magi-seats)" "MAGI-B is case-insensitive (magi-b)"
assert_eq "inline" "$(vdgg_formation_resolve MAGI_CASPER_AI magi-seats)" "primary/inline on MAGI-C resolves to inline"

# Every casing is accepted (proves the character-class pattern, not a
# hand-picked alternation), matching the SKILL.md "case-insensitive" promise.
printf 'MaGi-M: qwen\n' > "$VDGG_CONFIG_DIR/formations/magi-mixedcase.conf"
set +e
vdgg_formation_preflight magi-mixedcase >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 0 "$STATUS" "MAGI seats accept arbitrary casing (MaGi-M)"
assert_eq "qwen" "$(vdgg_formation_resolve MAGI_MELCHIOR_AI magi-mixedcase)" "MaGi-M resolves to MAGI_MELCHIOR_AI"

# MAGI seats stay inline when not listed, even under a wildcard.
cat > "$VDGG_CONFIG_DIR/formations/magi-wildcard.conf" <<'CONF'
* : sonnet5
CONF
assert_eq "inline" "$(vdgg_formation_resolve MAGI_MELCHIOR_AI magi-wildcard)" "MAGI-M is outside the * wildcard set"
assert_eq "inline" "$(vdgg_formation_resolve MAGI_BALTHASAR_AI magi-wildcard)" "MAGI-B is outside the * wildcard set"
assert_eq "inline" "$(vdgg_formation_resolve MAGI_CASPER_AI magi-wildcard)" "MAGI-C is outside the * wildcard set"

# Every MAGI key is validated during preflight, so an unknown executor on any
# of them is caught before state init writes anything.
printf 'MAGI-B: unknown-magi-executor\n' > "$VDGG_CONFIG_DIR/formations/bad-magi.conf"
set +e
vdgg_formation_preflight bad-magi >/dev/null 2>&1
STATUS=$?
set -e
assert_exit_code 1 "$STATUS" "unknown executor on a MAGI seat is rejected"
