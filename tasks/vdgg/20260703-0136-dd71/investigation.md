# Investigation — Formation (executor tiers)

## 作業リポジトリの確定

- 当初 `tmknzz/VibesDeGoGo`（旧モノレポ、削除予定）で着手したが、委譲機構（EXECUTOR系キー）は存在しなかった。正本は `VibesDeGoGo-for-Claude-Code`。作業をこちらへ移し、旧モノレポ側の痕跡（state・branch・.gitignore差分）は原状復帰済み。
- `VibesDeGoGo-for-Codex` を rg で確認: SKILL.md に EXECUTOR 機構なし（ヒットは CHANGELOG とタスクノートのみ）。**Formation は Claude Code edition 限定**とし、CHANGELOG にその旨を記す。dist リポジトリに edition_parity.md は存在しないため、parity 文書更新の義務はない。

## 既存の委譲機構（変更対象の現状）

- `skills/vibesdegogo/SKILL.md:29-31`「Delegated step executors」: `STEP3/4/6_EXECUTOR_COMMAND` が設定されたステップは、`references/subagent_prompts.md` のプロンプトで外部コマンドを実行し、成果物（ファイル存在＋見出し）をエージェント自身が検証する。Step 6 はタスク許可リストと `vdgg_task_gate` が引き続き適用される。**executor の実行はエージェント主導（hookは関与しない）**。
- `references/target_schema.md:41-49`: `.vdgg-target` の executor キー定義。`REVIEW_COMMAND`（:35-39）は `vdgg_review_run`（`scripts/vdgg-state.sh:424` 付近）が読む。
- `references/subagent_prompts.md:47-60`「Step 6 Implementation Subagent」: 入力は requirements / investigation / todo / current_task の4パス。失敗調査ノートを渡す口は現状ない。
- `vdgg_task_rollback`: SKILL.md Step 7 に記載あり。昇格時の基線復帰にそのまま使える。
- loop カウント: 検証失敗→reflection→`vdgg_state_loop 6 implementing` で loop が増える。「2回目の失敗で昇格」は「loop=2 となる再実装から上位tierが担当」と定義できる（state形式の変更不要、tierは progress.md 記録）。

## 変更方針

hook・state file・スクリプトは一切触らない。変更は仕様文書3ファイル＋CHANGELOG のみ:

1. `references/target_schema.md` — `STEP6_EXECUTOR_TIERS` キー追加（`|` 区切り・安い順・終端 `inline` 予約語・未設定時は従来動作・`STEP6_EXECUTOR_COMMAND` との優先関係を明記）。
2. `skills/vibesdegogo/SKILL.md` — 「Delegated step executors」に Formation 小節を追加: tier1開始、昇格則（loop=2で上位tier・rollback・investigation-r*.md引き継ぎ）、レビュー順序（テスト通過後のみ・差し戻しはまず同tier適用・再差し戻しで昇格）、重量級タスクの上位tier開始ガイドライン（契約変更・複数モジュール横断・並行処理・セキュリティ）、progress.md 記録と完了報告1行サマリの形式。
3. `references/subagent_prompts.md` — Step 6 プロンプトに任意入力 `failure notes`（investigation-r*.md のパス）を追加。

## Standard-First 確認

既存のカスタム実装の置き換え対象なし。追加はすべて既存の `.vdgg-target` 拡張パターンの範囲内で、新規スクリプト・依存追加なし。

## 未知・リスク

- `STEP6_EXECUTOR_COMMAND` と `STEP6_EXECUTOR_TIERS` が両方設定された場合の優先順位は仕様で決める必要がある → TIERS を優先し、COMMAND は「TIERS が1段だけの糖衣」と等価と定義する（後方互換維持）。
- テストはドキュメント変更の影響を受けない見込みだが、`tests/run-all.sh` を回して確認する。
