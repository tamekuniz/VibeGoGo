# VibesDeGoGo! Reference: State Helpers

The state helper script is:

```bash
VDGG_SKILL_DIR="${VDGG_SKILL_DIR:-$HOME/.claude/skills/vibesdegogo}"
source "$VDGG_SKILL_DIR/scripts/vdgg-state.sh"
```

For plugin installs, set `VDGG_SKILL_DIR` to the skill's base directory announced when the skill loads.

## Files

```text
.claude/.vdgg-active
tasks/vdgg/{id}/
.claude/.vdgg-state-{id}
```

State file format:

```text
step=<number>
phase=<phase>
loop_count=<number>
current_task=<task title>
task_allowlist_file=<path to active allowlist, empty before vdgg_task_begin>
task_base_ref=<path to baseline git-status snapshot>
vdgg_id=<YYYYMMDD-HHMM-xxxx>
last_updated=<UTC timestamp>
```

## Public Functions

```bash
vdgg_state_init
vdgg_state_read
vdgg_state_write <step> <phase> <loop_count> [current_task] [task_allowlist_file] [task_base_ref]
vdgg_state_advance <step> <phase>
vdgg_state_loop <step> <phase>
vdgg_state_mark_reviewed
vdgg_task_begin <task title> <allowed path>...
vdgg_task_changed_files
vdgg_task_check_allowlist
vdgg_task_gate [verification command...]
vdgg_task_rollback
vdgg_state_clear
vdgg_get_tasks_dir
vdgg_get_id
```

## Task Gate

`vdgg_task_begin` writes the allowlist to
`.claude/.vdgg-task-allowlist-{id}-{loop}`, snapshots the allowlisted files
into `.claude/.vdgg-task-baseline-{id}-{loop}/`, and records a
`git status --porcelain` baseline. During `implementing` and `testing`, the
pretool hook blocks Edit/Write outside the allowlist (task notes under
`tasks/vdgg/{id}/` are exempt). `vdgg_task_gate` re-checks the allowlist
against actual changed files (catching Bash-mediated edits too), runs the
verification command, and writes `.claude/.vdgg-task-gate-{id}-{loop}` on
success — required before `verified` whenever an allowlist is active.
`vdgg_task_rollback` reverts allowlisted changes to the baseline; if files
outside the allowlist changed, it refuses — resolve those manually (e.g.
`git status` + `git checkout -- <file>`) before retrying.

`vdgg_state_mark_reviewed` is the explicit review marker for review passes
done without the Claude Code `simplify` skill (manual review or an external
reviewer via `REVIEW_COMMAND`). It writes a per-loop review sentinel under
`.claude/.vdgg-review-sentinel-{id}-{loop}` with `modified=0`. The verified
gate accepts either the simplify sentinel or this review sentinel; both flip
to `modified=1` when implementation files are edited afterward in the same
loop. See `SKILL.md` Step 7 for the full gate description.

## Transition Rules

Allowed transitions:

- same step,
- next step,
- `8 -> 5` to continue with unfinished tasks,
- `7 -> 6` for testing/reflection retry.

`vdgg_state_loop` increments `loop_count` and removes the old simplify sentinel for that loop.

`8 -> 5` resets `loop_count` to 0 and clears `task_allowlist_file`/`task_base_ref` because a new task starts; `vdgg_task_begin` must run again before the next task's edits. Omitted optional args of `vdgg_state_write` preserve the stored values; a literal `-` clears a task field explicitly.

## Cleanup

`vdgg_state_init` and `vdgg_state_clear` remove stale transient files:

```text
.claude/.vdgg-error-pending
.claude/.vdgg-simplify-sentinel-*
.claude/.vdgg-review-sentinel-*
.claude/.vdgg-task-*  (allowlists, baselines, gate files)
```

## Simplify Sentinel

Path:

```text
$CWD/.claude/.vdgg-simplify-sentinel-{vdgg_id}-{loop_count}
```

Fields:

```text
started=1
started_at=<UTC timestamp>
modified=0|1
modified_files=<comma-separated paths>
```

Lifecycle:

1. Created by PostToolUse when the `simplify` skill runs during `testing`.
2. Updated to `modified=1` when Edit/Write runs after simplify in the same loop.
3. Deleted when verified transition succeeds, loop advances, or state clears.
