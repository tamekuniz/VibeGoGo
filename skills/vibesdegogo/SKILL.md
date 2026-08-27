---
name: "VibesDeGoGo!"
description: "A state-and-hook workflow for Claude Code that keeps coding agents moving until done while stopping only before constraint violations."
version: 0.4.0
---

# VibesDeGoGo!

VibesDeGoGo! is a serial, state-file-driven workflow for autonomous coding with Claude Code. It uses a state file plus Claude Code hooks to mechanically enforce the order of work. The agent does the work directly by default, and delegates to subagents only when parallel work is clearly useful.

## When To Use

Use VibesDeGoGo! for coding work: implementation, diagnosis, refactoring, or improvement work where the agent should carry the request through to verification and commit.

Do not use it for wording-only requests, open-ended discussion, or brainstorming where no code or repository workflow should be executed.

Trigger phrases include `/VibesDeGoGo!`, "use VibesDeGoGo!", and similar requests.

## Agent Role

- Declare before acting: output a Step declaration at the beginning of each Step.
- Update the state file: every Step start and completion must update state through `vdgg_state_*` helpers.
- Lead Steps 1, 2, 5, 8, and 9 directly.
- Execute Steps 3, 4, 6, and 7 directly unless delegation is clearly better.
- Delegate only when parallel execution helps or when multiple independent tasks can safely run at the same time.
- Do not delegate merely to save context, because the area is unfamiliar, or because the work may take time.
- Monitor subagents and correct direction if they drift.

### Step reporting

Whenever work is delegated to a subagent or an external executor, output one line in the user-facing text before the delegation:

```text
[VibesDeGoGo! Delegate] step=N, executor=<model or command>, role=<short role>
```

### Delegated step executors

Steps 3, 4, and 6 communicate only through files under `tasks/vdgg/{id}/`, so their executor is swappable through **Step AI Formations** (shared with the Codex edition) — a named, complete Step-to-AI mapping that covers Step 0/3/4/6/6R/7/0-Grill Me from a single config file. See "Step AI Formations" below.

When delegating, output a Delegate line before delegation (see Step reporting), and validate the executor's artifacts yourself before advancing: the output file exists and contains the required headings; for Step 6, the task allowlist and `vdgg_task_gate` still apply, which catches any out-of-allowlist edits the executor made. Steps 1, 2, 5, 8, and 9 are never delegated regardless of mechanism.

### Step AI Formations

A Formation is a named, complete Step-to-AI assignment shared with the Codex edition. Select it before Step 0 with `VDGG_FORMATION=<name>` (environment variable) or an explicit user instruction. Before Step 0 consultation begins, source `vdgg-state.sh`, run `vdgg_formation_preflight <name>`, and resolve `STEP_0_AI` and `STEP_0_GRILL_AI` with that explicit name. Then pass the same name to `vdgg_state_init --formation <name>` in Step 1 (or set `VDGG_FORMATION` before calling `vdgg_state_init`, which reads it automatically). Formation files and executor definitions are trusted user configuration outside the repository, shared with the Codex edition:

```text
${VDGG_CONFIG_DIR:-$HOME/.config/vdgg}/
  formations/<name>.conf
  executors/<ai>.conf
```

Write one line per step, in order, so the whole lineup is visible at a glance:

```text
0: primary
0G: primary
1: primary
2: primary
3: sonnet5
4: sonnet5
5: primary
6: sonnet5
6R: fable5
7: fable5
8: primary
9: primary
--
Everything below the separator is a free-form memo and is never read.
```

Syntax, one line per seat: `<seat>: <ai> [model] [effort]`.

- Seats: `0`, `0G`, `1`, `2`, `3`, `4`, `5`, `6`, `6R`, `7`, `8`, `9` (case-insensitive; `grill` is still accepted as a synonym of `0G`), plus `MAGI-M`, `MAGI-B`, `MAGI-C` for the three MAGI council seats (MELCHIOR / BALTHASAR / CASPER; case-insensitive), plus `*` which assigns `3, 4, 6, 6R, 7` at once — an explicit seat line wins over `*`. Every step can name the AI that runs it. Unlisted seats fall back to `primary`. The MAGI seats are outside the `*` wildcard set; they must be listed explicitly to delegate, otherwise MAGI runs those seats inline.
- Values: `primary` — the model this session is already running on, i.e. no delegation (`inline` is accepted as a synonym). The model shorthands `opus5`, `sonnet5`, `fable5`, `haiku45`, which expand to the bundled `claude` wrapper plus the full model id. The builtins `claude` / `codex`, which run the bundled `scripts/vdgg-exec-claude.sh` / `vdgg-exec-codex.sh` wrappers with optional model and effort tokens — effort is recognized by a closed vocabulary (claude: `low|medium|high`, codex: `minimal|low|medium|high|xhigh`), any other token is the model. Or a bare executor name resolved through `executors/<name>.conf` containing one `COMMAND=/absolute/path/to/executable` line; bare names and model shorthands take no extra tokens — bake fixed settings into that command.
- A lone `--` line ends the configuration. Everything below it is a memo: no comment marker is needed and nothing there is parsed, so it cannot break the file.
- The parser never sources these files and the command is executed directly, not through a shell string. Tokens must start with an alphanumeric so they can never reach an executor's argv as a flag.

When a Formation is selected, resolve the assigned AI before acting in every Step with `vdgg_formation_resolve <STEP_KEY>`. Use `STEP_6R_AI` for reflection and `STEP_0_GRILL_AI` for Grill Me. Then:

