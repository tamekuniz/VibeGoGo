# Investigation

All Codex-edition files were read in full during the review session that produced these requirements; the working tree is unchanged since (clean main at session start).

## 1. Related files

- `.agents/skills/vibesdegogo/scripts/vdgg-state.sh` — `vdgg_state_write` (4 args, preserves task fields by re-reading), `vdgg_state_advance` (no 8→5 special case — the parity gap), `vdgg_task_begin` (two-step write via perl/sed — same smell fixed in the Claude edition), `vdgg_task_changed_files` (derives per-loop baseline path; filters only `.codex/.vdgg-`), `vdgg_state_mark_reviewed` (already writes modified=0), `vdgg_state_clear`.
- `.agents/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh` — jq check fails closed before the active-file check; state-file protection covers only `.vdgg-state-`/`.vdgg-active`; allowlist check has no task-notes exemption; review gate already honors the review sentinel + task gate.
- `.agents/skills/vibesdegogo/scripts/vdgg-hook-posttool.sh` — review-modified tracking watches `apply_patch` only; jq missing exits 0 (already fail-open).
- `.agents/skills/vibesdegogo/scripts/vdgg-hook-stop.sh` — jq missing exits 0; OK.
- `.agents/skills/vibesdegogo/SKILL.md` — Step 5/7 documents task gate; `[Error Acknowledged]` is not documented (only the hook error message mentions it); no REVIEW_COMMAND/executor docs; version 0.2.0.
- `tests/` — 5 suites mirroring the Claude harness style (`tests/lib/assert.sh`).
- New files: `.github/workflows/test.yml`, `README.ja.md`.

## 2. Existing implementation patterns

- 2-space indent, compact guard style (`[ -f ... ] || exit 0`), `block()` helper in pretool.
- Hook JSON parsed with jq; CWD resolved to git toplevel.
- Reference implementation for every change: the Claude edition PR #1 (same repo family) — port with `.claude`→`.codex` path swaps and style adaptation.

## 3. Impact surface

- State-file field semantics shared with hooks (pretool reads `task_allowlist_file=` from state; gate path derived per loop) — the 8→5 clear plugs the stale-allowlist hole exactly as in the Claude edition.
- posttool Edit/Write tracking must exclude sidecars and task notes (same exemptions as pretool).
- Codex pretool resolves CWD to the git toplevel; the jq fallback must do the same (`git -C "$cwd" rev-parse --show-toplevel`, available without jq).

## 4. Prior similar implementations

- Claude edition commit 93c17ce (PR #1): verified-gate dual sentinel, sidecar protection glob, `-` clear marker, single-write `vdgg_task_begin`, stored-base-ref `changed_files`, jq fail-open, `vdgg_review_run`, `_vdgg_ensure_gitignore`, CI workflow, README.ja.md.

## 5. Side effects and risks

- Behavior change: task-notes exemption relaxes the allowlist check (progress.md editable mid-task — required by the workflow itself); release-noted.
- `vdgg_state_write` arg additions are backward compatible (all existing callers pass ≤4 args).
- Codex hooks also fire for `apply_patch`; the sidecar write-protection must cover apply_patch file paths (changed_files() already extracts them).

## 6. Constraints

- As in requirements: API stable, no deps, surgical, branch-pr.

## 7. Verification strategy

- Per task: `bash -n`; `bash tests/run-all.sh`; new regression cases per acceptance criteria.
