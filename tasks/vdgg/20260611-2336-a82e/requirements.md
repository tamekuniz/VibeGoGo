# Requirements

## Goal

Apply every Codex-edition item from the 2026-06-11 review session, including back-ports of the fixes made in the Claude Code edition (PR tmknzz/VibesDeGoGo-for-Claude-Code#1):

1. Parity: 8→5 transition resets `loop_count` to 0 and clears `task_allowlist_file`/`task_base_ref` (forcing `vdgg_task_begin` per task); `vdgg_state_write` gains optional args 5/6 with `-` clear marker; `vdgg_task_begin` does a single atomic state write (perl/sed patch removed); `vdgg_task_changed_files` prefers the stored `task_base_ref` and exempts `tasks/vdgg/` notes; pretool allowlist check exempts task notes.
2. Posttool tracks review-sentinel modification for `Edit`/`Write` (not only `apply_patch`); sidecar write-protection generalized to all `.codex/.vdgg-*` paths (Edit/Write/apply_patch + Bash write patterns), closing sentinel forgery.
3. jq fail-open when inactive: missing jq no longer blocks repositories without an active VDGG session; active sessions keep failing closed with multi-distro hints.
4. `vdgg_review_run` helper (REVIEW_COMMAND from `.vdgg-target` or argv; review sentinel only on success); `.gitignore` self-management for `.codex/.vdgg-*`; SKILL.md documents REVIEW_COMMAND, `STEP3/4/6_EXECUTOR_COMMAND`, `[Error Acknowledged]`, and rollback recovery when out-of-allowlist changes exist.
5. CI workflow (ubuntu+macos, syntax + tests); README guardrail wording (already partially present — verify) and README.ja.md.
6. CHANGELOG entry and version bump to 0.3.0.

## Constraints

- Keep step numbers, phase names, state-file format (field additions only), helper API names.
- No new external dependencies; bash + jq with fail-open fallback.
- Surgical edits matching existing 2-space Codex-edition style.
- branch-pr: commit on `fix/edition-parity-and-gates`, push, open PR, stop for human merge.
- The Claude Code repo and dev repo are out of scope for this session.

## Acceptance criteria

1. `bash tests/run-all.sh` passes (existing 5 suites + new cases).
2. New tests cover: 8→5 loop reset + task-field clear; posttool Edit/Write flips review sentinel; sentinel forgery blocked; jq-missing inactive→pass / active→block; `vdgg_review_run` success/failure; task-notes exemption.
3. `bash -n` clean on all changed scripts.
4. CI workflow file exists; README.ja.md exists; CHANGELOG/SKILL.md version = 0.3.0.
