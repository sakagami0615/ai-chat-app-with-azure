# Azure AI Chat Project Specification

## 1. 目的と対象利用者

Azure上で、Azure OpenAIを利用した堅牢で拡張可能なAIチャットアプリケーションを構築する。MVPは開発者個人の検証用途を対象とし、将来的に社内ユーザーへ拡張する。

## 2. MVPの範囲

MVPには次を含める。

- StreamlitによるチャットUI
- Azure OpenAIによる通常チャット
- Azure OpenAIのストリーミング応答
- Cosmos DBへの会話履歴の保存、復元、会話単位の削除
- Blob Storage上のPDF、Markdown、TXTを対象としたRAG
- 取り込みスクリプトによる文書の分割・埋め込み・インデックス登録
- Azure AI Searchのハイブリッド検索・セマンティックランカーによる文書検索と引用元表示
- App Service組み込み認証（Easy Auth）によるDev環境のアクセス制限
- 429、タイムアウト、サービス障害への限定回数リトライとエラー表示
- ローカル実行とDev環境での動作確認
- TerraformによるAzureリソースの再現

MVPでは、アプリケーション内のログイン処理、ユーザー・グループ単位の権限管理、管理画面、Private Endpoint、自動RAG判定、インデクサーによる文書の自動同期、Prod環境の構築を実装しない。

## 3. チャットモード

### 3.1 通常チャット

初期状態は通常チャットとする。通常チャットではAzure AI Searchを呼び出さず、ユーザー入力と会話コンテキストだけをAzure OpenAIへ渡す。

### 3.2 RAGチャット

ユーザーが文書検索モードを選択した場合だけ、Azure AI Searchでハイブリッド検索（キーワード＋ベクトル）を行い、セマンティックランカーで再順位付けした上位5件を回答生成へ渡す。

根拠の有無はセマンティックランカーの`@search.rerankerScore`（0〜4）で判定する。閾値以上の結果が1件もない場合は、根拠が文書から確認できないことを明示し、根拠のない回答を生成しない。閾値は設定値とする。

モード変更時は新しい会話を開始する。各会話には利用モードを記録する。将来、自動判定を追加する場合も判定結果をユーザーに表示し、手動で切り替えられるようにする。

### 3.3 引用

RAG回答には、文書名、ページ番号（PDF）またはセクション名（Markdown）、チャンク識別子を表示する。文書へのリンク表示は、提供方法が決まるまでMVPの必須要件としない。

検索チャンクには文書ID、ファイル名、ページ番号、セクション名、更新日時を保持する。

### 3.4 文書の取り込み

文書の取り込みは、リポジトリ内のPython取り込みスクリプトで行う。スクリプトはBlob Storage上の文書を読み込み、形式ごとに分割し、Azure OpenAIの埋め込みモデルでベクトル化して、Azure AI SearchのPush APIでインデックスへ登録する。

- PDF: ページ単位で抽出し、ページ内を段落優先で分割する。チャンクにページ番号を付与する。
- Markdown: 見出し単位で分割し、チャンクに見出し階層をセクション名として付与する。
- TXT: 段落優先で分割する。ページ番号とセクション名は持たない。

Blob Storageから削除された文書のチャンクは、スクリプト実行時にインデックスから削除する。スクリプトは冪等とし、同じ文書を再実行しても重複チャンクを作らない。

## 4. 履歴とデータ保持

会話とメッセージを分離してCosmos DBへ保存する。MVPでは固定の開発者IDを所有者識別子として利用し、将来Entra IDのユーザーIDへ置き換えられる構造にする。

保持期間は設定可能とし、初期値は90日とする。ユーザーは会話単位で履歴を削除できる。

## 5. 技術仕様

- Python 3.14
- Streamlit
- Azure OpenAI（チャットモデル、埋め込みモデル）
- Azure AI Search（ハイブリッド検索、セマンティックランカー）
- Azure Blob Storage
- Azure Cosmos DB
- Azure App Service（Dockerコンテナ、組み込み認証）
- Azure Container Registry
- Azure Key Vault
- Application Insights
- Terraform
- GitHub Actions

