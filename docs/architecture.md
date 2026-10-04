# Architecture

## 1. 構成

```text
ユーザー
  │
  ▼
App Service組み込み認証（Easy Auth / Entra ID）
  │
  ▼
Azure App Service (Docker / Streamlit)  ◄── Azure Container Registry（イメージ取得）
  ├─ 通常チャット ──────────────────────────► Azure OpenAI（チャット）
  ├─ RAGチャット ─► Azure AI Search ────────► Azure OpenAI（チャット）
  │                 （ハイブリッド＋セマンティック）
  ├─ 会話履歴 ──────────────────────────────► Cosmos DB
  ├─ 監視・相関ID ──────────────────────────► Application Insights
  └─ Easy Authのシークレット（Key Vault参照）► Key Vault

取り込みスクリプト（手動実行）
  ├─ 読み込み ──► Blob Storage
  ├─ 埋め込み ──► Azure OpenAI（埋め込みモデル）
  └─ 登録・削除 ─► Azure AI Search（Push API）

GitHub Actions（OIDC）
  ├─ Terraform ──► Azureリソース（Dev / Prodを分離）
  └─ イメージのビルド・push ─► Azure Container Registry ─► App Serviceへ反映
```

## 2. アプリケーション境界

MVPではStreamlitをUIとアプリケーション実行基盤にする。UI処理と、Azure OpenAI、AI Search、Cosmos DB、Blob Storageへのアクセスは別モジュールへ分けるが、FastAPIなどの別API層は作らない。

想定モジュール構成は次のとおりとする。

```text
app/
├── streamlit_app.py
├── chat/
├── rag/
├── ingestion/
├── azure_clients/
├── persistence/
└── config/
tests/
infra/
docs/
```

Azure SDKの名前空間パッケージ`azure`と衝突しないよう、Azure接続モジュールは`azure_clients/`とする。`streamlit run app/streamlit_app.py`は`app/`を`sys.path`へ追加するため、`app/azure/`があると`azure.identity`などのimportが自前のパッケージへ解決されてしまう。

## 3. 認証と設定

### 3.1 Azure SDKの認証

すべてのAzure SDKクライアントは`DefaultAzureCredential`を利用する。ローカルではAzure CLI認証、App ServiceではManaged Identityを使用する。環境固有のエンドポイント、デプロイ名、保持期間、RAG検索パラメータ、検索の閾値は環境設定から読み込む。

Azure OpenAI、AI Search、Cosmos DB、Blob Storageでは、APIキーや共有キーによるローカル認証を無効にし、Entra IDとRBACだけでアクセスする。

### 3.2 Easy Auth

Dev環境のApp ServiceはEasy Authを有効にし、Microsoft Entra IDプロバイダーで許可したアカウントだけがアクセスできるようにする。設定はTerraformで管理する。アプリケーション内にログイン処理は実装しない。

### 3.3 RBAC

ロールは各環境のリソースまたはResource Groupの範囲で、最小権限で割り当てる。割り当てはTerraformで管理する。

| 主体 | 対象 | ロール |
| --- | --- | --- |
| App ServiceのManaged Identity | Azure OpenAI | Cognitive Services OpenAI User |
| App ServiceのManaged Identity | AI Search | Search Index Data Reader |
| App ServiceのManaged Identity | Cosmos DB | Cosmos DB Built-in Data Contributor（データプレーンのSQLロール割り当て） |
| App ServiceのManaged Identity | Container Registry | AcrPull |
| App ServiceのManaged Identity | Key Vault | Key Vault Secrets User |
| 取り込み実行者（開発者） | Blob Storage | Storage Blob Data Reader |
| 取り込み実行者（開発者） | Azure OpenAI | Cognitive Services OpenAI User |
| 取り込み実行者（開発者） | AI Search | Search Index Data Contributor、Search Service Contributor |
| ローカル実行する開発者（Devのみ） | App ServiceのManaged Identityと同じデータアクセス対象 | App ServiceのManaged Identityと同じロール（AcrPullとKey Vault Secrets Userを除く） |
| GitHub ActionsのOIDC ID | 環境のResource Group | Contributor、Role Based Access Control Administrator |
| GitHub ActionsのOIDC ID | Terraform state用Storage Account | Storage Blob Data Contributor |
| GitHub ActionsのOIDC ID | Container Registry | AcrPush |

Cosmos DBのデータアクセス権は、Azure RBACのロール割り当てではなく、Cosmos DBのSQLロール割り当てで付与する。

### 3.4 秘密情報

MVPでアプリケーションが扱う秘密情報は、Easy Auth用Entra IDアプリ登録のクライアントシークレットだけとする。シークレットはKey Vaultへ保存し、App Serviceのアプリ設定からKey Vault参照で読み込む。アプリケーションのコードからはKey Vaultへアクセスしない。

GitHub Actionsには、OIDC接続用のクライアントID、テナントID、サブスクリプションIDだけを登録する。これらは秘密情報ではないが、GitHub Secretsまたは環境変数で管理する。

## 4. RAGパイプライン

### 4.1 取り込み