1. `inline`: work normally in the current agent.
2. External AI: write the smallest sufficient input artifact under `tasks/vdgg/{id}/`, output the Delegate line, and call `vdgg_executor_run <STEP_KEY> <input-file> [output-file]`.
3. Validate the expected artifact before advancing. A non-zero executor result, missing output, unknown AI, or invalid Formation stops the workflow with state unchanged. Never silently fall back to `inline`.

The executor receives `VDGG_EXECUTOR_FORMATION`, `VDGG_EXECUTOR_AI`, `VDGG_EXECUTOR_STEP`, `VDGG_EXECUTOR_INPUT`, and `VDGG_EXECUTOR_OUTPUT`. State transitions, task allowlists, review gates, and commit permissions remain owned by the controlling VDGG session — Claude Code hooks continue to enforce them.

Naming an AI on a seat assigns the *work product* of that step, never the mechanics: state transitions, task allowlists, review gates, and commit permissions stay with the controlling VDGG session at every step, and the Claude Code hooks continue to enforce them. So an AI named on Step 1, 2, 5, 8, or 9 drafts or decides the artifact for that step — the branch name, `requirements.md`, the next task and its allowlist, the progress update, the commit message — while this session performs the state write, the gate arming, and the git operation. Seats `0` and `0G` are conversational, so a bundled one-shot wrapper there answers in a single pass instead of holding a dialogue; use a bare executor that can own the conversation when that matters.

The `MAGI-M` / `MAGI-B` / `MAGI-C` seats are not VDGG steps — they name executors for the three MAGI council members (MELCHIOR / BALTHASAR / CASPER) when the MAGI skill (`zmagi`, formerly `magi`) runs as a Step 0 consultation escalation or a Step 7 subjective-artifact review gate. The MAGI skill resolves each seat via `vdgg_formation_resolve MAGI_MELCHIOR_AI` (and the B / C variants). Seats left unlisted (or set to `primary`/`inline`) run inline in the host — MAGI's own default — so existing formation files that predate MAGI seats keep working unchanged. Committee independence increases when at least MELCHIOR runs on a different vendor than the host; see the MAGI skill's Formation section for the honesty covenant that governs external-executor failures.

### Local llama-server executors

When a Formation assigns a Step to an executor backed by a locally-hosted `llama-server` (llama.cpp), VDGG ships two helpers so the server configuration lives in one declarative file instead of being scattered across `~/.zshrc`, launchd plists, and executor wrapper scripts:

- [`references/servers-conf.md`](references/servers-conf.md) — schema and CLI contract for `${VDGG_CONFIG_DIR:-$HOME/.config/vdgg}/servers.conf` (source of truth).
- [`references/servers.conf.example`](references/servers.conf.example) — a copy-and-edit fixture.
- [`scripts/vdgg-llm-start.sh`](scripts/vdgg-llm-start.sh) — a thin wrapper: `--check`, `--dry-run <id>`, `<id>` (exec).
- [`references/local-inference-setup.md`](references/local-inference-setup.md) — first-run walkthrough for macOS launchd (tested) and Linux systemd (schema-compatible, awaiting community verification).

Executor `COMMAND=` lines can then call `vdgg-llm-start <id>` through a wrapper that sends the actual request to `http://127.0.0.1:<port>`. Only the port/api key move; the executor script itself no longer hard-codes them.

## Standard-First Contract

For code changes, Step 0 Constraints must include the following default policy unless the user explicitly overrides it:

- Prefer the target environment's standard features, components, APIs, and patterns.
- Do not add custom UI, custom components, custom state management, custom design systems, custom utilities, or external dependencies unless the need is clear.
- If the standard path is not enough, stop before implementation and report why, alternatives, impact, and whether the work can later return to the standard path.
- Do not silently solve the problem by adding custom implementation or dependencies.

If existing custom implementation is found, record in `investigation.md` whether it could be replaced with standard facilities and why it is or is not being replaced.

## Self-Maintenance Mode

Use this mode only when changing VibesDeGoGo! itself under `skills/vibesdegogo/`.

Rules:

- Fix the target files, purpose, and out-of-scope areas before editing.
- Read only files directly related to the change. Do not re-investigate the whole project.
- Use `rg` and targeted reads. Do not start broad researcher subagents.
- Keep the plan to at most 3 tasks.
- Preserve existing script, hook, and documentation structure.
- Do not add external dependencies.
- Escalate to full flow if hook I/O contracts, state file format, or Step transition contracts change.
- Verify with `bash -n`, `rg` sanity checks, and minimal hook simulation when needed.
- Skip Step 8 deployment.
- Stop only before constraint violations, destructive operations, or external dependency changes.

## Lightweight Mode

Lightweight mode is for small, closed changes in ordinary projects. It shortens ceremony, not discipline.

Use it only when all of these are true:

- The user explicitly asks for lightweight mode, or the agent briefly states why lightweight mode applies before starting.
- Target files, purpose, out-of-scope areas, and verification method are clear at the start.
- Existing standard patterns are enough.
- No dependency or custom implementation is needed.
- The change is small and the direct references/callers can be checked in a limited scope.

Do not use lightweight mode for API contracts, database or migration changes, persistence formats, auth, permissions, security, billing, analytics event names, user data deletion or migration, legal text, high-risk medical or financial text, compatibility decisions, state transition design, dependency additions, broad renames, or cross-module changes.

Minimum flow:

1. Declare target files, purpose, out-of-scope areas, and verification method in 1 to 5 lines.
2. Use `rg` and targeted reads to inspect the change site and direct references.
3. Make the smallest change that follows existing patterns.
4. Run the declared verification. Do not skip verification.
5. If the change will be built, deployed, or committed and `.vdgg-target` configures version files (`VERSION_FILE_*_PATH` / `_KEY`), bump each configured key to a value newer than `HEAD` before building/deploying. This is the only Step 8 obligation lightweight mode keeps; do not skip it just because the rest of Step 8 is omitted.
6. Report only changes, verification result, and residual risk.

