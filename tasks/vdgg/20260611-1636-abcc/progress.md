# Progress

## Session notes

- 2026-06-11: Session started on branch `feat/v17-sync-and-quality-gates`. Requirements agreed in chat (user pre-approved "apply everything from the review session").
- Investigation finding: the split repo (0.2.0) is the cleaner successor; v1.7.1 (installed) contributes gitignore management + SKILL.md operational sections only. The v1.7.1 background `brew install jq` auto-run is intentionally NOT ported.
- Hook-enforcement note: this session runs with cwd in a different repo, so the live hooks no-op against this repo; workflow discipline (no tests during implementing, simplify gate before verified, no commit before Step 9) is followed manually per contract.

## Task log

### T1: Port v1.7.1 improvements — DONE
- Changed: `vdgg-state.sh` (+`_vdgg_ensure_gitignore`, called from init); `SKILL.md` (lightweight version-bump item, branch MUST line, stay-on-feature-branch Step 1 snippet replacing the literal-checkout footgun, simplify consolidation + severity sections).
- Simplify gate: 4 findings (3 low, 1 medium). Applied: gitignore pattern list collapsed to single `.claude/.vdgg-*` glob (medium — removes T3 update burden); dropped redundant `2>/dev/null`. Skipped: snippet comment "duplication" — point-of-use reminders for agents are functional. Reflection skipped per self-maintenance mode (mechanical list→glob swap), re-verified instead.
- Verified: `bash -n` OK; 4/4 test suites green; gitignore append idempotent (single marker after double call).
- Residual risk: none known; `.vdgg-target` (project root) unaffected by the `.claude/.vdgg-*` glob.

### T2: Review gate fix — DONE
- Changed: pretool verified gate accepts simplify OR review sentinel and consumes both; sidecar write-protection generalized to `.claude/.vdgg-` (Edit/Write + Bash write patterns); posttool flips `modified=1` on whichever sentinel exists; `vdgg_state_mark_reviewed` now writes `modified=0`/`modified_files=` (Codex parity); docs updated (SKILL.md Step 7, state_helpers.md, hook_rules.md → "Review Gate"); tests +7 cases (review-sentinel allow/block/consume, forgery via Write and Bash, posttool flip + task-notes exclusion), test-state.sh updated for new mark_reviewed fields.
- Simplify gate: low-only findings → recorded in followup-r0.md per severity policy, no implementation edits.
- Verified: `bash -n` ×3 OK; 4/4 suites green including new cases.
- Residual risk: docs reference `vdgg_review_run` which lands in T6 — T6 must land in this PR (it is planned).

### T3 reflection r0 (simplify medium finding)
1. **Root Cause Investigation**: `vdgg_task_begin` wrote state twice (vdgg_state_write, then perl/sed patch for the two task fields) because `vdgg_state_write` had no way to set them — see investigation-r0.md. A perl/sed failure would leave half-written state.
2. **Pattern Analysis**: `vdgg_state_write` already preserves omitted `current_task` by re-reading the old state; the two task fields fit the same optional-argument + preserve pattern.
3. **Hypothesis**: extending `vdgg_state_write` with optional args 5/6 (allowlist, base_ref) removes the two-step write without touching any other call site.
4. **Implementation plan**: one fix — add the optional args with preserve-on-omit, call them from `vdgg_task_begin`, and make `vdgg_task_changed_files` prefer the stored `task_base_ref` so gates survive loop increments.

### T3 reflection r1 (round-2 simplify medium finding)
1. **Root Cause Investigation**: preserve-on-omit in `vdgg_state_write` carries the previous task's `task_allowlist_file` across the 8→5 boundary; an agent skipping `vdgg_task_begin` could then edit the previous task's files (see investigation-r1.md).
2. **Pattern Analysis**: the 8→5 branch in `vdgg_state_advance` already resets `loop_count` — task-scope cleanup belongs in the same boundary.
3. **Hypothesis**: an explicit clear marker (`-`) for the optional args lets the 8→5 branch clear both task fields, forcing `vdgg_task_begin` before any new-task edits.
4. **Implementation plan**: one fix — `vdgg_state_write` treats `-` as clear-to-empty for args 5/6; `vdgg_state_advance` passes `- -` on the 8→5 transition; regression test in test-state.sh.

