# Requirements

## Goal

Bring VibesDeGoGo-for-Claude-Code up to a sellable state by applying every improvement identified in the 2026-06-11 review session:

1. Reconcile the drift: port the content of the live installed skill (`~/.claude/skills/vibesdegogo`, v1.7.1) into this repository (currently v0.2.0), so the public repo matches what is actually battle-tested daily.
2. Fix the review-gate hole: the `verified` transition must accept the `vdgg_state_mark_reviewed` review sentinel as an alternative to the simplify sentinel, and direct writes to sentinel files must be blocked like state files (no heredoc forgery path).
3. Port the task allowlist/gate mechanism (`vdgg_task_begin` / `vdgg_task_gate` / `vdgg_task_rollback` + hook enforcement) from the Codex edition, so Bash-mediated file edits can no longer bypass phase discipline undetected.
4. Make hooks fail open when VDGG is inactive and `jq` is missing (no blocking of unrelated repositories), while keeping fail-closed behavior when a VDGG session is active. (Partially addressed in v1.7.1 — verify and complete.)
5. Small logic cleanups: dead `*/${TASKS_DIR}/*` glob, `.vdgg-step-block-*` remnant cleanup, document the reflection same-second mtime edge.
6. Plugin packaging: add `.claude-plugin/plugin.json` + `hooks/hooks.json` so the repo installs as a Claude Code plugin with hooks auto-activated; keep manual install path working; document both.
7. CI: GitHub Actions workflow running `tests/run-all.sh` on ubuntu and macos.
8. Japanese README (README.ja.md); honest wording about enforcement ("guardrail, not a complete boundary"); add a beginner-friendly one-line explanation of what a PR is to the final report format.
9. External review/executor option: `.vdgg-target` gains `REVIEW_COMMAND` (external reviewer such as codex/qwen, wrapped by a helper that writes the review sentinel on success) and documented `STEP3/4/6_EXECUTOR` keys; artifact validation (file exists + required headings) before advancing past delegated steps.

## Constraints

- Do not break the existing step structure (Steps 0-9), phase names, state-file format, or public helper API names.
- Standard-first: no new external dependencies (jq stays the only one, with fallback); plain bash + existing patterns only.
- Surgical changes: keep existing script/hook/doc structure; match existing style.
- branch-pr workflow: commit on `feat/v17-sync-and-quality-gates`, push, open a PR, stop for human merge approval. Never merge automatically.
- The live installed copy `~/.claude/skills/vibesdegogo` is read-only reference material in this session — do not modify it.
- The dev repo `VibesDeGoGo!` and the Codex repo are out of scope for this session (Codex repo gets its own follow-up session).

## Acceptance criteria

1. `bash tests/run-all.sh` passes (all existing tests green).
2. New/updated tests cover: review-sentinel accepted at verified gate; sentinel-file direct writes blocked; task allowlist blocks out-of-allowlist edits during implementing/testing; jq-missing + VDGG-inactive does not block.
3. `bash -n` passes on every changed script.
4. Repo content is a superset of the installed v1.7.1 (no regression of live improvements; `diff -rq` shows repo-side additions only or intentional documented differences).
5. Plugin manifest validates: `.claude-plugin/plugin.json` + `hooks/hooks.json` exist and reference the in-repo script paths.
6. CI workflow file exists and runs the test suite on push/PR for ubuntu + macos.
7. README.ja.md exists and matches README.md content; README states the guardrail nature of enforcement.
8. `target_schema.md` documents `REVIEW_COMMAND` and `STEP*_EXECUTOR`; the review wrapper writes the review sentinel only on success; SKILL.md Step 7 documents the external-review path.