Escalate to full flow if tests fail twice, scope expands, specification or compatibility judgment is needed, custom implementation looks necessary, verification is unclear, or the agent is about to proceed on a guess.

## State Layout

Each VibesDeGoGo! session has a unique ID in this format: `YYYYMMDD-HHMM-xxxx`.

```text
.claude/.vdgg-active              current VibesDeGoGo! ID
.claude/.vdgg-state-{id}          state file for that ID
tasks/vdgg/{id}/requirements.md   fixed Goal / Constraints / Acceptance criteria
tasks/vdgg/{id}/investigation.md  Step 3 investigation report
tasks/vdgg/{id}/todo.md           task list
tasks/vdgg/{id}/progress.md       progress and retry notes
```

State files are KEY=VALUE text files with these fields: `step`, `phase`, `loop_count`, `current_task`, `vdgg_id`, and `last_updated`.

See `references/state_helpers.md` for helper details.

## Phases

| phase | Step | Meaning |
|---|---:|---|
| `declare` | 1 | formation declaration |
| `requirements` | 2 | write requirements |
| `investigating` | 3 | deep investigation |
| `planning` | 4 | create plan and task files |
| `task-selected` | 5 | choose one task |
| `implementing` | 6 | implement and write tests |
| `testing` | 7 | verify and run review gate |
| `reflection` | 6-R | investigate failure and prepare one retry |
| `verified` | 7 end | verification complete |
| `progress` | 8 | update progress and request validation |
| `commit` | 9 | commit and optionally push/PR |

## Step Declaration Format

Step 1 uses the formation declaration:

```text
[VibesDeGoGo! Declaration] id=<vdgg_get_id output>
```

Steps 2 and later use this one-line format:

```text
[VibesDeGoGo! Step N Start] step=N, phase=PHASE_NAME, loop=LOOP_COUNT
```

Declarations are a reporting convention for the user and the transcript; the hooks no longer validate them. State-transition legality is enforced by the `vdgg_state_*` helpers themselves.

## Step 0: Agree On Requirements

Before starting the state machine, agree with the user on:

1. Goal: what state or user value should be achieved.
2. Constraints: what must not change and what boundaries apply.
3. Acceptance criteria: concrete checks that determine completion.

Draft these three items in chat. Ask questions only for ambiguity that cannot be safely resolved. Start Step 1 only after the user clearly accepts the draft.

Step 0 is not mechanically enforced because no state file exists yet.

## Step 0 Mode: Consultation (壁打ち)

When the requirements cannot yet be safely fixed, run Step 0 as a consultation (壁打ち) before drafting Goal / Constraints / Acceptance. Enter this mode when any of these hold: the goal is ambiguous; the work is subjective or creative — docs, naming, copy, design, a handbook, anything an AI can produce where "good" lives in the user's head, not only in code; the change is high-stakes or hard to reverse (public artifacts, contracts); or more than one defensible direction exists. For a clear, mechanical task with one obvious shape, skip this mode and draft the three items directly.

Consultation is a sounding board. It is none of its three failure modes:

- **Not guess-and-go:** do not silently pick one reading and start building.
- **Not option-dumping:** do not hand over a bare list ("A, B, or C?") and make the user do the thinking.
- **Not autonomous-finalize:** do not settle a subjective or scope question for the user behind a closed door.

Loop until the WHAT is agreed:

1. Name the decisions the result actually hinges on — real forks, not pseudo-choices. Raise a few at a time; do not flood.
2. For each, lay out the trade-offs (what each option wins and loses) and give a recommendation with its reasoning. Recommend; do not merely survey.
3. The user decides or redirects. On every subjective or scope question the user is the decider; the agent supplies the thinking, not the verdict.
4. For a genuinely split, high-stakes fork, escalate that one point to a deeper, multi-perspective deliberation: run the MAGI skill (`zmagi`, formerly `magi`) if it is installed; if not, get a second opinion another way (a different model, or a structured review). Bring the output back as material — still for the user to decide.

Do not relitigate a settled point, and do not stall: drive toward convergence. When the WHAT is agreed, leave consultation mode and write `requirements.md`. For subjective artifacts, record in Acceptance what "good" was agreed to mean, so completion stays checkable. Then proceed to Step 1.

## Step 0 Helper: Grill Me (optional)

The Consultation loop above is the baseline for resolving ambiguity. Grill Me is an optional third part — a question-driven interrogator that walks the decision tree one branch at a time — that can be slotted in **before** drafting Goal / Constraints / Acceptance, to pre-filter ambiguity through structured waves of questions, each with a recommended answer.

When Grill Me is engaged, Step 0 runs in three layers before drafting:

1. **Shallow consultation** — the baseline loop above raises real forks and gives recommendations.
2. **Grill Me pass** — sequential question waves drive the user through unresolved branches, each question carrying a recommended answer; the user accepts, redirects, or rejects per question.
3. **MAGI escalation** — for any remaining genuinely split, high-stakes fork, step 4 of the Consultation loop still applies (run MAGI if installed, else get a second opinion another way).

Then drafting `requirements.md` proceeds as usual.

Grill Me is a pre-filter, not a replacement for MAGI. Skipping Grill Me is safe because MAGI remains the deeper-deliberation backstop for high-stakes forks.

Control via `.vdgg-target` (`references/target_schema.md`):

