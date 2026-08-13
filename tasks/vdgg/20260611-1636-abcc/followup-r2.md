# Followup candidates (low-severity simplify findings, T3 round 3, not applied)

1. severity=low — `vdgg_state_write`: the two `-`/preserve if-elif blocks for args 5/6 are the same 4-line pattern twice; could extract a tiny helper. Two call sites only; indirection cost roughly equals the duplication cost.
2. severity=low — `vdgg_state_advance`: `current_loop` is computed before the 8→5 early return and unused on that path; move the extraction below the guard (cold path, cosmetic).
3. severity=low — (carried from round 2) extract a `_vdgg_state_field()` helper for the repeated `grep '^key=' | cut -d= -f2-` idiom (11+ sites across the file).
4. severity=low — (carried) `vdgg_task_rollback` derives `baseline_dir` from the current loop; after a loop increment mid-task the baseline dir of the begin-loop is the meaningful one (same behavior as the Codex edition today; gate/check are unaffected because they use the stored `task_base_ref`).
