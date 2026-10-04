# ADR-0004: Secrets, Deployment, and Streaming Failure Handling

- Status: Accepted
- Date: 2026-10-04

## Context

仕様には「秘密情報はKey VaultまたはGitHub Secretsで管理する」とあった。しかし、Azure SDKの認証をManaged Identityに統一したため、管理すべき秘密情報が何かが不明確だった。ロードマップにも「Key Vaultの運用強化」があり、MVPでKey Vaultを使うかどうかも曖昧だった。

CI/CDはTerraformの適用だけを定義しており、アプリケーションのイメージのビルドとデプロイが未定義だった。

ストリーミング応答のリトライについては、途中まで出力した後の失敗の扱いが決まっていなかった。このままでは、リトライによる回答の重複や、不完全な回答の履歴保存が起こりうる。

## Decision

### 秘密情報

- Azure OpenAI、AI Search、Cosmos DB、Blob Storageはローカル認証を無効にし、RBACだけでアクセスする。
- MVPの秘密情報は、Easy Auth用Entra IDアプリ登録のクライアントシークレットだけとする。これをKey Vaultへ保存し、App ServiceのKey Vault参照で読み込む。アプリケーションのコードはKey Vaultへアクセスしない。

### デプロイ

- アプリケーションのイメージはGitHub Actionsでビルドし、コミットSHAをタグにしてAzure Container Registryへpushする。`main`へのマージでDevへ反映する。
- イメージのタグはアプリケーション用ワークフローだけが更新し、Terraformは`ignore_changes`で無視する。

### ストリーミング中の失敗

- リトライは、最初の応答チャンクを受信する前の失敗だけを対象とする。
- 受信開始後の中断では自動でリトライしない。部分回答とエラー、相関IDを表示し、そのやり取りは履歴へ保存しない。

## Consequences

秘密情報の保管場所が1つに定まり、アプリケーションのコードは秘密情報を扱わない。ただし、Key Vaultとクライアントシークレットのローテーションを運用する必要がある。

イメージの更新とインフラの変更が別々のワークフローで行われるため、Terraformのapplyでイメージが巻き戻ることはない。その代わり、現在デプロイされているイメージのタグはTerraform stateからは分からない。

ストリーミングの中断時に回答が重複せず、不完全な回答が履歴に残らない。一方、中断したやり取りはユーザーが再送する必要がある。
