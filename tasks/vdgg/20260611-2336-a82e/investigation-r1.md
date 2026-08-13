# Reflection investigation r1 (gate failure after loop increment)

Trigger: `vdgg_task_gate` failed with "allowlist not found" at loop 1 during this very session — live reproduction. Researcher subagent skipped per self-maintenance mode (mechanism identified from the failing call).

## 1. Related files
- `.agents/skills/vibesdegogo/scripts/vdgg-state.sh`: `vdgg_task_check_allowlist`, `vdgg_task_rollback`.

## 2. Existing implementation patterns
- The state file stores `task_allowlist_file` precisely so the allowlist survives `vdgg_state_loop`; `vdgg_task_changed_files` already prefers the stored `task_base_ref` (C1/C4 fixes). The pretool hook reads the stored field too.

## 3. Impact surface
- `vdgg_task_check_allowlist` derives the allowlist path from the CURRENT loop; after any reflection retry (loop > begin-loop) it reports "allowlist not found", breaking `vdgg_task_gate` and `vdgg_task_rollback` exactly when retries happen.

## 4. Prior similar implementations
- Claude edition resolves the allowlist from the stored state field (T3 reuse-review fix); this back-port was missed in C1.

## 5. Side effects and risks
- None known; fallback to the derived path keeps behavior identical at loop = begin-loop.

## 6. Constraints
- Same C4 allowlist (vdgg-state.sh, SKILL.md, test-codex-state.sh).

## 7. Verification strategy
- Regression test: begin task at loop 0, `vdgg_state_loop` to 1, assert `vdgg_task_check_allowlist` still passes and `vdgg_task_gate true` succeeds. Full suite + re-run the gate for this session (which is itself at loop 2 now — the live regression check).
