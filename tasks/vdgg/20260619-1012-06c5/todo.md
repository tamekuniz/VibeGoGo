# Todo

## T1: SKILL.md に GrillMe セクション (inline schema 含む) を追加

- 対象: `.agents/skills/vibesdegogo/SKILL.md`
- 内容: 行77直後 (Consultation 末尾) に `## Step 0 Helper: Grill Me (optional)` 新設。本文 + inline `.vdgg-target` GRILLME schema。
- 検証: `bash -n` で `.agents/skills/vibesdegogo/scripts/*.sh` クリーン。MAGI 行 (line 75) と既存 inline schema (lines 260-272) 無変更。
