## Goal

`tmknzz/VibesDeGoGo-for-Claude-Code` PR #6 と同等の Step 0 GrillMe 組み込みを Codex エディションに反映する。3層構造 (浅い壁打ち → GrillMe → MAGI → drafting) と `GRILLME=on/off/auto` トグルを Codex 版 SKILL.md に追加。Codex 版は `references/target_schema.md` を持たず schema は SKILL.md 内に inline 記述する慣習に従う。

## Constraints

- standard-first: Codex 版の既存 inline schema パターン (REVIEW_COMMAND / STEP*_EXECUTOR_COMMAND が SKILL.md に直書き) に揃える。
- 既存 `.vdgg-target` 後方互換。`GRILLME` 未設定時 = `off` 扱い。
- 未インストール検出時は graceful skip。
- MAGI 行 (Consultation step 4) 無変更。
- 対象は `.agents/skills/vibesdegogo/SKILL.md` のみ (Codex 版は schema 別ファイルなし)。
- for-Claude-Code PR #6 の文言と意味的に揃え、エディション固有の差分のみ反映。

## Acceptance criteria

1. `.agents/skills/vibesdegogo/SKILL.md` の Step 0 Consultation 直後に `## Step 0 Helper: Grill Me (optional)` を新設。
2. 同セクション内に `.vdgg-target` の `GRILLME` schema 説明を inline で含める (Codex 版の既存パターンに合わせる)。
3. for-Claude-Code 側と意味的に同一の挙動 (`off`/`on`/`auto`、未インストール graceful skip、MAGI escalation を後ろに置く順序) を表現。
4. MAGI 行 (line 75 付近) 無変更。
5. `bash -n` で `.agents/skills/vibesdegogo/scripts/*.sh` クリーン (触らない予定)。
6. ブランチ `feat/step0-grillme-toggle` で PR 作成。
