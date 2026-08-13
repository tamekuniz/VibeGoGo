# Todo — Formation (executor tiers)

Self-Maintenance Mode（計画3タスク以内）。すべて仕様文書の変更のみで、スクリプト・hook・state形式は不変更。

## T1: target_schema.md に STEP6_EXECUTOR_TIERS を定義

- 対象: `skills/vibesdegogo/references/target_schema.md`
- 内容: executor キー群の並びに `STEP6_EXECUTOR_TIERS` を追加。`|` 区切り・安い順・終端 `inline` 予約語・未設定時は従来動作・`STEP6_EXECUTOR_COMMAND` との優先関係（TIERS優先、COMMANDは1段TIERSと等価）を記述。ローカルLLM→上位モデル→inline の設定例を1つ（モデル名はプレースホルダ）。
- 検証: rg でキー名の記載を確認。既存キーの記述が不変であること（git diff 目視）。

## T2: SKILL.md に Formation 節と昇格則を追記

- 対象: `skills/vibesdegogo/SKILL.md`
- 内容: 「Delegated step executors」直後に「Formation (executor tiers)」小節を追加 — tier1開始原則、昇格則（同一タスク2回目の失敗＝loop=2の再実装から上位tier・`vdgg_task_rollback` で基線復帰・investigation-r*.md を次tierに引き継ぐ）、レビュー順序（REVIEW_COMMAND はテスト通過後のみ・差し戻しはまず同tierが適用・再差し戻しで昇格）、重量級タスク例外（契約変更・複数モジュール横断・並行処理・セキュリティは上位tier開始可）、progress.md 記録形式と完了報告1行サマリ形式。
- 検証: rg で新キー名・`vdgg_task_rollback`・`investigation-r` への言及が揃うこと。Acceptance 2,4,5 に対応する文言があること。

## T3: subagent_prompts.md の Step 6 プロンプト拡張と CHANGELOG

- 対象: `skills/vibesdegogo/references/subagent_prompts.md`, `CHANGELOG.md`
- 内容: Step 6 Implementation Subagent の Inputs に任意行 `- failure notes (optional): <investigation-r*.md paths>` を追加し、「引き継いだ失敗ノートがある場合は同じ轍を踏まないこと」を1文追記。CHANGELOG に Formation 追加（Claude Code edition 限定である旨を含む）を記載。
- 検証: `bash tests/run-all.sh` が通ること（ドキュメント変更でテスト非破壊の確認）。
