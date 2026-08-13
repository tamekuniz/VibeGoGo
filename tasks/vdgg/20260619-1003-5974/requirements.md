## Goal

VDGG の Step 0 (Consultation 壁打ち) に Grill Me スキルを「3つ目の部品」として組み込む。MAGI が高ステークス分岐の合議を担うのに対し、Grill Me は「質問駆動で要件の曖昧さを潰す」役を担い、3層構造 (浅い壁打ち → GrillMe → MAGI → drafting) を作る。`.vdgg-target` の `GRILLME` キーで明示制御 (`on` / `off` / `auto`) でき、未インストールならスキップして従来動作。GrillMe をスキップしても MAGI が安全網として残るため、外しても要件品質は致命的に落ちないことを設計前提とする。

## Constraints

- standard-first: 既存の MAGI 検出ベース自動発火パターンと整合させる。MAGI セクションは触らない。
- 既存 `.vdgg-target` を壊さない後方互換。`GRILLME` 未設定時 = `off` 扱い。
- 未インストール検出時は graceful skip。MAGI も独立に検出判定するので変更不要。
- Step 0 内のみ。Step 7 やレビューゲートには関与しない (GrillMe は要件設計の道具で、コード/成果物レビュー道具ではない)。
- 対象は **配布リポ 2 つ** (`tmknzz/VibesDeGoGo-for-Claude-Code` と `tmknzz/VibesDeGoGo-for-Codex`)。旧 monorepo (削除予定) には触らない。
- コード正当性ではなく仕様文書 + 設定キー + 例の追加が主成果。スクリプトは触らない見込み。

## Acceptance criteria

両 distribution リポで以下が満たされること:

1. `skills/vibesdegogo/SKILL.md` (Codex 版は `.agents/skills/vibesdegogo/SKILL.md`) の Step 0 Consultation セクションに以下を追記:
   - 3層構造 (浅い壁打ち → GrillMe → MAGI → drafting) の説明
   - `GRILLME` キーの 3 つの挙動 (`on`/`off`/`auto`)
   - `auto` の発火条件 (MAGI escalation と同じ「曖昧 / 主観的 / 高ステークス / 複数の妥当な方向」のいずれか)
   - 未インストール時の graceful skip
   - MAGI との順序関係 (GrillMe が先、MAGI が後)
2. `references/target_schema.md` に `GRILLME=on|off|auto` キーを例とコメント付きで追加。`GRILLME=auto` を推奨例として明示。
3. MAGI セクションには変更を入れない (干渉しない設計の証明)。
4. `bash -n` で scripts/*.sh がクリーン (触っていないが念のため)。
5. 両リポで PR が作成され、ブランチ名は `feat/step0-grillme-toggle` 系で揃える。