- `GRILLME=off` (default): do not run Grill Me. Behavior is unchanged from the Consultation loop and MAGI escalation alone.
- `GRILLME=on`: always run Grill Me at Step 0 before drafting, even for clear-shape tasks.
- `GRILLME=auto`: run Grill Me when any of the Consultation entry conditions hold — the goal is ambiguous; the work is subjective or creative; the change is high-stakes; or more than one defensible direction exists. Same trigger list as Consultation itself, so they fire together.

If the Grill Me skill is not installed, the setting is treated as `off` and Step 0 continues with Consultation. The orchestrating agent invokes the installed Grill Me skill directly; there is no shell helper for this (the same convention as MAGI escalation).

If a selected Formation assigns `STEP_0_GRILL_AI` to an external AI, that executor owns the complete Grill Me conversation. Its command must keep the transcript out of stdout/stderr and write only the final handoff file. `vdgg_executor_run STEP_0_GRILL_AI <input> <output>` accepts that handoff only when its level-2 headings are exactly, in order: `Goal`, `Constraints`, `Acceptance criteria`, `Decisions`, and `Unresolved questions` (`vdgg_grill_validate_output` enforces this). The HQ consumes that file, not the conversation transcript. If the executor cannot own the interaction on the current surface, stop and report the limitation; do not relay every turn through HQ and call it equivalent.

## Step 1: Formation Declaration

Initialize state. Source the state helpers in every Bash command that calls `vdgg_*` functions (shells do not persist between commands). For manual installs the helpers live at `$HOME/.claude/skills/vibesdegogo`; for plugin installs use this skill's base directory as announced when the skill loads:

```bash
VDGG_SKILL_DIR="${VDGG_SKILL_DIR:-$HOME/.claude/skills/vibesdegogo}"
# Plugin install: replace the default above with this skill's announced base directory.
source "$VDGG_SKILL_DIR/scripts/vdgg-state.sh"
if [ -n "${VDGG_FORMATION:-}" ]; then
    vdgg_state_init --formation "$VDGG_FORMATION"
else
    vdgg_state_init
fi
```

`vdgg_state_init --formation <name>` validates the Formation file and every referenced executor before creating the state file; a failure leaves no session armed. The Formation name is persisted in the state file (`formation=` field) so subsequent Bash commands can call `vdgg_formation_resolve` without re-passing the name. See "Step AI Formations" above for the config directory and file format.

For the default `branch-pr` workflow, create a feature branch after `vdgg_state_init` and before any code editing. The branch name MUST describe the change, not the workflow.

Branch name is derived from the Step 0 Goal, not from the VibesDeGoGo! id. Pick a name in the form `{type}/{slug}` where:

- `{type}` is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore` (same vocabulary as the Step 9 commit type).
- `{slug}` is a short kebab-case summary of the change (3-5 words, lowercase, ASCII, hyphen-separated). Drop articles and filler.
- Examples: `feat/japanese-readme`, `fix/init-portability`, `refactor/state-helpers`.

```bash
WORKFLOW=branch-pr; BASE_BRANCH=""
# Never `source` .vdgg-target: it is a repository-controlled file, and sourcing
# it would execute any code an untrusted repo places there (e.g. WORKFLOW=x with
# a trailing `$(...)`). Read only the needed keys and validate them.
if [ -f "$(pwd)/.vdgg-target" ]; then
    WORKFLOW=$(grep -m1 '^WORKFLOW=' "$(pwd)/.vdgg-target" | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/')
    BASE_BRANCH=$(grep -m1 '^BASE_BRANCH=' "$(pwd)/.vdgg-target" | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/')
    case "$WORKFLOW" in trunk|branch-pr) ;; *) WORKFLOW=branch-pr ;; esac
    # Reject anything that is not a plausible branch name.
    case "$BASE_BRANCH" in ''|*[!A-Za-z0-9._/-]*) BASE_BRANCH="" ;; esac
fi
WORKFLOW=${WORKFLOW:-branch-pr}
if [ "${WORKFLOW:-branch-pr}" != "trunk" ]; then
    if [ -z "${BASE_BRANCH:-}" ]; then
        BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
        BASE_BRANCH=${BASE_BRANCH:-main}
    fi
    CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    # Stay on the current branch if it's already a non-base feature branch
    # (e.g. continuing or bundling another task onto the same branch).
    if [ "$CUR" = "$BASE_BRANCH" ]; then
        # On base branch -> create a new feature branch. The agent MUST pick
        # the {type}/{slug} name from the Step 0 Goal; this snippet does not
        # auto-generate one. Do NOT use `vibesdegogo/` as a prefix — that
        # names the workflow, not the change, and is useless to anyone
        # reading the PR list.
        echo "vdgg: on base branch ($BASE_BRANCH). Run:" >&2
        echo "  git checkout -b <type>/<kebab-slug-derived-from-Step-0-Goal>" >&2
        echo "Types: feat | fix | refactor | docs | test | chore" >&2
    fi
fi
```

If the current branch is already a feature branch, stay on it when this session continues or bundles work onto that change; create a new nested `{type}/{slug}` branch only when the session starts a genuinely separate change. The Step 1 block runs once per session because `vdgg_state_init` refuses a second initialization.

Then output the Step 1 declaration from `references/output_formats.md`.

## Step 2: Write Requirements

Write Step 0's agreed content to `tasks/vdgg/{id}/requirements.md` with exactly these headings:

```markdown
## Goal
...

## Constraints
...

