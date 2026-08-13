# Reflection investigation r2 (external review round 2: rollback baseline)

Trigger: codex exec re-review verdict FAIL — `vdgg_task_rollback` derives `baseline_dir` from the current loop, so rollback fails with "baseline dir not found" after any `vdgg_state_loop` increment. Previously misclassified by us as low/followup; the reviewer is right that rollback is a failure-path tool and failures are exactly when loops increment.

## 1. Related files
- `.agents/skills/vibesdegogo/scripts/vdgg-state.sh`: `vdgg_task_rollback`.

## 2. Existing implementation patterns
- The state field `task_base_ref` stores the begin-time baseline STATUS path `.vdgg-task-baseline-status-{id}-{loop}`; the baseline DIR is the same path with `baseline-status-` → `baseline-` — derivable without schema changes.

## 3. Impact surface
- Rollback becomes usable across retries; behavior at begin-loop unchanged (string-derived path equals the directly derived one).

## 4. Prior similar implementations
- Same derivation already fixed for the allowlist (r1) and changed-files baseline (C1/C4); Claude edition rollback has the identical bug — added to the PR #1 follow-up commit list.

## 5. Side effects and risks
- If `task_base_ref` is empty (no task begun), fall back to the loop-derived path as before.

## 6. Constraints
- Same C4 allowlist files.

## 7. Verification strategy
- Regression test: begin at loop 0 → loop to 1 → modify the allowlisted file → `vdgg_task_rollback` exits 0 and restores baseline content. Full suite + gate + codex re-review.