依存関係、Dockerイメージ、Terraform providerのバージョンを固定する。StreamlitおよびAzure/OpenAI SDKを含む依存関係がPython 3.14に対応していることをCIで検証する。

## 6. 認証・設定・環境

Azure SDKの認証には`DefaultAzureCredential`を使用する。ローカルでは`az login`によるAzure CLI認証、Azure上ではApp ServiceのManaged Identityを使用する。

Dev環境のApp ServiceはEasy Auth（Microsoft Entra IDプロバイダー）を有効にし、未認証リクエストをログインへリダイレクトする。アクセスは許可したアカウントだけに限定する。アプリケーションはEasy Authの認証情報を所有者識別子に使わず、MVPでは固定の開発者IDを使い続ける。

DevとProdはAzureリソースを分離する。Pull RequestではTerraformのformat、validate、planを実行し、`main`へのマージでDevへ適用する。ProdはTerraformの定義とplanまでをMVPの範囲とし、applyはMVP完了後に行う。Prodのapplyは、GitHub ActionsのEnvironment承認を経てから実行する。Terraform stateは専用Azure Storage AccountのBlob backendに保存し、ロックを有効化する。

Azure OpenAI、AI Search、Cosmos DB、Blob StorageはAPIキーや共有キーによる認証を無効にし、Entra IDとRBACだけでアクセスする。ロールは最小権限で割り当て、Terraformで管理する。割り当ての一覧は`docs/architecture.md`に記載する。

`.env.example`には設定項目だけを記載し、実値を含む`.env`はGit管理対象外とする。MVPの秘密情報は、Easy Auth用Entra IDアプリ登録のクライアントシークレットだけとする。このシークレットはKey Vaultへ保存し、App ServiceのKey Vault参照で読み込む。

## 7. エラー処理と監視

429、タイムアウト、Azure OpenAIまたは関連サービスの一時障害には、限定回数の指数バックオフ付きリトライを行う。最終的に失敗した場合は、ユーザー向けに原因に応じたメッセージを表示し、相関IDを示す。

ストリーミング応答のリトライは、最初の応答チャンクを受信する前の失敗だけを対象とする。受信開始後にストリームが途切れた場合は自動でリトライせず、部分回答に中断したことを示すエラーと相関IDを添えて表示する。中断したやり取りは履歴へ保存しない。

Application Insightsにはリクエスト時間、成功・失敗、429、タイムアウト、検索件数、相関IDを記録する。ログ保持期間は30日とし、プロンプト本文と回答本文は保存しない。OpenTelemetryなどの自動計測で本文が記録される設定は、明示的に無効にする。連続エラー、429急増、タイムアウト急増、App Service停止をアラート対象とする。

## 8. テストとMVP完了条件

設定読み込み、リトライ・タイムアウト、ストリーミング中断時の処理、履歴の保存・取得・削除、文書の分割とメタデータ付与、RAG検索結果の整形と閾値判定、プロンプト組み立てを単体テストする。通常のCIではAzureサービスをモックし、Azure統合テストは手動またはスケジュール実行とする。

MVPは次をすべて満たした時点で完了とする。

- 通常チャットとRAGチャットが切り替えられる
- 通常チャットで不要な文書検索を行わない
- 取り込みスクリプトで登録した文書を検索でき、ページ番号またはセクション名付きの引用が表示される
- 閾値以上の検索結果がない場合に、根拠がないことを明示して回答を生成しない
- ストリーミング応答、履歴の保存・復元・削除が動作する
- 429、タイムアウト、サービス障害が制御された形で処理される
- ローカルとDev環境で動作確認できる
- `main`へのマージで、アプリケーションのイメージがDev環境へデプロイされる
- Dev環境に、Easy Authで許可されたアカウント以外がアクセスできない
- TerraformでDev環境を再構築でき、Prod環境のplanが成功する
- 単体テストとCIが成功する
- 秘密情報がGitに含まれておらず、Application Insightsにプロンプト本文と回答本文が記録されていない