## Acceptance criteria
...
```

Then advance:

```bash
# [VibesDeGoGo! Step 2 Start] step=2, phase=requirements, loop=0
vdgg_state_advance 2 requirements
```

The hook blocks Step 3 until `requirements.md` exists.

## Step 3: Deep Investigation

Investigate existing code related to the requirements and write `tasks/vdgg/{id}/investigation.md`.

Investigation rules:

- Do not guess. Read actual code.
- Do not stop at a single file. Trace callers and impact.
- Consider recent git history and project notes when relevant.
- Read lessons from recent sessions and record the applicable ones in `investigation.md` under a `## 8. Lessons applied` heading (write `none applicable` when nothing fits):

  ```bash
  for f in $(find tasks/vdgg -name lessons.md -exec ls -t {} + 2>/dev/null | head -20); do echo "--- $f ---"; cat "$f"; done
  ```
- Mark unknowns explicitly.

Then advance:

```bash
# [VibesDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0
vdgg_state_advance 3 investigating
```

Use subagents only when parallel investigation clearly helps.

When a Formation is selected and `vdgg_formation_resolve STEP_3_AI` returns a non-`inline` AI, output the Delegate line, write the investigation prompt (see `references/subagent_prompts.md`) with filled-in paths as the input artifact, and call `vdgg_executor_run STEP_3_AI <input-file> tasks/vdgg/{id}/investigation.md`. Validate the required headings on the output before advancing.

## Step 4: Planning

Use `investigation.md` to create `tasks/vdgg/{id}/todo.md` and `tasks/vdgg/{id}/progress.md`.

Task sizing:

- One or two methods and one to three files: keep as one task.
- Four or more files, or independent changes: split tasks.
- Ask whether one implementation cycle can reasonably finish it.

Then advance:

```bash
# [VibesDeGoGo! Step 4 Start] step=4, phase=planning, loop=0
vdgg_state_advance 4 planning
```

When a Formation is selected and `vdgg_formation_resolve STEP_4_AI` returns a non-`inline` AI, output the Delegate line, write the planning prompt with filled-in paths as the input artifact, and call `vdgg_executor_run STEP_4_AI <input-file> tasks/vdgg/{id}/todo.md`. Validate the output before advancing (both `todo.md` and `progress.md` must exist).

## Step 5: Select One Task

Choose one task from `todo.md` — or, during a followup sweep, the next pending `TF` task from the queue in `progress.md`. The task must be small enough to complete implementation, tests, and verification in one Step 6 to Step 8 loop; split it before Step 6 if it is not. Declare an allowlist of every implementation/test/documentation file this task is allowed to change; keep it narrow and task-specific. Task notes under `tasks/vdgg/{id}/` never need allowlisting. If the task changes an interface, enum, type, or signature, also include the test file(s) that assert it in the allowlist, so a needed test update does not hit the re-arm wall mid-task.

```bash
# [VibesDeGoGo! Step 5 Start] step=5, phase=task-selected, loop=0
vdgg_state_advance 5 task-selected
vdgg_task_begin "T1: title" path/to/file1 path/to/file2
```

`vdgg_task_begin` records the task in state, snapshots a baseline of the allowlisted files, and arms the task gate. The hook blocks implementation edits until it has run.

## Step 6: Implement

