# Progress: Step 0 GrillMe Integration

## Tasks (this session: for-Claude-Code only)

- [x] T1: for-Claude-Code SKILL.md + target_schema.md 編集
  - `skills/vibesdegogo/SKILL.md`: Step 0 Consultation の直後に `Step 0 Helper: Grill Me (optional)` を新設。3層構造、`GRILLME=on/off/auto`、未インストール時の graceful skip を明文化。MAGI 行 (Consultation step 4) は無変更。
  - `skills/vibesdegogo/references/target_schema.md`: TEST_COMMAND_PATTERN と REVIEW_COMMAND の間に `GRILLME=auto` を例示。コメントで挙動説明。

## Verification

- `bash -n` clean (scripts/*.sh 4本)
- `vdgg_task_gate` passed (allowlist 内のみ変更)
- 整合性: SKILL.md の見出し数 27、新セクション挿入位置正しく Consultation 直後

## Followup (separate session)

- T2/T3: `tmknzz/VibesDeGoGo-for-Codex` 側に同等変更を別 VDGG セッションでミラー実施