文書はBlob Storageへ配置し、`app/ingestion/`の取り込みスクリプトでAzure AI Searchへ登録する。初期対応形式はPDF、Markdown、TXTとする。分割ルールとチャンクのメタデータは`docs/project-specification.md`の「3.4 文書の取り込み」に従う。

インデックス定義（フィールド、ベクトル設定、セマンティック設定）は、取り込みスクリプトがコード上の定義から作成・更新する。

スクリプトは文書IDとチャンク番号から決定的なチャンクIDを生成し、`mergeOrUpload`で登録する。Blob Storageに存在しない文書のチャンクは削除する。MVPではスクリプトを開発者が手動で実行し、インデクサーと管理画面は使わない。

### 4.2 検索

RAGモードのときだけ検索する。通常チャットではAI Searchへアクセスしない。

検索はキーワード検索とベクトル検索を組み合わせたハイブリッド検索とし、セマンティックランカーで再順位付けする。`@search.rerankerScore`が閾値以上の上位5件を回答生成へ渡し、1件もなければ根拠なしとして扱う。クエリのベクトル化には、取り込みと同じ埋め込みモデルを使用する。

## 5. 永続化

会話とメッセージを分離してCosmos DBへ保存する。会話には所有者識別子、モード、作成日時、更新日時を持たせ、メッセージにはロール、本文、作成日時、引用メタデータを持たせる。MVPの所有者識別子は固定の開発者IDとし、将来Entra IDのユーザーIDへ差し替える。

履歴へ保存するのは、ストリーミングが最後まで完了したやり取りだけとする。ユーザーのメッセージとアシスタントの回答は、回答の完了後にまとめて保存する。

## 6. ストリーミングとリトライ

Azure OpenAIへのリトライは、最初の応答チャンクを受信する前の失敗（429、タイムアウト、一時障害）だけを対象とする。

最初のチャンクを受信した後にストリームが途切れた場合は、自動でリトライしない。それまでに表示した部分回答に、中断したことを示すエラーと相関IDを添えて表示する。そのやり取りは履歴へ保存せず、ユーザーは同じ質問を再送できる。

## 7. 監視とログ

Application InsightsへはOpenTelemetry（Azure Monitor OpenTelemetry Distro）で送信する。生成AIの自動計測によるプロンプト本文・回答本文の記録は、次の設定で明示的に無効にする。

- `AZURE_TRACING_GEN_AI_CONTENT_RECORDING_ENABLED=false`
- `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=false`

アプリケーションのログには、本文の代わりに相関ID、モード、所要時間、トークン数、検索件数などのメタデータだけを出力する。

## 8. インフラとデプロイ

### 8.1 Terraform構成

Terraformは次の構成を基本とする。

```text
infra/
├── modules/
│   ├── app-service/
│   ├── container-registry/
│   ├── openai/
│   ├── search/
│   ├── storage/
│   ├── cosmos/
│   ├── key-vault/
│   ├── role-assignments/
│   └── monitoring/
└── environments/
    ├── dev/
    └── prod/
```

- `app-service`: App Service Plan、Web App、Easy Auth、Managed Identity、アプリ設定を含む。
- `openai`: チャットモデルと埋め込みモデルのデプロイを含む。
- `search`: セマンティックランカーを有効にする。インデックス定義はTerraformでは管理しない（4.1を参照）。
- `role-assignments`: 3.3の割り当てを管理する。

Terraform stateは専用Storage AccountのBlob backendへ保存する。

### 8.2 App Serviceの設定

Streamlitを動かすため、App Serviceに次を設定する。

- WebSocketsを有効にする
- インスタンスを2台以上にする場合は、ARR Affinity（セッションアフィニティ）を有効にする
- Always Onを有効にする
- コンテナの待ち受けポートを`WEBSITES_PORT`で指定し、Streamlitはheadlessモードで起動する
- HTTPSのみを許可する

### 8.3 CI/CD

GitHub ActionsはOIDCでAzureへ接続する。

インフラ:

- Pull Request: Terraformのformat、validate、DevとProdのplanを実行する。
- `main`へのマージ: Devへapplyする。
- MVPの期間中はProdへapplyしない。MVP完了後のProdのapplyは、GitHub ActionsのEnvironment承認を経てから実行する。

アプリケーション:

- Pull Request: lint、単体テスト、Dockerイメージのビルドを実行する。
- `main`へのマージ: コミットSHAをタグにしたイメージをContainer Registryへpushし、Dev App Serviceのイメージを更新する。

Terraformはイメージのタグを`ignore_changes`の対象にし、タグはアプリケーション用ワークフローだけが更新する。Dockerのベースイメージはダイジェストで固定する。

## 9. ローカル開発

単体テストはAzureサービスをモックする。手動確認では`az login`後にDevのAzureリソースへ接続する。設定項目は`.env.example`で示し、実値は`.env`または環境変数で与える。機密情報を含むデータはMVPの検証対象にしない。

ローカル実行ではEasy Authを経由しない。ローカルのStreamlitは`localhost`だけで待ち受け、外部へ公開しない。