Implement the selected task and write tests where appropriate.

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0
vdgg_state_advance 6 implementing
```

Do not run tests in `implementing`; the hook blocks test commands until Step 7. Edit/Write outside the task allowlist is blocked. `vdgg_task_begin` can only (re)arm at Step 5 — the state machine rejects it from `implementing`/`reflection` (6 -> 5 is not a legal transition). If the scope legitimately grew mid-task, either narrow the change to fit the current allowlist, or finish this task through Step 8 and select the extra scope as a new task at Step 5 (8 -> 5) with the right allowlist.

When a Formation is selected and `vdgg_formation_resolve STEP_6_AI` returns a non-`inline` AI, output the Delegate line, write the implementation prompt (see `references/subagent_prompts.md`) with filled-in paths and the current task's allowlist as the input artifact, and call `vdgg_executor_run STEP_6_AI <input-file>`. The executor edits files in the working tree; the task allowlist and `vdgg_task_gate` still apply, so out-of-allowlist edits are caught at Step 7. When no Formation is selected, Step 6 runs inline.

## Step 7: Verify

Before running verification, state the concrete checks you will run. Scale the count to the change's surface — roughly 1 to 3 for a small, localized change, more when it spans multiple files or touches a contract; do not stop at three if the surface is larger. At least one check must be one that would FAIL if the change were wrong — a boundary, error, or regression case, not only a happy-path confirmation. Then run them through the task gate, which re-checks the allowlist and records a pass only when the command succeeds. Pass the command as separate shell words, for example `vdgg_task_gate npm test`, or use `vdgg_task_gate bash -lc 'set -o pipefail; command with pipes'`.

A verification command with a pipe that omits `set -o pipefail` can hide a failure in an earlier pipeline stage behind a successful final stage, so the gate records a false pass.

```bash
# [VibesDeGoGo! Step 7 Start] step=7, phase=testing, loop=0
vdgg_state_advance 7 testing
vdgg_task_gate <verification-command> [args...]
```

After all checks pass, run the `simplify` skill as a quality gate. The PostToolUse hook records a sentinel file:

```text
.claude/.vdgg-simplify-sentinel-{vdgg_id}-{loop_count}
```

Outcomes:

- Sentinel missing: `vdgg_state_advance 7 verified` is blocked.
- `modified=0`: verified transition is allowed.
- `modified=1`: verified transition is blocked; go through reflection and re-test.

When a task allowlist is active, `vdgg_state_advance 7 verified` is also blocked until `vdgg_task_gate` has passed for the current loop. If verification fails and the work must be redone from the baseline, `vdgg_task_rollback` reverts the allowlisted changes.

For environments that cannot use the `simplify` skill, or when `.vdgg-target` configures an external reviewer, run the review through `vdgg_review_run`:

```bash
vdgg_review_run                      # runs REVIEW_COMMAND from .vdgg-target
vdgg_review_run <command> [args...]  # runs an explicit review command
```

When a Formation is selected and `vdgg_formation_resolve STEP_7_AI` returns a non-`inline` AI, output the Delegate line, write the review prompt with the working-tree diff and verification results as the input artifact, and call `vdgg_review_run vdgg_executor_run STEP_7_AI <input-file> <findings-output>` so the gate is recorded only when the executor succeeds. The sentinel records that the review ran, not that it passed, so apply the severity-based response below before advancing. The Formation review is read-only (findings only, no edits). When no Formation is selected, use `simplify` or `vdgg_review_run` as above.

It writes the review sentinel only when the command exits 0, and it is the documented way to write one: recording the gate means running a command that succeeds, rather than calling a bare marker. The verified gate accepts either sentinel — simplify or explicit review — and both are subject to the same rule: implementation edits after the review flip `modified=1` and route through reflection. Prefer the simplify skill when it is available; prefer a different vendor than the implementing model for external review. For code that ships to other machines or handles user data, the review prompt must include a security perspective (injection, secrets exposure, unsafe file/network/exec operations) — simplify does not cover security. Sentinel files cannot be written directly; the hooks block Edit/Write/Bash writes to `.claude/.vdgg-*` paths.

For a **subjective artifact** (docs, copy, naming, design — where quality is a judgment, not something a test can decide), the review gate can be the `MAGI` skill (installed as `zmagi`, formerly `magi`) when it is present: run MAGI as the review, write its verdict line to `tasks/vdgg/{id}/magi-verdict.md`, and record the gate with `vdgg_review_run grep -q '^MAGI判定: 可決' tasks/vdgg/{id}/magi-verdict.md`, so a deliberation recorded as 未達 cannot open it. The verdict file is written by the agent, so this checks the record, not the deliberation itself. If MAGI is not installed, skip it and use the standard `simplify`/review gate above. MAGI judges desirability, not code correctness — correctness still rides on tests and `simplify`.

### Multi-perspective review is mandatory (Layer 2)

Single-pass external Step 7 review is prohibited. The reviewer must inspect the diff through **N ≥ 3 independent perspectives** ("lenses"), and the merged review output must carry `lens_count` at the top level so `vdgg_review_run` can verify the requirement was met (a lens_count below 3 is rejected by the Layer 2 validator that `vdgg_review_run` invokes after Layer 1). This is the default; there is no per-task opt-in.

- Default lens set is `correctness`, `security`, `contract`, `simplification`, `altitude`. Small diffs (< 200 LOC, 1–2 files) may drop to any 3 of those. Large or contract-touching diffs (> 500 LOC, or auth/persistence/concurrency) must use 5.
- The `simplify` skill's built-in Phase 1 already runs 4–5 parallel angle finders, so a simplify sentinel automatically carries `lens_count=4` (see the PostToolUse hook that writes the sentinel). No extra work needed when the reviewer is `simplify`.
- For Formation Step 7 executor delegation, the HQ (this session) is responsible for invoking the executor `N` times with per-lens prompts and merging the results into one schema-conformant JSON. Set the merged output's top-level `lens_count` to `N`. A single 1-shot call to an external reviewer, even a capable one, is NOT enough — collapse to one call and the drift risk (a single model taking a shortcut) returns to the failure mode this layer exists to prevent.
- When merging N single-lens outputs, dedup findings by `(file, line, summary)` if the same defect surfaces across lenses; keep the highest severity when they disagree.

### Adversarial countersign for clean reviews (Layer 3)

Multi-perspective review (Layer 2) protects against a single reviewer taking a shortcut, but N lenses of *the same reviewer* still share a blind spot: the reviewer's model, its training cutoff, its habit of trusting patterns it has seen before. When the primary review comes back with no `high` or `medium` finding, that "clean" verdict is the moment to worry — real problems can survive same-reviewer redundancy and only surface under a genuinely different eye.

Layer 3 runs an **adversarial countersign** on any clean primary review: a second reviewer, ideally from a different vendor or model family, re-reviews the same diff with the mandate "find what the primary missed." Only when the countersign also comes back clean is the sentinel flipped from `countersign=none` to `countersign=clean`. If the countersign surfaces any `high` or `medium` finding the primary missed, `vdgg_review_countersign` returns a failure that the caller must treat as a failed review — go to reflection (Step 6-R) rather than advancing.

Pipeline enforcement — this is not a discipline norm the caller can forget. `vdgg_review_run` marks the sentinel with `countersign_required=1` whenever the primary review returns no `high`/`medium` finding. The PreToolUse hook then calls `_vdgg_review_gate_ready` before opening the verified gate and refuses to advance while `countersign_required=1 && countersign != clean`. Skipping `vdgg_review_countersign` on a clean primary is therefore a hard block, not a warning. `vdgg_review_run` called without `--review-output` (the legacy backward-compat path) also sets `countersign_required=1`, so the pre-Layer-1 shortcut of "just run any command that exits 0" no longer opens the gate — migrate to `--review-output` or run `vdgg_review_countersign` explicitly. The private writer `_vdgg_write_review_sentinel` also refuses direct calls that lack the one-shot `_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1` breadcrumb, so accidental "just call the helper" shortcuts are refused; only `vdgg_review_run` and `vdgg_review_countersign` set the breadcrumb.

- Trigger condition: primary review's findings are empty OR every finding is `low`. A primary with any `high`/`medium` already flagged real problems; a countersign there adds nothing except cost, so the helper no-ops with success and the sentinel is marked `countersign_required=0`.
- Reviewer selection: the countersign should come from a different vendor or model family than the primary whenever the Formation makes that possible. A same-family countersign satisfies the mechanism but weakens the guarantee — record when this happens in `progress.md` so future rounds know to escalate.
- Simplify path exemption: the `simplify` skill's built-in Phase 1 already fans out across 4–5 angle finders (see Layer 2), and its findings are consumed inline rather than via `vdgg_review_run --review-output`. Simplify sentinels therefore skip Layer 3; the multi-agent phase is doing the diverse-reviewer work in-band.
- The countersign output must satisfy Layer 1 (schema) and Layer 2 (`lens_count ≥ 3`) on its own — a countersign that returns prose or a single-lens JSON is a failed countersign, not a passed one.

### Review prompts must request concrete fixes, not only findings

Every review prompt — simplify angle-finder agents, Formation Step 7 executor calls, external `vdgg_review_run` reviewers, and MAGI verdicts on subjective artifacts — MUST require the reviewer to include the concrete fix for each finding alongside the problem statement. Findings without a proposed fix push the implementer back into guessing what the reviewer meant, which is the shape past regressions have taken. This is the default; there is no per-task opt-in.

When writing the prompt, require each finding to carry:

- `file`, `line` — where the problem is.
- `severity` — `high` / `medium` / `low` (mandatory; see the severity-based response section below).
- `summary` — one sentence stating the problem.
- `fix` — a concrete code snippet, unified diff, or step-by-step instruction that resolves it. "Consider X" / "may want to Y" is not acceptable — the reviewer must commit to a specific change. If the reviewer genuinely cannot propose a fix, write `fix: unknown, needs investigation` so the implementer treats it as a research task instead of a guess.
- `cost` — reviewer's estimate of implementation effort (low / medium / high), used by the implementer to plan the fix batch.

The implementer still owns the final decision (accept, skip, or defer to `followup.md`); the reviewer's job is to make that decision cheap by handing over a fix the implementer can adopt, adapt, or reject on concrete grounds.

### simplify subagent consolidation

The simplify skill's default Phase 1 (5 parallel angle finders, up to 8 candidates each) is the right call when ANY of these hold:

- This is the FIRST simplify round (`loop_count=0`) on this feature.
- The diff is large (>500 LOC), spans multiple files/layers, or touches contracts (API, persistence, concurrency, auth, security).
- An unresolved high or medium finding from the previous round still applies to code being changed in this round (recall still matters there).

You MAY collapse the 5 angles into ONE comprehensive agent (or do the review inline without a subagent) when ALL of these hold:

- This is a follow-up round (`loop_count` ≥ 1).
- No unresolved high or medium finding from the previous round still applies to code being changed in this round.
- The diff in this round is small (≤200 LOC) AND localized (1–2 files, 1–2 functions).
- No concurrency, pasteboard, pointer, lifecycle, or contract surface is touched.

When collapsing, state the reason in the user-facing text (e.g. "collapsing to 1 agent because loop=3 and no unresolved high/medium finding touches this round's diff"). Do not collapse silently to save tokens or time.

### simplify findings: severity-based response

After simplify returns findings, classify each one and decide before editing:

- **high**: correctness bug, data loss, race condition, security, contract regression.
- **medium**: real bug with a narrow trigger, or a design that will break under reasonable use.
- **low**: cosmetic, stale doc, log message wording, naming, dead branch, style.

Response:

- Any **high or medium** finding → fix it in implementation files. The sentinel will flip to `modified=1`, routing you through reflection — this is correct.
- **All findings are low (or `[]`)** → DO NOT edit implementation files. Append the findings to `tasks/vdgg/{id}/followup.md` — or, inside a `TF` followup task, to `followup-final.md` — and advance directly to `verified`. Low items are collected by the Step 8 followup sweep.

This stops convergence-loops on cosmetic findings while keeping the hook discipline intact: any implementation edit during testing still flips `modified=1`, so there is no escape hatch for high/medium.

When listing findings, always assign an explicit `severity` field per finding so the classification is auditable. If simplify's own output omits severity, classify each finding yourself before deciding the response.

After successful verification and simplify review:

```bash
# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0
vdgg_state_advance 7 verified
```

If testing fails, or simplify changed code, go to reflection:

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=reflection, loop=<same loop>
vdgg_state_advance 6 reflection
```

