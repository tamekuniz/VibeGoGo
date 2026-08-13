# Reflection investigation r1 (T3 round-2 simplify finding)

Researcher subagent skipped per self-maintenance mode: mechanism fully understood from the altitude review.

## 1. Related files
- `skills/vibesdegogo/scripts/vdgg-state.sh`: `vdgg_state_write` (preserve-on-omit), `vdgg_state_advance` (8→5 branch).

## 2. Existing implementation patterns
- 8→5 already special-cases loop reset in `vdgg_state_advance`; clearing task fields belongs in the same branch.
- Preserve-on-omit means empty arg = preserve, so an explicit clear marker is needed; `-` is the conventional CLI "empty" sentinel and can never be a real path here.

## 3. Impact surface
- Without the fix: after 8→5, `task_allowlist_file` still points at the previous task's allowlist, so an agent that skips `vdgg_task_begin` could edit the previous task's files mechanically unchallenged.
- With the fix: the pretool "No active task allowlist" block fires until `vdgg_task_begin` runs for the new task.

## 4. Prior similar implementations
- Loop reset at 8→5 (same branch) sets the precedent for boundary cleanup.

## 5. Side effects and risks
- `vdgg_state_write` callers passing `-` as a literal path would clear instead — no such caller exists, and paths named `-` are not produced anywhere.

## 6. Constraints
- Public API stays backward compatible.

## 7. Verification strategy
- test-state.sh: set task fields at step 7, advance 8→5, assert both fields cleared; full suite green.
