# ChatGPT 6 Pro + Qwen + Codex

`VDGG_FORMATION=chatgpt-qwen` をStep 0より前に指定する。調査(3)、計画(4)、振り返り(6R)、レビュー(7)は通常Chatの6 Pro、実装(6)は既存の`qwen-coder`、残りは`primary`。Codexのモデルは変更しない。節約重視なら開始時にTerraを選ぶ。Chatの制限は残り、消費削減率は保証しない。

## 初回設定

`codex-with-chatgpt`スキルで**対象workspaceだけ**を接続する。別workspaceの接続を流用しない。Qwenは既存のllama-server設定と認証を使い、`/v1/models`と実生成でモデルを確認する。

この参照ファイルと`vdgg-exec-chatgpt.py`、`vdgg-chatgpt-bridge.mjs`をインストール先VDGG skillの同じ相対位置へコピーする。`vdgg-exec-chatgpt.py`は実行可能にする。信頼済み設定ディレクトリに新規ファイルを追加する（同名が既にあれば比較してから変更）。

`~/.config/vdgg/executors/chatgpt-web.conf`:

```text
COMMAND=/absolute/installed/skill/scripts/vdgg-exec-chatgpt.py
```

`references/chatgpt-qwen.conf`を`~/.config/vdgg/formations/chatgpt-qwen.conf`へコピーし、`vdgg_formation_preflight chatgpt-qwen`を実行する。既存`chatgpt`（手動clipboard）は変更しない。ホストはこの参照を必ず読む。

## ホストがChatGPT executorを処理する手順

1. `c2c doctor -w <workspace> --json`が正常であること、保存済みの接続名/Project/Chat対応を確認する。`VDGG_CHATGPT_WORKSPACE`はそのworkspaceの絶対パス。入力artifactをその配下の許可されたファイルへ書く。コード・diff・ログはChatへ貼らない。
2. `vdgg_executor_run STEP_4_AI <input> <new-output>`等を、短くyieldするシェルツールで実行する。stdoutの`request`にあるJSONを読む。これは待機中であり、完了ではない。全Chat席に未作成のoutputを必ず渡す。状態変更のコマンドと一緒に実行しない。
3. `codex-with-chatgpt`の同じin-app browserタブで、通常Chatかつ表示モデルが**6 Pro**であることを確認する。小さな制御メッセージを送る: `[C2C] STATE: INIT`（レビューではEXECUTED）、`TASK_ID`、`ITERATION`、requestの`id`、`relative_input`、正確な接続名。workspace_infoを確認してから入力ファイルをMCPで読むよう指示する。回答には独立した行で`REQUEST_ID: <id>`、`VERDICT: PASS|FAIL|BLOCKED`と、実質的な計画またはseverity付きレビューを要求する。レビューは正しさとセキュリティを含み、high/medium指摘でFAIL。接続・モデル・根拠が不足すればBLOCKED。PASSを誘導しない。
4. 生成中は同じタブで20〜30秒ごとに軽く確認する。再送しない。回答全文をhostのローカルartifactへ保存する。入力本文をブラウザ経由で読まない。PASSの場合だけ次を実行する:

```sh
python3 /absolute/skill/scripts/vdgg-exec-chatgpt.py complete \
  --request /actual/request.json --answer /actual/observed-answer.md \
  --model '6 Pro' --chat-url 'https://chatgpt.com/c/actual-conversation-id'
```

5. 元のexecutorが終了コード0で完了したことと成果物を確認する。FAIL/BLOCKEDなら別モデルへ代替しない。待機プロセスを終了し、根拠を残して通常のVDGG reflection/修復へ進む。完了済み回答を別依頼へ再利用しない。既定待機上限は1800秒、`VDGG_CHATGPT_TIMEOUT`は1〜7200秒。
6. Step 7は実テストの`vdgg_task_gate`に加え、現行SKILLのLayer 1〜3を適用する。HQは観点ごとに別の入力・request ID・outputで上記executorを呼び、最低3回（並行性・認証等を含む変更は5回）レビューする。各回答を保存し、実際に確認したdiff範囲を`coverage`、severity付き指摘を`findings`、実施回数を`lens_count`にまとめたschema準拠JSONを作る。コード本文をChatへ貼らず、各観点の入力もMCPで読ませる。
7. `vdgg_review_run --review-output <merged.json> <review-command>`で実レビューとJSONの検証を通す。取得済みレビューなら、その入力hash・回答・実施観点・モデル表示・Chat URLを保持し、対応関係を検証するコマンドを使う。文面の存在だけをgateにしない。clean判定では別モデルによる複数観点の反証レビューを実施し、`vdgg_review_countersign --original-output <merged.json> --countersign-output <counter.json> <counter-review-command>`を通す。Qwen実装→ChatGPT主レビューの場合はCodexによる反証レビューを推奨し、同系統モデルなら保証が弱まる旨を記録する。追加レビュー分のCodex消費は残る。

この方式はCodexホストのブラウザ操作を必要とする。無人のシェルだけでは完了しない。回答の出所/モデルはホストが実UIから保証するもので、URL形式チェックによる認証ではない。待機JSONは`~/.local/state/vdgg/chatgpt/`に保存され、コード本体は含めず入力のパスとhashを持つ。ローカルの信頼済みホストに対するsandboxではない。

## Qwen実装

既存`qwen-coder`に小さな仕様・allowlist・必要なコードを渡し、**outputを指定してdiff artifactを受け取る**。ホストがパス/内容を確認し、`git apply --check --recount`後にallowlist内へ適用する。ローカルモデルのdiffを未確認で適用しない。モデルが未起動なら既存起動コマンドを使う。この機械では`~/.local/bin/qwen 27b on`、実測モデルはQwen3.8-27B / RVN-Q4_K_M-multilingual-mtp.gguf、API aliasはqwen-coder。

## 一時接続の再起動

通常はC2C標準CLIを使う。この機械で確認した一時ホスト名のOS DNS不具合が再発するときだけ、専用launcherを使用できる:

```sh
C2C_CHECKOUT="$HOME/codex-with-chatgpt" node /absolute/skill/scripts/vdgg-chatgpt-bridge.mjs /absolute/workspace
```

既存bridgeが動いていれば二重起動しない。長時間実行ツールで起動してから通常の`c2c setup`/`doctor`へ戻る。launcherはC2C 0.1.1の公開モジュール実装に依存するので、更新時に再検証する。1.1.1.1へのDNS問合せは一時URLのhealth確認だけに限定し、TLS検証とシステムDNS設定を維持する。再起動で一時アドレスが変わった場合はC2Cスキルの再接続手順が必要。ドメイン購入は不要。
