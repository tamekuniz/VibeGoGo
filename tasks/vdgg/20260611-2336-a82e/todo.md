# Todo

- [ ] C1: State/gate parity back-port — `vdgg_state_write` optional args 5/6 + `-` clear; 8→5 branch (loop reset + task-field clear); `vdgg_task_begin` single write; `vdgg_task_changed_files` stored-base-ref + `tasks/vdgg/` exemption; pretool allowlist task-notes exemption; tests.
- [ ] C2: Sentinel protection + posttool tracking — generalize sidecar write-protection to `.codex/.vdgg-*` (Edit/Write/apply_patch + Bash writes); posttool flips review sentinel on Edit/Write too (with sidecar/task-notes exclusions); tests.
- [ ] C3: jq fail-open when inactive — pretool extracts cwd via grep fallback + git toplevel, exits 0 without an active session; active stays fail-closed with multi-distro hints; tests.
- [ ] C4: review_run + gitignore + SKILL.md docs — `vdgg_review_run`; `_vdgg_ensure_gitignore` (`.codex/.vdgg-*`); SKILL.md documents REVIEW_COMMAND, STEP3/4/6_EXECUTOR_COMMAND, `[Error Acknowledged]`, rollback recovery; tests.
- [ ] C5: CI + READMEs — `.github/workflows/test.yml`; README guardrail wording check; README.ja.md.
- [ ] C6: CHANGELOG 0.3.0 + SKILL.md version bump.
