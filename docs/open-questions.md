# Open Questions

ここには、実装開始時点でまだ確定していない事項だけを記載する。確定した項目は`docs/project-specification.md`または`docs/decisions/`へ移動する。

## Azureリソースの具体値

- Dev / Prodで使用するAzureリージョン（チャットモデル、埋め込みモデル、セマンティックランカーが使えること）
- App Service、Cosmos DB、Container RegistryのSKUとスケール設定
- AI SearchのSKU（セマンティックランカーとManaged Identityが使えるBasic以上が前提）
- 各リソースの命名規則、タグ、Resource Group構成
- Terraform state専用Storage Accountの管理主体
- Easy Auth用Entra IDアプリ登録の管理方法（Terraformの`azuread` providerで作るか、手動で作るか）、許可アカウントの指定方法、クライアントシークレットのローテーション方法
- GitHub ActionsのOIDC IDに付与するRole Based Access Control Administratorの条件（割り当て可能なロールの制限）

## モデルと会話

- チャットモデルの種類、デプロイ名、APIバージョン、TPMクォータ
- 会話履歴をモデルへ渡す範囲（トークン上限と切り詰め方）
- リトライ回数、バックオフの上限、タイムアウト秒数
- Cosmos DBのパーティションキー（`ownerId`か`conversationId`か）

## RAGの詳細パラメータ

- 埋め込みモデルの種類と次元数
- チャンクの文字数・トークン数とオーバーラップ
- `@search.rerankerScore`閾値の具体値
- PDFのテキスト抽出に使うライブラリ
- 取り込みスクリプトの実行契機（手動のみか、GitHub Actionsから実行するか）
- 引用リンクの提供方法（User Delegation SASの発行、またはリンクを表示しない）

## 開発環境

- Pythonのパッケージ管理ツール（uv、pip-toolsなど）とロックファイルの形式
- lint、フォーマッター、型チェックのツール（ruff、mypyなど）

## 運用とUI

- Prodを構築する時期と、構築時のアクセス制御
- 本番公開時のドメインとTLS運用
- 日本語UIの具体的な文言とアクセシビリティ基準
- 90日保持後の削除方式（Cosmos DBのTTLを第一候補とする）
- Application Insightsの具体的なアラート閾値

## 判断期限

上記の項目は、該当する実装タスクの開始前に決定し、必要に応じてADRへ記録する。
