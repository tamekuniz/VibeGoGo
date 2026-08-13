# Investigation

## 1. Related files

- `skills/vibesdegogo/scripts/vdgg-state.sh` — state helpers; gains gitignore management (port), task allowlist/gate (port from Codex), review-run wrapper (new).
- `skills/vibesdegogo/scripts/vdgg-hook-pretool.sh` — verified gate (simplify sentinel only today), jq fail-closed block, phase guards, dead `*/${TASKS_DIR}/*` glob at lines 204/227.
- `skills/vibesdegogo/scripts/vdgg-hook-posttool.sh` — simplify sentinel creation + modified tracking (Edit/Write only), jq fail-closed block.
- `skills/vibesdegogo/scripts/vdgg-hook-stop.sh` — already fails open without jq; no change needed beyond none.
- `skills/vibesdegogo/SKILL.md` — Step 1/5/6/7 instructions; gains 1.7.1 sections + allowlist/gate usage + external review path + `VDGG_SKILL_DIR` resolver.
- `skills/vibesdegogo/references/{state_helpers,target_schema,hook_rules,setup,output_formats,subagent_prompts}.md` — docs to update per feature.
- `tests/` — `lib/assert.sh` harness, four suites; extend pretool/state suites, add jq-missing coverage.
- New: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `hooks/hooks.json`, `.github/workflows/test.yml`, `README.ja.md`.
- Read-only reference: `~/.claude/skills/vibesdegogo` (installed v1.7.1), `../VibesDeGoGo-for-Codex/.agents/skills/vibesdegogo/scripts/vdgg-state.sh` (allowlist source).

## 2. Existing implementation patterns

- Hooks: bash, `set -euo pipefail`, parse hook JSON with jq, exit 0 = allow, exit 2 + stderr = block.
- State: KEY=VALUE file rewritten whole via heredoc; transitions validated by `_vdgg_check_step_transition` (same/+1/8→5/7→6).
- Sentinels: `.claude/.vdgg-simplify-sentinel-{id}-{loop}` (created by posttool on Skill simplify; consumed by pretool at verified). `.claude/.vdgg-review-sentinel-{id}-{loop}` written by `vdgg_state_mark_reviewed` but consumed by nothing (the hole).
- Codex allowlist pattern: `vdgg_task_begin` snapshots baseline (file copies + `git status --porcelain` snapshot), `vdgg_task_changed_files` diffs two status snapshots with `sort | uniq -u`, `vdgg_task_gate` = allowlist check + verification command + gate file, `vdgg_task_rollback` restores from baseline.
- Tests: per-script suites source `lib/assert.sh`, build temp repos, pipe synthetic hook JSON into hooks, assert exit codes/messages.

## 3. Impact surface

- Verified-gate change touches pretool + posttool + state helpers + SKILL.md + state_helpers.md/hook_rules.md + tests (test-hook-pretool.sh, test-state.sh).
- Allowlist port adds 2 state-file fields (`task_allowlist_file`, `task_base_ref`) — matches Codex edition, realigning the editions; state_helpers.md format section must be updated; existing tests that assert exact state-file contents may need updates.
- Plugin packaging adds files only; hook script paths inside `hooks/hooks.json` use `${CLAUDE_PLUGIN_ROOT}`; manual install path must keep working (setup.md keeps settings.json instructions as the alternative).
- SKILL.md source-path snippets change from hardcoded `$HOME/.claude/skills/...` to a `VDGG_SKILL_DIR` resolver (needed for plugin cache installs). Hook declaration validation is unaffected (it checks step declarations, not paths).

## 4. Prior similar implementations

- v1.7.1 `_vdgg_ensure_gitignore`: idempotent, marker-comment guarded, skips when no .gitignore — port as-is.
- v1.7.1 SKILL.md sections to port: lightweight-mode version-bump obligation; "branch name MUST describe the change"; stay-on-feature-branch Step 1 snippet (also removes the `<type>/<kebab-case-slug>` literal-checkout footgun in the 0.2.0 snippet); simplify subagent consolidation; severity-based findings response (followup-r files).
- v1.7.1 jq fallback grep parser: reuse the extraction idea for fail-open cwd lookup, but DO NOT port the background `brew install jq` auto-run (runs a package manager without consent).
- Codex edition `vdgg_task_*`: port with `.codex` → `.claude` path swaps and `/\.codex\/\.vdgg-/d` filter → `.claude` equivalent.

## 5. Side effects and risks

- Making `vdgg_task_begin` mandatory for implementation edits is a behavior change for existing users → version bump + CHANGELOG entry; SKILL.md instructs the new call so agents adapt automatically.
- Blocking direct sentinel writes could break the undocumented heredoc fallback some sessions may have relied on → replaced by `vdgg_review_run`/`vdgg_state_mark_reviewed`, documented.
- Sentinel-write blocking must not block the helpers themselves: helpers build paths at runtime, so command text never contains the literal sentinel path; only literal-path writes are blocked.
- jq fail-open must not weaken active sessions: fail open ONLY when no `.vdgg-active` can be located via the fallback parser; otherwise keep fail-closed with install hints.
- CI: GitHub runners need jq (ubuntu has it preinstalled; add an install step for safety on both OSes).

## 6. Constraints

- No new external dependencies; bash + jq only (jq with fail-open fallback).
- Keep step numbers, phase names, helper API names; state file gains fields only (matching Codex edition).
- Do not modify `~/.claude/skills/vibesdegogo` (live copy) or the other two repos in this session.
- branch-pr: PR at the end, no merge.

## 7. Verification strategy

- Per task: `bash -n` on changed scripts; `bash tests/run-all.sh` green.
- New tests: review-sentinel accepted at verified; sentinel forgery (Edit/Write + Bash heredoc) blocked; allowlist blocks out-of-list edit in implementing; gate file required at verified when allowlist exists; jq-missing + inactive → exit 0; jq-missing + active → exit 2.
- Plugin: validate JSON files with jq; path references resolve within repo.
- Docs: README.ja.md mirrors README.md sections; CHANGELOG updated; version bumped to 0.3.0.

Unknowns: exact `plugin.json`/`marketplace.json` schema details — to be verified against official docs before T7 (plugin packaging task).
