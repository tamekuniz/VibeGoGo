# Requirements — Formation (executor tiers)

## Goal

VDGG（Claude Code edition）の委譲実行機構に「Formation」を追加する。実装ステップ（Step 6）の実行者を安い順のtier階層として `.vdgg-target` の `STEP6_EXECUTOR_TIERS`（1行）で宣言できるようにし、タスクごとに最も安いモデルで決着させることを自動化する。

- 宣言形式: `STEP6_EXECUTOR_TIERS="<cmd1>|<cmd2>|inline"`。`|` 区切りで安い順。終端の `inline` は「オーケストレーター本体が直接実装する」を意味する予約語。
- タスクは原則 tier1 から開始する。
- 昇格則: 同一タスクの1回目の検証失敗は同tierのまま reflection → 再実装。2回目の失敗（loop=2到達）で上位tierへ昇格する。昇格時は `vdgg_task_rollback` で基線に戻し、上位tierはクリーンに再実装する。ただし investigation-r*.md（失敗の調査ノート）は次tierのプロンプトに引き継ぐ。
- レビュー順序: 外部レビュー（REVIEW_COMMAND）はテスト（vdgg_task_gate）通過後にのみ実行する。レビュー差し戻しは、まず同tierが指摘を適用する。再差し戻しで上位tierへ昇格する。
- 例外則: 明白に重いタスク（API・永続化などの契約変更、複数モジュール横断、並行処理・セキュリティに関わる変更）は、オーケストレーター判断で上位tierから開始してよい。判断基準の例をSKILL.mdに明記する。
- 実績記録: タスクごとの決着tier・loop数を progress.md に記録し、完了報告に1行サマリ（例: `T1: tier1で完決` / `T2: tier2に昇格して完決`）を出す。

スコープ外（v1に含めない）: 実績データに基づく初期配置の学習・自動調整。新モデルの自動ベンチマーク・自動昇格。Step 3/4 executor のtier化（既存の単一 `STEP3/4_EXECUTOR_COMMAND` のまま）。Codex edition への移植（executor機構の有無を調査し、無ければ本件はClaude Code edition限定とし、parity文書に差分として記録する）。

## Constraints

- `STEP6_EXECUTOR_TIERS` 未設定時の動作は現行と完全に同一（offデフォルト）。既存の `STEP6_EXECUTOR_COMMAND` の意味・優先順位を壊さない。
- hook・state file形式・Step遷移契約は変更しない。tierの現在値はhookで強制せず、progress.md 上のオーケストレーター記録として持つ。
- モデル名・ベンダー名をスキル本体にハードコードしない（設定例としての記載は可）。
- 外部依存を追加しない。
- Step 1, 2, 5, 8, 9 の非委譲は維持する。
- エディション間差分は edition parity の規約（該当文書があればそれ）に従って記録する。

## Acceptance criteria

1. `.vdgg-target` に `STEP6_EXECUTOR_TIERS` を1行書くだけでFormationが有効化されることが target_schema.md に定義されている。
2. 昇格条件（loop=2で昇格・rollback・調査ノート引き継ぎ・レビューはテスト通過後のみ・差し戻しはまず同tier適用）がSKILL.mdに明文化されている。
3. `STEP6_EXECUTOR_TIERS` 未設定時の記述上の動作が現行と同一である（既存記述の意味変更なし）。
4. 決着tierの progress.md 記録形式と完了報告の1行サマリ形式が定義されている。
5. 重量級タスクを上位tier開始できる例外則が、判断基準の例示付きでSKILL.mdにある。
6. `bash -n`（スクリプト変更時）と `rg` による整合チェック（キー名の全記載箇所の一致、既存テストの通過）が通る。
