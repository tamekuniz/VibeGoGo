# Changelog

This project follows the structure of Keep a Changelog:
https://keepachangelog.com/en/1.1.0/

## [Unreleased]

### Added

- Codex edition smoke tests (`tests/test-codex-state.sh`) covering init,
  advance, loop, mark_reviewed, clear, and the re-init refusal path.
- README install hints for `jq` on macOS, Debian/Ubuntu/WSL, Alpine, and
  Fedora/RHEL.
- `vdgg_state_mark_reviewed` is now listed in `references/state_helpers.md`
  as an auxiliary review marker for environments without the `simplify` skill.

### Fixed

- Reflection gate now works on Linux. The pretool hook used the BSD-only
  `stat -f %m` for retry investigation/progress mtime checks, which silently
  returned 0 on Linux and permanently blocked the Step 6 retry transition. A
  small `_vdgg_mtime` helper falls back from `stat -f %m` to `stat -c %Y` so
  the gate is correct on both macOS and Linux/WSL.
- Claude edition `vdgg_state_init` no longer silently overwrites an active
  session. It now prints a clear message with the existing id and returns 1,
  matching the Codex edition behavior.
- Codex `_vdgg_generate_id` now truncates the random component to 4 hex
  characters so ids match the documented `YYYYMMDD-HHMM-xxxx` format and stay
  in parity with the Claude edition.

### Changed

- Step 1 feature branch name is now derived from the agreed Step 0 Goal in
  `{type}/{slug}` form (e.g., `feat/japanese-readme`) instead of the
  `vibesdegogo/{id}` template. Both Claude and Codex editions of `SKILL.md`,
  and `references/target_schema.md`, were updated. Nesting on top of an
  existing feature branch is allowed; the Step 1 block runs once per session
  because `vdgg_state_init` refuses a second initialization.
- Hook `jq` missing-dependency UX is unified across Claude and Codex hooks.
  All hooks print a per-OS install hint and exit 2 (or 0 in the stop hook).
  The previous behavior that silently kicked off a background `brew install
  jq` has been removed; users now run the install command themselves and the
  pretool/posttool hooks let `brew install jq` / `apt-get install jq` /
  `apk add jq` / `dnf install jq` / `pacman -S jq` commands through while jq
  is still missing.

## [0.2.0] - 2026-05-26

### Added

- Zero-dependency bash smoke tests for state helpers and hook phase guards.
- Claude/Codex edition parity documentation.
- Contribution guide and GitHub issue/PR templates.

### Fixed

- Restored meaningful Claude hook/state script comments damaged during rename.
- Replaced the leftover legacy formation regex with `vdgg_state_*` matching.
- `PostToolUseFailure` posttool branch now honors the same `IS_SEARCH`
  exception as the standard `EXIT_CODE` branch, so search no-match (exit 1)
  from `grep`/`find`/etc. no longer raises the error-pending flag and
  blocks follow-up tools.
- Pretool's direct state-file edit guard treats fd-merge redirects
  (`2>&1`, `>&2`) as non-destructive by changing the redirect detector
  from `>` to `>[^&]`. Diagnostic commands that merely mention state-file
  paths now pass through.
- Pretool's direct state-file edit guard exempts `git commit`, so a commit
  message that legitimately mentions a state-file path is no longer
  treated as a destructive edit. Other commit-phase rules still apply.
- Posttool's testing-phase Edit/Write tracking now excludes the simplify
  sentinel itself, preventing a self-referential `modified=1` loop when
  the sentinel is created via Edit/Write (e.g. environments without the
  `simplify` Skill tool).
- Codex pretool received the same redirect and `git commit` exemptions
  for parity.

## [0.1.0] - 2026-05-25

### Added

- VibesDeGoGo! for Claude Code.
- VibesDeGoGo! for Codex.
- Branch/PR workflow defaults.
- Reflection loop and verification gates.
- Self-maintenance and lightweight mode documentation.
