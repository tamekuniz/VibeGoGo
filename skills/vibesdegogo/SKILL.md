---
name: "VibesDeGoGo!"
description: "A state-and-hook workflow for Claude Code that keeps coding agents moving until done while stopping only before constraint violations."
version: 0.2.0
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
5. Report only changes, verification result, and residual risk.

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

The hooks validate declarations inside Bash command text for state transitions. Use the exact strings above.

## Step 0: Agree On Requirements

Before starting the state machine, agree with the user on:

1. Goal: what state or user value should be achieved.
2. Constraints: what must not change and what boundaries apply.
3. Acceptance criteria: concrete checks that determine completion.

Draft these three items in chat. Ask questions only for ambiguity that cannot be safely resolved. Start Step 1 only after the user clearly accepts the draft.

Step 0 is not mechanically enforced because no state file exists yet.

## Step 1: Formation Declaration

Initialize state:

```bash
source $HOME/.claude/skills/vibesdegogo/scripts/vdgg-state.sh
vdgg_state_init
```

For the default `branch-pr` workflow, create a feature branch after `vdgg_state_init` and before any code editing.

Branch name is derived from the Step 0 Goal, not from the VibesDeGoGo! id. Pick a name in the form `{type}/{slug}` where:

- `{type}` is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore` (same vocabulary as the Step 9 commit type).
- `{slug}` is a short kebab-case summary of the change (3-5 words, lowercase, ASCII, hyphen-separated). Drop articles and filler.
- Examples: `feat/japanese-readme`, `fix/init-portability`, `refactor/state-helpers`.

```bash
WORKFLOW=branch-pr; BASE_BRANCH=""
if [ -f "$(pwd)/.vdgg-target" ]; then source "$(pwd)/.vdgg-target"; fi
if [ "${WORKFLOW:-branch-pr}" != "trunk" ]; then
    if [ -z "${BASE_BRANCH:-}" ]; then
        BASE_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
        BASE_BRANCH=${BASE_BRANCH:-main}
    fi
    # VDGG_BRANCH: agent fills in based on the agreed Step 0 Goal.
    VDGG_BRANCH="<type>/<kebab-case-slug>"
    git checkout -b "$VDGG_BRANCH"
fi
```

Nesting is allowed: if the current branch is already a feature branch, a new `{type}/{slug}` branch is still created on top of it. The Step 1 block runs once per session because `vdgg_state_init` refuses a second initialization.

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
- Consider recent git history, lessons, and project notes when relevant.
- Mark unknowns explicitly.

Then advance:

```bash
# [VibesDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0
vdgg_state_advance 3 investigating
```

Use subagents only when parallel investigation clearly helps.

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

## Step 5: Select One Task

Choose one task from `todo.md` and record it in state:

```bash
# [VibesDeGoGo! Step 5 Start] step=5, phase=task-selected, loop=0
vdgg_state_advance 5 task-selected
vdgg_state_write 5 task-selected <loop_count> "T1: title"
```

## Step 6: Implement

Implement the selected task and write tests where appropriate.

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0
vdgg_state_advance 6 implementing
```

Do not run tests in `implementing`; the hook blocks test commands until Step 7.

## Step 7: Verify

Before running verification, state 1 to 3 concrete checks. Then run tests, builds, smoke checks, or manual checks as appropriate.

```bash
# [VibesDeGoGo! Step 7 Start] step=7, phase=testing, loop=0
vdgg_state_advance 7 testing
```

After all checks pass, run the `simplify` skill as a quality gate. The PostToolUse hook records a sentinel file:

```text
.claude/.vdgg-simplify-sentinel-{vdgg_id}-{loop_count}
```

Outcomes:

- Sentinel missing: `vdgg_state_advance 7 verified` is blocked.
- `modified=0`: verified transition is allowed.
- `modified=1`: verified transition is blocked; go through reflection and re-test.

For environments that cannot use the `simplify` skill, the state helper also exposes `vdgg_state_mark_reviewed` as an explicit review marker. It is an auxiliary compatibility hook, not a replacement for the Claude Code simplify gate when that gate is available.

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

At the beginning of reflection, start a researcher subagent for root-cause investigation unless self-maintenance mode explicitly allows skipping it for a mechanical typo/path issue.

The researcher must write:

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
- all tasks complete: continue to Step 9.

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

Then provide a friendly completion report: what finished, what was verified, what the user needs to do next, build/version numbers if any, and short technical details.

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
- [ ] Step 8: update progress/version and request validation.
- [ ] Step 9: commit, push/PR according to workflow, clear state, and report.
