# Followup candidates (low-severity simplify findings, not applied)

## From T2 (review gate)

1. severity=low — `vdgg-hook-posttool.sh` testing-phase loop: the `.claude/.vdgg-` and tasks-dir exclusion checks are loop-invariant; hoist them above the two-sentinel `for` loop (saves 2 glob matches per Edit/Write during testing, flatter control flow). May be naturally subsumed by T3's posttool edits.
2. severity=low — `tests/test-hook-pretool.sh` / `tests/test-hook-posttool.sh`: three identical review-sentinel heredoc fixtures; extract a `write_review_sentinel <modified>` helper next to `write_state`.
3. severity=low — `references/hook_rules.md` Review Gate section: add a one-line cross-reference marking hook_rules.md as the authoritative gate spec and SKILL.md Step 7 as user-facing instruction, to prevent doc drift.

Skipped (judged false positive): sharing sentinel-path/field helpers between vdgg-state.sh and the hooks — hooks are deliberately standalone (no sourcing of the state script), and sourcing would couple them to `VDGG_CWD` resolution at hook time.

## From T4 (jq fail-open)

5. severity=low — pretool: extract a `GIT_COMMIT_PATTERN` variable for the three near-identical `git commit` regexes (pre-existing pattern, not introduced by T4).
6. severity=low — pretool/posttool: a `_vdgg_state_get` mini-helper could halve the `grep|cut` state-parsing boilerplate (pre-existing).
7. note — jq-missing fallback duplication across pretool/posttool is intentional (standalone hooks); update both in lockstep when the install-command pattern changes.

## From T6 (review/executor options)

8. severity=low — `vdgg_review_run`'s REVIEW_COMMAND extraction handles double quotes only; VERSION_FILE parsing also strips single quotes — align the idioms (or extract a shared `.vdgg-target` field reader in vdgg-state.sh).
9. severity=low — target_schema.md: add one sentence each clarifying (a) Steps 3/4 artifact structure is validated by agent inspection, not hooks; (b) `{PLACEHOLDERS}` are agent-substituted, not env vars/shell-expanded.

## From T7 (plugin packaging)

10. severity=low — narrow hook matchers from `""` to the tools the scripts actually inspect (PreToolUse: `Bash|Edit|Write|Agent`; PostToolUse/Failure: `Bash|Skill|Edit|Write`) in BOTH hooks/hooks.json and setup.md's settings.json snippets, plus a note that matchers and script case-statements must stay in lockstep. Saves two process spawns per read-only tool call.
11. severity=low — test-plugin-manifests.sh: add a cross-check that hooks/hooks.json and setup.md reference the same script set (rename/split drift guard).
12. severity=low — marketplace.json plugin entry description: align wording with plugin.json ("for Claude Code").
