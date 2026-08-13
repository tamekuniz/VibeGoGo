# Reflection Investigation r0 — T2 Formation節

## 根本原因

MAGI軽量議レビューゲート（第1議）で否決。原因はレビューが特定済みで、コード挙動の追跡は不要（Self-Maintenance Mode・文書変更のみのため、別途researcherサブエージェントは起動しない）。

- 否決点: `STEP6_EXECUTOR_TIERS` のラダーが予約語 `inline` で終わらない場合（例: `"<cmd1>|<cmd2>"`）、最終tierが2回目の検証失敗をした後の挙動が仕様に存在しない。
- 遡ると要件定義（requirements.md）自体が「終端は `inline`」を前提にしており、非inline終端という運用者の書き方を想定から漏らしていた。実装（T2の文面）は要件に忠実で、欠落は要件由来。

## パターン分析

仕様文書で「推奨形」だけを定義し、逸脱形の挙動を未定義のまま残す欠落パターン。VDGGは規律を機械的に強制するスキルなので、未定義挙動は品質特性に直接反する。

## 仮説（1つ）

Escalation rule 段落の末尾に「非inline終端ラダーでは、最終tierの2回目以降の失敗はescalateせず、そのtierのまま通常のreflectionループを継続する（inlineと同じ扱い）」を1文追加すれば、全ケースの挙動が定義され、MELCHIORの否決理由は解消する。

## 修正計画（1つ）

SKILL.md の `### Formation (executor tiers)` 内 Escalation rule 段落末尾に上記1文（英語・既存の文体）を追加する。他の段落・既存行は変更しない。同tier（Sonnetサブエージェント）が適用する。
