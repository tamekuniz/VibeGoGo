# Reflection investigation r0 (C4 external review findings)

External reviewer: `codex exec --sandbox read-only` via `vdgg_review_run` (verdict FAIL). Researcher subagent skipped per self-maintenance mode: findings are precise and mechanically verifiable.

## 1. Related files
- `.agents/skills/vibesdegogo/scripts/vdgg-state.sh`: `vdgg_task_changed_files` (filter scope), `vdgg_review_run` (extraction guard).

## 2. Existing implementation patterns
- `path_is_tasks_file` in the pretool is already scoped to the active id (`tasks/vdgg/${VDGG_ID}/`); the changed-files filter should match that scope.
- The file runs under `set -euo pipefail`; other extraction sites guard with `|| true`.

## 3. Impact surface
- Filter fix narrows the blind spot: only the ACTIVE session's notes are exempt; edits to other sessions' records or unrelated files under `tasks/vdgg/` are visible to allowlist/rollback again.
- `|| true` guard restores the intended "no command given" error path when `.vdgg-target` exists without `REVIEW_COMMAND`.

## 4. Prior similar implementations
- Claude edition has the same broad filter (carried in the back-port) — to be fixed there in the follow-up commit to PR #1 along with the zsh rename.

## 5. Side effects and risks
- None known; both fixes shrink behavior to the documented intent.

## 6. Constraints
- Same task allowlist (vdgg-state.sh, SKILL.md, test-codex-state.sh).

## 7. Verification strategy
- New tests: changed-files shows edits under `tasks/vdgg/<other-id>/`; `vdgg_review_run` with a `.vdgg-target` lacking REVIEW_COMMAND returns 1 and prints the error. Full suite green; re-run the external Codex review.

Rejected finding (recorded): replacing `.gitignore` self-management with `.git/info/exclude` — deliberate v1.7.x design (marker-guarded, documented); `.git/info/exclude` does not survive clones and complicates setup.
