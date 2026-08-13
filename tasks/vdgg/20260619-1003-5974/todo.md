# Todo: Step 0 GrillMe Integration

## T1: for-Claude-Code SKILL.md に GrillMe セクション追加 + target_schema.md に GRILLME キー追加

- 対象ファイル: `skills/vibesdegogo/SKILL.md`, `skills/vibesdegogo/references/target_schema.md`
- 内容:
  - SKILL.md 行164の直後（Consultation セクション末尾）に `## Step 0 Helper: Grill Me (optional)` を新設
  - target_schema.md 行33-35の間に `GRILLME=on|off|auto` 設定例とコメントを挿入
- 検証: `bash -n` で scripts/*.sh をクリーン確認、SKILL.md を読み直して文章整合性
- 完了条件: 2ファイル編集、MAGI セクション無変更、未インストール graceful skip が明文化

## T2: for-Codex SKILL.md に GrillMe セクション追加（inline schema 含む）

- 対象ファイル: `.agents/skills/vibesdegogo/SKILL.md`
- 内容:
  - 行77の直後に同等の `## Step 0 Helper: Grill Me (optional)` を新設
  - Codex 版は target_schema.md が無いため、新セクション内に `.vdgg-target` の GRILLME 記述を inline で含める（Codex 版が REVIEW_COMMAND 等を inline で書いているパターンに合わせる）
- 検証: `bash -n` で `.agents/skills/vibesdegogo/scripts/*.sh` クリーン、SKILL.md を読み直して文章整合性
- 完了条件: 1ファイル編集、Codex 流の inline schema 表現、MAGI セクション無変更

## T3: 両リポで commit + push + PR 作成

- 対象: T1, T2 完了後
- 内容:
  - for-Claude-Code: 既に branch `feat/step0-grillme-toggle` 作成済み。commit + push + `gh pr create`
  - for-Codex: branch `feat/step0-grillme-toggle` 新規作成。commit + push + `gh pr create`
- 検証: 両 PR URL を取得して報告