## Step 6-R: Reflection

Reflection is mandatory after failed verification or simplify changes.

At the beginning of reflection, start a researcher subagent for root-cause investigation unless self-maintenance mode explicitly allows skipping it for a mechanical typo/path issue. When a Formation is selected and `vdgg_formation_resolve STEP_6R_AI` returns a non-`inline` AI, delegate this reflection pass to that executor via `vdgg_executor_run STEP_6R_AI <input-file> tasks/vdgg/{id}/investigation-r{loop_count}.md`.

Lightweight branch: when reflection was triggered by review/simplify findings rather than a test failure, skip the researcher subagent — write `investigation-r{loop_count}.md` directly from the review findings (classify each finding, then state the one fix) instead. A test-failure-triggered reflection still requires the researcher subagent as above. Either way, `investigation-r{loop_count}.md` and `progress.md` must still be written; the hook checks apply the same regardless of which path produced them.

The researcher (or, on the lightweight branch, the agent itself) must write:

```text
tasks/vdgg/{id}/investigation-r{loop_count}.md
```

Then append four items to `progress.md`:

1. Root Cause Investigation.
2. Pattern Analysis.
3. Hypothesis: exactly one hypothesis.
4. Implementation plan: exactly one fix.

Forbidden in reflection:

- skipping root-cause investigation,
- trying multiple fixes at once,
- patching symptoms without understanding cause,
- going directly to `verified`,
- editing implementation files.

