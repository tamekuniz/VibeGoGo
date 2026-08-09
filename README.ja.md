> **⚠️ このリポジトリは役目を終えており、更新されていません。**
> 内容は 2026-06-07 時点で凍結されていて、それ以降に追加された機能は入っていません。
> 現行版は
> [VibesDeGoGo-for-Claude-Code](https://github.com/tmknzz/VibesDeGoGo-for-Claude-Code)
> と [VibesDeGoGo-for-Codex](https://github.com/tmknzz/VibesDeGoGo-for-Codex) です。
> このリポジトリを現行仕様として読まないでください。

[English](README.md) | **日本語**

# VibesDeGoGo!

VibesDeGoGo! は state file と hook によるワークフローです。AI コーディングエージェントを「実際に完了するまで止めない」ように動かしながら、「制約違反の直前では必ず止める」ことを機械的に強制します。

このリポジトリには現在 2 つのエディションが含まれています:

- **VibesDeGoGo! for Claude Code:** Claude Code 用の skill と hook を `skills/vibesdegogo/` に収録（オリジナル）。
- **VibesDeGoGo! for Codex:** Codex 用の skill と hook を `.agents/skills/vibesdegogo/` に収録。グローバル hook 登録を推奨。リポジトリ用に `.codex/hooks.json` も同梱。

存在理由はシンプルです。バイブコーディング（vibe coding）は強力ですが、AI エージェントは退屈な部分 — 要件定義、調査、検証、明確な引き継ぎ — を飛ばしがちです。VibesDeGoGo! はその部分を「レール」にします。

中核となる発想:

- 進捗確認のために止めない
- 制約違反の前では止める
- 実装の前に要件を書く
- 計画の前に既存コードを調査する
- 完了の前に検証する
- state file と hook によって、プロンプト本文だけでなく機械的にワークフローを強制する

## これは何か

VibesDeGoGo! は実用的な AI コーディングセッション向けです。ユーザーが 1 回依頼するだけで、エージェントが最後までやり切ることを意図しています:

1. Goal / Constraints / Acceptance criteria を合意する
2. `requirements.md` を書く
3. コードベースを調査し `investigation.md` を書く
4. `todo.md` と `progress.md` を作る
5. 1 タスクずつ実装する
6. テストまたは他の手段で検証する
7. 失敗したら振り返り（reflection）して再試行する
8. progress とバージョンメタデータを更新する
9. commit し、必要なら push する

エージェント側は意図的に厳格、ユーザー側は軽量、という設計です。

## 主要ルール

- **進捗確認では止まらない:** エージェントは「続けてもいいですか？」で止めてはいけません。
- **制約確認では止まる:** 制約変更、依存追加、非標準実装、永続化 / API / 課金 / 分析の契約変更、セキュリティ関連の振る舞い変更、破壊的操作 — これらの直前では必ず止まります。
- **Standard-first:** プラットフォーム / フレームワークの標準コンポーネント、API、パターンを優先します。それでは不足する場合のみ、理由・代替案・影響を実装前に報告します。
- **検証必須:** テスト、ビルド検証、smoke check、または自動化できない場合は明示的な手動検証ステップを通さずにタスクを完了とマークしません。
- **push の振る舞いはワークフロー依存:** デフォルトの `branch-pr` は feature branch を push して PR を作ります。`trunk` は `.vdgg-target` で `AUTO_PUSH=true` の時だけ push します。

## モード

- **Full flow:** 通常のコーディング作業のデフォルト。
- **Self-maintenance mode:** `skills/vibesdegogo/` 配下の変更専用。VibesDeGoGo! 自身の編集を焦点絞りつつ、中核チェックは温存します。
- **Lightweight mode:** 一般プロジェクトで小さく閉じた変更向け。スコープ固定・既存パターン踏襲・依存追加なし・明示的検証を要求します。テスト 2 連敗、スコープ拡大、仕様判断が必要になった場合は full flow に昇格します。
- **Friendly completion reports:** 最終メッセージはまず平易な状態と次のアクションから始まり、Git の詳細は短い technical note として分離します。

## リポジトリ構成

```text
skills/vibesdegogo/
  SKILL.md
  scripts/
    vdgg-state.sh
    vdgg-hook-pretool.sh
    vdgg-hook-posttool.sh
    vdgg-hook-stop.sh
  references/
    setup.md
    output_formats.md
    target_schema.md
    hook_rules.md
    state_helpers.md
    subagent_prompts.md
```

## インストール: VibesDeGoGo! for Claude Code

Claude Code の skills ディレクトリに skill フォルダをコピーします:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R skills/vibesdegogo "$HOME/.claude/skills/vibesdegogo"
```

続いて、以下のドキュメントに従って hook を登録します:

```text
skills/vibesdegogo/references/setup.md
```

hook が Claude Code の hook JSON を `jq` でパースするため、`jq` が必須です。未インストールの場合は、お使いの環境に応じて以下のいずれかを実行してください:

```bash
brew install jq               # macOS
sudo apt-get install jq       # Debian / Ubuntu / WSL
apk add jq                    # Alpine
sudo dnf install jq           # Fedora / RHEL
```

## インストール: VibesDeGoGo! for Codex

リポジトリをまたいで使うには、Codex の user skill として導入します:

```bash
mkdir -p "$HOME/.codex/skills"
cp -R .agents/skills/vibesdegogo "$HOME/.codex/skills/vibesdegogo"
```

Codex は `.agents/skills` 配下のリポジトリ内 skill も読みます。開発用に本リポジトリにも同 skill が同梱されています:

```text
.agents/skills/vibesdegogo/
```

通常運用では、グローバル hook を `~/.codex/hooks.json` または `~/.codex/config.toml` に登録すると、全リポジトリで VDGG ルールが効きます。hook スクリプトは現在のリポジトリに `.codex/.vdgg-active` がなければ no-op で抜けるため、グローバル登録しても他リポジトリへの影響はありません。

本リポジトリにはプロジェクトローカルの hook 定義 `.codex/hooks.json` も同梱しています。プロジェクト hook 定義をレビュー / trust すれば使えます:

```text
.codex/hooks.json
```

Codex 内で `/hooks` を使って hook 定義を確認・trust してください。詳細はこちら:

```text
.agents/skills/vibesdegogo/references/codex-setup.md
```

Codex の hook JSON を `jq` でパースするため、`jq` が必須です。プラットフォーム別のインストールコマンドは上記 Claude Code セクションを参照してください。

## プロジェクト設定

各プロジェクトでは、必要に応じてプロジェクトルートに `.vdgg-target` を置けます。詳細はこちら:

```text
skills/vibesdegogo/references/target_schema.md
```

最も重要な任意のワークフロー項目は以下:

```bash
WORKFLOW=branch-pr
AUTO_PUSH=false
```

デフォルトの `WORKFLOW=branch-pr` では、Step 9 で feature branch を push して PR を作れる状態にします。`AUTO_PUSH=true` は `WORKFLOW=trunk` の時のみ意味を持ちます。

これは日常的な実運用から抽出された opinionated なワークフローです。汎用 CI/CD システムではありません。AI コーディングエージェント向けのガードレール付き運用手順です。
