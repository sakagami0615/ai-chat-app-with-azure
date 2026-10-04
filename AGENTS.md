# AGENTS.md - AI Agent Rules

このファイルは、リポジトリ内の実装・編集で常に適用するルールだけを定義します。確定仕様や設計の詳細は、作業内容に応じて下記の文書を必ず参照してください。

## 文書の参照順序

- 機能要件、MVPの範囲、受け入れ条件: [`docs/project-specification.md`](docs/project-specification.md)
- Azure構成、データフロー、運用構成: [`docs/architecture.md`](docs/architecture.md)
- 未決定で判断が必要な項目: [`docs/open-questions.md`](docs/open-questions.md)
- 将来構想と段階的な拡張: [`docs/roadmap.md`](docs/roadmap.md)
- 重要な設計判断とその理由: [`docs/decisions/`](docs/decisions/)

仕様・設計・ロードマップが矛盾する場合は、確定仕様とADRを優先し、未決事項や将来構想を確定要件として実装しない。判断を追加した場合は、該当文書を同じ変更で更新する。

## 命名規則

- Python: `snake_case`
- Streamlitの画面・クラス: `PascalCase`
- Pythonの関数・変数: `snake_case`
- Terraform、Docker、設定ファイル: `kebab-case`または既存ツールの標準形式
- 自前のPythonパッケージに、依存ライブラリと同じトップレベル名（`azure`、`openai`、`streamlit`など）を付けない

## 技術・構成の制約

- MVPのUIと実行基盤はStreamlitとAzure App Serviceを使用する。MVPでは別のFastAPI API層を追加しない。
- Pythonは3.14を使用し、依存関係・Dockerイメージ・Terraform providerのバージョンを固定する。
- LLMはAzure OpenAI、RAG検索はAzure AI Search、文書保管はBlob Storage、履歴はCosmos DBを使用する。
- AzureリソースはDevとProdを分離し、Terraformで再現可能にする。
- 通常チャットとRAGチャットを明示的なモードとして扱い、通常チャットでは文書検索を実行しない。

## セキュリティと認証

- 秘密情報、APIキー、接続文字列、実値を含む`.env`をGitへ保存しない。`.env.example`には項目名だけを記載する。
- Azure SDKの認証は`DefaultAzureCredential`に統一する。ローカルはAzure CLI、Azure上はManaged Identityを使用する。
- Azure上のアクセスはManaged Identityと最小権限RBACを優先する。
- ログへプロンプト本文、回答本文、機密情報を保存しない。
- MVPは機密情報を扱わない検証データを前提とし、認証なしの環境を一般公開しない。Azure上のApp ServiceはEasy Authでアクセスを制限する。

## 実装・品質ルール

- 429、タイムアウト、Azureサービス障害には限定回数の指数バックオフ付きリトライと、相関ID付きのユーザー向けエラーを実装する。
- 外部サービスへのアクセスは、UI処理、Azure接続、RAG、永続化、設定の責務を分離する。
- 単体テストではAzureサービスをモックし、Azure統合テストは手動またはスケジュール実行とする。
- 変更前に関連する仕様・ADRを確認し、変更後は仕様、テスト、ドキュメントの整合性を検証する。
