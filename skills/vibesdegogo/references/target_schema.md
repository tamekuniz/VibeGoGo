# VibesDeGoGo! Reference: .vdgg-target Schema

`.vdgg-target` is an optional project-root file. It is a plain `KEY=VALUE` text file that tells Step 8 and Step 9 how to update versions, validate changes, and push work.

It MUST NOT be `source`d. It is a repository-controlled file, so sourcing it (or otherwise evaluating its values as shell) would let an untrusted repository run arbitrary code. Read individual keys instead, e.g. `grep -m1 '^WORKFLOW=' .vdgg-target | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/'`, and validate the value before use. The hooks already parse it this way.

`REVIEW_COMMAND` and `STEP*_EXECUTOR_COMMAND` are executed (via `bash -c` / as the step's command). Treat them as a trust boundary: only use these keys when a human placed the file. Do not use the executable keys from a `.vdgg-target` that shipped inside an untrusted cloned repository; if in doubt, show the value and get confirmation first. To keep the agent from self-authoring these keys to forge a passing review, the PreToolUse hook blocks Edit/Write/Bash writes to `.vdgg-target` (reads stay allowed), the same way it protects the `.claude/.vdgg-*` sidecars.

## Related environment variables

`VDGG_FORMATION` is an environment variable (not a `.vdgg-target` key). When set, it names a Formation from `${VDGG_CONFIG_DIR:-$HOME/.config/vdgg}/formations/<name>.conf` that assigns an AI to every Step. Step 1 reads it and calls `vdgg_state_init --formation "$VDGG_FORMATION"`, which validates the Formation and all referenced executors before creating the state file; the name is persisted in the state file so later `vdgg_formation_resolve <STEP_KEY>` calls do not need to re-pass it. See `SKILL.md` "Step AI Formations" for the full protocol.

When a Formation is selected, the `.vdgg-target` keys `STEP3_EXECUTOR_COMMAND`, `STEP4_EXECUTOR_COMMAND`, and `STEP6_EXECUTOR_TIERS` are ignored — the Formation's per-Step AI assignments are authoritative. When no Formation is selected, those keys apply as historically. Do not mix both mechanisms in the same session.

## Fields

```bash
# Version files. Multiple entries are allowed.
VERSION_FILE_1_PATH=<path from project root>
VERSION_FILE_1_KEY=<key in that file>
VERSION_FILE_2_PATH=...
VERSION_FILE_2_KEY=...

# Human guidance for version generation.
VERSION_FORMAT="<description>"
VERSION_EXAMPLE="<example>"

# Validation/deployment guidance.
DEPLOY_COMMAND="<slash command or manual procedure>"
DEPLOY_TARGET="<device, local app, dev server, etc.>"
VERIFY_TYPE="<device preview, browser check, curl check, etc.>"

# Workflow. Default is branch-pr.
WORKFLOW=branch-pr

# Base branch for PRs. Optional; default is origin default branch, then main.
BASE_BRANCH=main

# Only used when WORKFLOW=trunk.
AUTO_PUSH=false

# Extra test command regex blocked during implementing phase.
TEST_COMMAND_PATTERN="<extended regex>"

# Step 0 Grill Me toggle. Grill Me is an optional question-driven interrogator
# that walks the decision tree one branch at a time and runs before drafting
# Goal / Constraints / Acceptance. See SKILL.md "Step 0 Helper: Grill Me".
#   off  (default) — do not run Grill Me.
#   on             — always run Grill Me at Step 0.
#   auto           — run when the Consultation entry conditions hold
#                    (ambiguous goal, subjective work, high stakes,
#                    multiple defensible directions).
# Treated as off if the Grill Me skill is not installed.
GRILLME=auto

# Chat step reporting (verbose/quiet). quiet omits chat step declarations
# and interim narration; see SKILL.md "Step reporting" for the never-omit list.
STEP_REPORT=verbose

# Entry gate. Normally the hooks are fail-open while no VibesDeGoGo! session
# is armed (no .claude/.vdgg-active), so unrelated repositories are never
# blocked. Setting VDGG_REQUIRED=on opts this repository out of that
# leniency: while unarmed, the PreToolUse hook denies Edit/Write/NotebookEdit,
# unknown tools exposing a file path, and Bash segments that write files
# (redirects to real paths, tee, rm/mv/cp/dd/install/truncate/touch/ln/patch/
# mkfifo, sed/perl -i) or run `git commit` — including writes to .vdgg-target
# itself, so the gate cannot be self-disabled. Read-only tools, builds, and
# the arming command (vdgg_state_init) stay allowed. Without jq the hook
# cannot classify tools, so it fails closed while this key is on.
# Only the literal value `on` activates the gate; absent/off/other values
# keep the historical fail-open behavior. Set this in repositories where
# every code change must go through the VibesDeGoGo! workflow.
VDGG_REQUIRED=off

# Optional external review gate for Step 7. The command must be read-only
# (findings only, no edits) and exit 0 only when the review passes. Run it
# with `vdgg_review_run` (no arguments), which writes the review sentinel on
# success. Use a different vendor than the implementing model when possible.
# For code that ships to other machines or handles user data, include a
# security perspective in the review prompt, since the simplify gate does
# not cover security.
REVIEW_COMMAND="codex exec --sandbox read-only 'review the working tree diff for correctness and security (injection, secrets exposure, unsafe file/network/exec operations, data loss); exit non-zero on blocking findings'"

# Optional delegated step executors. When set, the agent runs the command for
# that step instead of doing the step inline, then validates the artifacts
# (file exists + required headings) before advancing. Placeholders the agent
# substitutes: {TASKS_DIR}, {REQUIREMENTS}, {INVESTIGATION}, {TODO}, {TASK}.
STEP3_EXECUTOR_COMMAND="qwen -p '<investigation prompt from subagent_prompts.md with paths filled in>'"
STEP4_EXECUTOR_COMMAND=""

# Optional Step 6 executor tier ladder for the legacy (no-Formation) path: an
# ordered, |-separated list of executor commands, cheapest first. The literal
# tier "inline" is reserved and means the orchestrating agent implements the
# task itself; when the key is unset, Step 6 always works that way. Other
# entries use the same command/placeholder conventions as
# STEP3_EXECUTOR_COMMAND / STEP4_EXECUTOR_COMMAND above ({TASKS_DIR},
# {REQUIREMENTS}, {INVESTIGATION}, {TODO}, {TASK}). Step 6 delegation requires
# an active task allowlist; out-of-allowlist edits by the executor are caught
# by vdgg_task_gate. Escalation rules live in SKILL.md ("Step 6 Executor
# Tiers (no Formation)"). Ignored when a Formation is selected — use
# STEP_6_AI from the Formation instead.
STEP6_EXECUTOR_TIERS="<local-llm-cli> -p '<implementation prompt>'|<stronger-model-cli> -p '<implementation prompt>'|inline"
```

## Example: iOS Or macOS App

```bash
VERSION_FILE_1_PATH=project.yml
VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION
VERSION_FORMAT="yyyymmdd plus two-letter sequence, starting at AA"
VERSION_EXAMPLE="20260527AA"
DEPLOY_COMMAND="/deploy-device"
DEPLOY_TARGET="physical device"
VERIFY_TYPE="device preview"
AUTO_PUSH=false
```

## Example: Web Backend Without Version Files

```bash
DEPLOY_COMMAND="npm run dev"
DEPLOY_TARGET="dev server"
VERIFY_TYPE="browser check"
AUTO_PUSH=false
```

## Workflow Behavior

`branch-pr` is the default:

1. Step 1 creates a feature branch named from the Step 0 Goal, in `{type}/{slug}` form (e.g., `feat/japanese-readme`). See Step 1 in `SKILL.md`.
2. Step 9 commits there.
3. Step 9 pushes the branch and creates a PR.
4. The agent stops. A human decides whether to merge.

`AUTO_PUSH` is ignored in `branch-pr` because pushing the feature branch is required to create a PR.

`trunk` is opt-in:

1. Work stays on the current branch.
2. Step 9 commits there.
3. Step 9 pushes only when `AUTO_PUSH=true`.