Return to implementation with loop increment:

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=<next loop>
vdgg_state_loop 6 implementing
```

The hook checks that `progress.md` and `investigation-r{loop_count}.md` were updated during reflection.

Right after returning to `implementing`, distill any reusable lesson from this reflection into `tasks/vdgg/{id}/lessons.md` — one entry per lesson: symptom → wrong assumption → correct move. Before writing, re-run the Step 3 lessons command and skip duplicates; write nothing when the failure was one-off (lessons are deliberately failure-derived — clean-pass insights are out of scope). After writing an entry, output one line in the user-facing text so the user can veto it on the spot, while the phase still allows deleting the entry:

```text
[VibesDeGoGo! Lesson] <one-line summary>
```

(The reflection phase itself cannot write this file; the hook allows only `progress.md` and `investigation-r*.md` there.)

If the revised hypothesis needs files outside the current allowlist, do not try to widen the allowlist in place — `vdgg_task_begin` cannot re-arm outside Step 5 and will fail loudly. Adapt the fix to the current allowlist (e.g. downgrade an optional cleanup to a followup note), or complete/close this task and take the wider scope as a new task via Step 8 -> Step 5. The task gate must pass again for the new loop before `verified`.

## Step 8: Progress And Validation Request

Advance:

```bash
# [VibesDeGoGo! Step 8 Start] step=8, phase=progress, loop=0
vdgg_state_advance 8 progress
```

Read `.vdgg-target` if it exists. If version files are configured, update their configured keys and make the new value newer than `HEAD`.

Ask the user for validation according to `DEPLOY_COMMAND`, `DEPLOY_TARGET`, and `VERIFY_TYPE`. If no target is configured, ask how they want to validate.

Update `progress.md` and check whether all tasks are complete:

- unfinished tasks: go back to Step 5,
- all planned tasks complete: run the followup sweep below, then continue to Step 9.

### Followup sweep (low findings)

On the FIRST Step 8 entry after all planned tasks are complete, build the sweep queue exactly once: read `tasks/vdgg/{id}/followup.md`; if it is empty or absent, continue to Step 9. Otherwise group its items into followup tasks using the Step 4 task-sizing rules, name them with a `TF` prefix (`TF1: ...`, `TF2: ...`), and record the queue in `progress.md` with a status per task (pending / fixed / residue).

Then return to Step 5 (8 -> 5) for the next pending `TF` task, so every fix runs through the normal allowlist, task gate, and review gate, and lands in the same branch and PR as the planned work. Later Step 8 entries during the sweep do NOT re-read `followup.md`; they update the queue statuses in `progress.md` and pick 8 -> 5 while pending `TF` tasks remain, Step 9 when none do. During the sweep, skip the per-task validation ask above — request validation once, before Step 9.

Sweep rules:

- A `TF` task's Step 7 review may use the collapsed single-agent simplify path regardless of `loop_count`: its scope was already screened and classified by a planned task's review.
- New low findings discovered inside a `TF` task go to `followup-final.md` (append, never overwrite) and are NOT queued — list them in the completion report as residue.
- An item judged unsafe or out of scope to fix is marked `residue` in the queue with the reason and listed in the completion report.

## Step 9: Commit

Advance:

```bash
# [VibesDeGoGo! Step 9 Start] step=9, phase=commit, loop=0
vdgg_state_advance 9 commit
```

Commit on the feature branch. Include version files if Step 8 changed them.

Commit message format:

```text
{type}: {summary}
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

### branch-pr workflow

Default behavior:

1. push the feature branch,
2. create a PR,
3. report the PR URL,
4. stop for human merge approval.

Do not merge automatically just because CI is green.

### trunk workflow

Only when `.vdgg-target` explicitly sets `WORKFLOW=trunk`, commit directly on the current branch. Push only when `AUTO_PUSH=true`.

## Clear State And Finish

After PR creation or trunk commit/push decision:

```bash
vdgg_state_clear
```

Then provide a friendly completion report: what finished, what was verified, what the user needs to do next, build/version numbers if any, short technical details, any residual low findings from the followup sweep (with the reason each was left), and a lessons line (`lessons applied: N / new: M`).

## Stop Conditions

Do not stop for progress confirmation. Do stop before:

- violating Step 0 constraints,
- adding or changing dependencies,
- changing API, persistence, auth, permissions, security, billing, analytics, or user data contracts,
- destructive operations,
- broad renames,
- inability to satisfy or verify acceptance criteria.

When stopping intentionally, include `[Intentional Stop]` in assistant text and explain why.

## Checklist

- [ ] Step 0: agree on Goal / Constraints / Acceptance criteria.
- [ ] Step 1: initialize state and declare formation.
- [ ] Step 2: write `requirements.md`.
- [ ] Step 3: write `investigation.md`.
- [ ] Step 4: write `todo.md` and `progress.md`.
- [ ] Step 5: select one task and record `current_task`.
- [ ] Step 6: implement.
- [ ] Step 7: verify, run simplify, and only then mark verified.
- [ ] Step 6-R: if needed, investigate failure, record one hypothesis, and retry.
- [ ] Step 8: update progress/version, run the followup sweep for remaining low findings, and request validation.
- [ ] Step 9: commit, push/PR according to workflow, clear state, and report.
