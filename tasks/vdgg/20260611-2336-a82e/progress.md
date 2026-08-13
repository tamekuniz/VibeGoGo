# Progress

## Session notes

- 2026-06-11: Branch `fix/edition-parity-and-gates`. Scope: Codex-edition items from the review session + back-ports from Claude edition PR #1 (commit 93c17ce).
- Hook-enforcement note: session cwd is a different repo, so live hooks no-op here; workflow discipline followed manually per contract.

## Task log

### C1: state/gate parity back-port — DONE
- Ported from Claude PR #1: `vdgg_state_write` args 5/6 + `-` clear; 8→5 loop reset + task-scope clear; single-write `vdgg_task_begin`; stored-base-ref `changed_files` + task-notes exemption; pretool task-notes exemption. NEW: zsh-safety rename (`local path` → `entry`) after hitting the live bug — `path` is tied to $PATH in zsh and emptied it. Tests: 8→5 reset/clear, notes exemption, zsh regression (guarded by `command -v zsh`).
- Verified: 5/5 suites; simplify (single agent, ported logic): clean.

### C2: sentinel protection + posttool tracking — DONE (implemented by Sonnet delegate)
- Sidecar write-protection generalized to `.codex/.vdgg-*`; posttool flips the review sentinel on Edit/Write with sidecar/task-notes exclusions; +4 tests.
- Verified: `vdgg_task_gate bash tests/run-all.sh` passed (allowlist cross-check + 5/5 suites); simplify review: clean (sentinel-flip duplication judged acceptable, two different strategies).

### C3: jq fail-open when inactive — DONE (implemented by Sonnet delegate)
- Pretool jq-missing block: grep/sed cwd fallback + git-toplevel resolution; inactive → exit 0; active → fail closed with hints; +2 fakebin tests.
- Verified: task gate passed (5/5 suites); inline review: clean (one low: `R` variable name vs file's `ROOT` style → followup).

### C4 reflection r0 (external Codex review verdict: FAIL)
1. **Root Cause Investigation**: `vdgg_review_run`'s REVIEW_COMMAND extraction dies silently under `set -e` when the key is absent; the `tasks/vdgg/` changed-files filter exempts ALL sessions' records, not just the active one (see investigation-r0.md).
2. **Pattern Analysis**: pretool's `path_is_tasks_file` is id-scoped — the filter should mirror it; other extractions in the file guard with `|| true`.
3. **Hypothesis**: scoping the filter to `tasks/vdgg/${id}/` and guarding the extraction restores both documented behaviors without side effects.
4. **Implementation plan**: one fix — id-scope the filter + `|| true` the extraction, with regression tests for both. (Third reviewer finding — replace .gitignore management with .git/info/exclude — rejected as deliberate design; recorded in investigation-r0.md.)

### C4 reflection r1 (live gate failure at loop 1)
1. **Root Cause Investigation**: `vdgg_task_check_allowlist` derives the allowlist path from the current loop; after `vdgg_state_loop` the loop-1 path does not exist → "allowlist not found" (reproduced live by this session's own gate; see investigation-r1.md).
2. **Pattern Analysis**: the stored `task_allowlist_file` state field exists precisely for loop survival; `vdgg_task_changed_files` and the pretool already read it.
3. **Hypothesis**: resolving the allowlist from the state field (fallback: derived path) restores gate/rollback across retries with no change at begin-loop.
4. **Implementation plan**: one fix — state-field resolution in `vdgg_task_check_allowlist` (and rollback's existence guard), plus a loop-survival regression test.

### C4 reflection r2 (external review round 2)
1. **Root Cause Investigation**: `vdgg_task_rollback` derives `baseline_dir` from the current loop; after a retry the dir for the new loop doesn't exist → rollback dead exactly on the failure path (see investigation-r2.md). We had misclassified this as low/followup; reviewer's medium call accepted.
2. **Pattern Analysis**: same derive-vs-stored mismatch fixed twice already (allowlist r1, changed-files baseline C1) — the stored `task_base_ref` path encodes the begin loop.
3. **Hypothesis**: deriving `baseline_dir` from `task_base_ref` (`baseline-status-` → `baseline-`), with the old derivation as fallback, restores rollback across retries with zero schema change.
4. **Implementation plan**: one fix — string-derive baseline_dir from the stored base_ref in `vdgg_task_rollback` + a loop-1 rollback regression test.

### C4: review_run + gitignore + SKILL.md docs — DONE (Sonnet delegates ×3, external Codex reviews ×3)
- Added `vdgg_review_run`, `_vdgg_ensure_gitignore` (`# Codex / VibesDeGoGo!` marker), SKILL.md docs ([Error Acknowledged], REVIEW_COMMAND, executor keys, rollback recovery). External review via `vdgg_review_run` + `codex exec --sandbox read-only` (dogfood) FAILED twice with real findings: r0 = REVIEW_COMMAND extraction dies under set -e + tasks/vdgg filter too broad (fixed, id-scoped); r1 = live gate failure: allowlist lookup didn't survive loop increments (fixed via state-field resolution); r2 = rollback baseline_dir same bug (fixed via base_ref derivation). Round 3: VERDICT PASS. One reviewer finding rejected as design intent (gitignore vs .git/info/exclude).
- Verified: gate passed at loop 3 (live regression of the fix); 5/5 suites.

### C5: CI + READMEs — DONE (Opus delegate)
- `.github/workflows/test.yml` (ubuntu+macos, jq ensure, bash -n sweep, run-all); README guardrail paragraph + PR parenthetical; README.ja.md. Accuracy review caught a pre-existing layout omission (vdgg-hook-userprompt.sh) — fixed in both READMEs.
- Verified: gate passed; YAML valid; heading parity EN/JA.

### C6: CHANGELOG + version bump — DONE (Sonnet delegate)
- CHANGELOG 0.3.0 entry; SKILL.md version 0.3.0. Orchestrator review corrected two factual errors in the delegate's text (.vdgg-target path, apply_patch vs Bash) and removed a Claude-edition-only claim (simplify sentinel).
- Verified: gate passed; 5/5 suites; version grep OK.