### T3: Task allowlist/gate port — DONE (3 simplify rounds, 2 reflections)
- Changed: `vdgg-state.sh` (+10 helpers/functions: task path helpers, normalize/safe-relative, `_vdgg_rm_dir_glob`, `vdgg_task_begin/changed_files/check_allowlist/gate/rollback`; state file +`task_allowlist_file`/`task_base_ref`; `vdgg_state_write` optional args 5/6 with `-` clear marker; 8→5 clears task scope); pretool (allowlist enforcement in implementing/testing with task-notes exemption, task-gate requirement before verified); SKILL.md Steps 5–7 + reflection; state_helpers.md; hook_rules.md table; tests (+test-task-gate.sh suite, +6 pretool cases, +3 state assertions).
- Improvements over the Codex original: task notes exempt from allowlist; single atomic state write in `vdgg_task_begin` (perl/sed patch removed); `vdgg_task_changed_files` anchors to the stored `task_base_ref` across retry loops; 8→5 boundary clears task scope so `vdgg_task_begin` is mechanically required per task. These should be back-ported to the Codex edition.
- Verified: `bash -n` OK; 5/5 suites green (round 3 simplify: low-only → followup-r2.md).
- Residual risk: behavior change for existing users (allowlist now mandatory in implementing/testing) — release-noted in T9's CHANGELOG entry.

### T4: jq fail-open when inactive — DONE
- Changed: pretool/posttool jq-missing blocks now grep-extract cwd and exit 0 when no `.vdgg-active` exists there; active sessions keep fail-closed + install-hints + jq-install passthrough; setup.md wording updated; +2 pretool tests (fakebin PATH without jq: inactive→0, active→2). Simplify: clean (lows to followup).
- Verified: `bash -n` ×2 OK; 5/5 suites green.

### T5: small cleanups — DONE
- Changed: dead `*/${TASKS_DIR}/*` glob alternatives replaced with the relative-form pair (now consistent across all three phase cases); `.vdgg-step-block-*` remnants removed from init/clear and state_helpers.md; hook_rules.md "Known Limits" documents the same-second mtime edge. Simplify (single-agent, deletion-only diff): clean.
- Verified: `bash -n` OK; 5/5 suites green; zero step-block references left in code/docs.

### T7: plugin packaging — DONE
- Changed: `.claude-plugin/plugin.json` + `marketplace.json`, `hooks/hooks.json` (4 events via `${CLAUDE_PLUGIN_ROOT}`); `VDGG_SKILL_DIR` resolver in SKILL.md/state_helpers.md/hook_rules.md; plugin-install sections in README.md/setup.md; +test-plugin-manifests.sh (JSON validity, required fields, script-path existence, version consistency); SKILL.md version → 0.3.0. Schemas verified against official plugin docs. Simplify: lows to followup (matcher narrowing, cross-check test, description alignment).
- Verified: 6/6 suites green.

### T8: CI — DONE
- Changed: `.github/workflows/test.yml` (ubuntu+macos matrix, jq ensure, `bash -n` sweep, `tests/run-all.sh`). YAML validated locally; actual runner execution happens on the PR. Simplify: collapsed to inline review (declarative single file, no logic) — clean.

### T9: docs finish — DONE
- Changed: CHANGELOG 0.3.0 entry (behavior change called out); README guardrails-honesty paragraph + layout tree updated with plugin dirs (review caught the omission); README.ja.md added; output_formats.md final report explains what a PR is for first-time users.
- Verified: 6/6 suites green; version consistent across plugin.json/SKILL.md/CHANGELOG; docs accuracy spot-checked against the actual repo by a review agent.

### T6: external review/executor options — DONE
- Changed: `vdgg_review_run` helper (argv or `.vdgg-target` REVIEW_COMMAND; sentinel only on exit 0); target_schema.md documents `REVIEW_COMMAND` + `STEP3/4/6_EXECUTOR_COMMAND` with placeholders; SKILL.md "Delegated step executors" section + Step 7 `vdgg_review_run` usage; subagent_prompts.md notes the prompts double as executor templates; +3 state tests. Simplify: clean, 2 lows to followup.
- Verified: `bash -n` OK; 5/5 suites green.
