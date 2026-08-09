---
name: vibesdegogo
description: "Use VibesDeGoGo! for Codex when the user asks Codex to carry coding work through requirements, investigation, planning, implementation, verification, progress reporting, and commit/PR with safety stops."
version: 0.2.0
---

> **⚠️ SUPERSEDED COPY — frozen at 2026-06-07. Do not read this file as the current specification.**
> The maintained Codex edition lives in
> [VibesDeGoGo-for-Codex](https://github.com/tmknzz/VibesDeGoGo-for-Codex).
> Features added after the freeze — Formation per-step model assignment, executor
> delegation, the task gate, and external review — are absent here.

# VibesDeGoGo! for Codex

VibesDeGoGo! for Codex is a serial, state-file-driven workflow for autonomous coding in Codex. It follows the VibesDeGoGo! for Claude Code step model first; do not simplify the workflow unless the user explicitly asks for a lighter mode.

## When To Use

Use this skill for coding work where the user wants Codex to continue through implementation, verification, and commit/PR.

Trigger phrases include `VibesDeGoGo! for Codex`, `VibesDeGoGo!`, `/VibesDeGoGo!`, and Japanese equivalents such as `VibesDeGoGoで進めて`.

Do not use it for wording-only requests, open-ended discussion, or brainstorming where no repository workflow should execute.

## Important Codex Differences

- State lives in `.codex/.vdgg-active` and `.codex/.vdgg-state-{id}`.
- Task files still live in `tasks/vdgg/{id}/`.
- Prefer global hooks in `~/.codex/hooks.json` or `~/.codex/config.toml` so VDGG rules apply across repositories. Repo-local `.codex/hooks.json` is optional and only covers that repository after trust.
- Hook commands should call the installed skill path, normally `$HOME/.codex/skills/vibesdegogo`, or set `VDGG_CODEX_SKILL_DIR` to an absolute skill directory. Do not assume the target project contains `.agents/skills/vibesdegogo`.
- Codex hook coverage is a guardrail, not a complete enforcement boundary. When unsure, stop before risky work.
- Codex does not have the exact Claude Code `simplify` gate. Use the Codex review gate in this skill instead: after verification, run a focused simplification/review pass yourself, record it with `vdgg_state_mark_reviewed`, then advance to `verified`.

Use this resolver inside every shell command that calls state helpers:

```bash
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
if [ ! -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ]; then
  VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
fi
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
```

## Step 0: Agree On Requirements

Before starting the state machine, draft and get agreement on:

1. Goal: what state or user value should be achieved.
2. Constraints: what must not change and what boundaries apply.
3. Acceptance criteria: concrete checks that determine completion.

Default constraints must include:

- Prefer the target environment's standard features, components, APIs, and patterns.
- Do not add custom UI, custom components, custom state management, custom design systems, custom utilities, or external dependencies unless the need is clear.
- Stop before changing constraints, adding dependencies, changing API/persistence/auth/permissions/security/billing/analytics/user-data behavior, destructive operations, or broad renames.
- Do not mark work complete without verification.

Start Step 1 only after the user clearly accepts the draft.

Do not create or advance `.codex/.vdgg-*` state files, create task files, switch branches, or edit implementation files before Step 0 is accepted. Step 0 happens before state exists, so hooks cannot fully enforce it; the agent must stop itself here.

## Step 1: Formation

```bash
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
if [ ! -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ]; then
  VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
fi
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_init
```

For the default `branch-pr` workflow, create a feature branch after initialization and before code edits.

Branch name is derived from the Step 0 Goal, not from the VibesDeGoGo! id. Pick a name in the form `{type}/{slug}` where:

- `{type}` is one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore` (same vocabulary as the Step 9 commit type).
- `{slug}` is a short kebab-case summary of the change (3-5 words, lowercase, ASCII, hyphen-separated). Drop articles and filler.
- Examples: `feat/japanese-readme`, `fix/init-portability`, `refactor/state-helpers`.

```bash
WORKFLOW=branch-pr
BASE_BRANCH=""
if [ -f .vdgg-target ]; then source .vdgg-target; fi
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

Then output:

```text
[VibesDeGoGo! Declaration] id=<vdgg_get_id output>
```

## Step 2: Requirements

Write `tasks/vdgg/{id}/requirements.md`:

```markdown
## Goal
...

## Constraints
...

## Acceptance criteria
...
```

Advance:

```bash
# [VibesDeGoGo! Step 2 Start] step=2, phase=requirements, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 2 requirements
```

## Step 3: Investigation

Read actual project files. Do not guess. Trace direct callers and impact. Record unknowns explicitly in `tasks/vdgg/{id}/investigation.md`.

Advance:

```bash
# [VibesDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 3 investigating
```

## Step 4: Planning

Create `tasks/vdgg/{id}/todo.md` and `tasks/vdgg/{id}/progress.md`.

Advance:

```bash
# [VibesDeGoGo! Step 4 Start] step=4, phase=planning, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 4 planning
```

## Step 5: Select One Task

Choose exactly one task sized for a full implementation cycle:

- one task must be small enough to complete implementation, tests, build, and real/manual check in one Step 6 to Step 8 loop;
- split separate provider/API/auth/key-storage/UI/persistence/versioning risks into separate tasks;
- do not select umbrella tasks such as `T1-T3` or "all model providers";
- if the selected task cannot be verified with the current acceptance criteria in one Step 7, split it before Step 6.

Choose one task and record it:

```bash
# [VibesDeGoGo! Step 5 Start] step=5, phase=task-selected, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 5 task-selected
vdgg_state_write 5 task-selected 0 "T1: title"
```

## Step 6: Implement

Advance before editing implementation files:

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 6 implementing
```

Do not run verification commands in this phase.

## Step 7: Verify And Review

State 1 to 3 concrete verification checks, then run them.

```bash
# [VibesDeGoGo! Step 7 Start] step=7, phase=testing, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 7 testing
```

After checks pass, do a focused simplification/review pass:

- remove unnecessary complexity,
- confirm standard-first choices,
- confirm no constraints were violated,
- record the review in `progress.md`.

Then mark the Codex review gate:

```bash
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_mark_reviewed
```

Finally advance:

```bash
# [VibesDeGoGo! Step 7 Start] step=7, phase=verified, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 7 verified
```

If verification fails or review changes implementation files, go to reflection.

## Step 6-R: Reflection

Advance:

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=reflection, loop=<same loop>
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 6 reflection
```

Write `tasks/vdgg/{id}/investigation-r{loop}.md` and update `progress.md` with:

1. Root Cause Investigation.
2. Pattern Analysis.
3. Hypothesis: exactly one hypothesis.
4. Implementation plan: exactly one fix.

Return to implementation:

```bash
# [VibesDeGoGo! Step 6 Start] step=6, phase=implementing, loop=<next loop>
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_loop 6 implementing
```

## Step 8: Progress And Validation Request

Advance:

```bash
# [VibesDeGoGo! Step 8 Start] step=8, phase=progress, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 8 progress
```

Update `progress.md`, update configured version files if `.vdgg-target` requires it, and ask the user for validation when needed.

## Step 9: Commit

Advance:

```bash
# [VibesDeGoGo! Step 9 Start] step=9, phase=commit, loop=0
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_advance 9 commit
```

Commit format:

```text
{type}: {summary}
```

Default `branch-pr` behavior:

1. commit on the feature branch,
2. push the feature branch,
3. create a PR,
4. report the PR URL,
5. stop for human merge approval.

`trunk` workflow is allowed only when `.vdgg-target` explicitly sets `WORKFLOW=trunk`.

After PR creation or trunk commit/push decision:

```bash
VDGG_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
VDGG_CODEX_SKILL_DIR="${VDGG_CODEX_SKILL_DIR:-$HOME/.codex/skills/vibesdegogo}"
[ -f "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" ] || VDGG_CODEX_SKILL_DIR="$VDGG_REPO_ROOT/.agents/skills/vibesdegogo"
source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh"
vdgg_state_clear
```

## Stop Conditions

Do not stop for progress confirmation. Stop intentionally with `[Intentional Stop]` before:

- violating Step 0 constraints,
- adding or changing dependencies,
- changing API, persistence, auth, permissions, security, billing, analytics, or user-data contracts,
- destructive operations,
- broad renames,
- inability to satisfy or verify acceptance criteria.
