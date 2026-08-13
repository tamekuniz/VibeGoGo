# Progress

- [x] T1: SKILL.md GrillMe セクション追加（inline schema 含む）
  - `.agents/skills/vibesdegogo/SKILL.md` 行77（Consultation 末尾）の直後に `## Step 0 Helper: Grill Me (optional)` を新設
  - 同セクション内に `.vdgg-target` の `GRILLME=on/off/auto` schema を inline 記述（Codex 版の REVIEW_COMMAND / STEP*_EXECUTOR_COMMAND と同パターン）
  - MAGI 行（旧 line 75）無変更
  - `bash -n` clean、`vdgg_task_gate` passed

## 上流 PR との関係

`tmknzz/VibesDeGoGo-for-Claude-Code` PR #6 とセマンティクス一致。差分は inline schema の置き場のみ（Claude 版は `references/target_schema.md`、Codex 版は SKILL.md 内 inline）。
