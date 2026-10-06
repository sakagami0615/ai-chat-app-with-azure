# Hello World sandbox

Issue #62 の事前検証用です。リポジトリ直下の Streamlit アプリと Dockerfile を使い、この Terraform ルートだけで Azure リソースを構築・削除します。Dev / Prod 用の Terraform や Easy Auth は含みません。

## 前提

- Azure CLI。`az login` 済みで、操作対象のサブスクリプションを `az account set --subscription <subscription-id>` で選択していること。
- Terraform **1.16.5**。AzureRM provider は **5.4.0** に固定され、`.terraform.lock.hcl` を使用します。
- 作成・削除する Resource Group、ACR、App Service Plan、Web App の管理権限、および ACR スコープで `AcrPull` を割り当てる権限。
- ACR Build を実行できる Azure 権限。ローカル Docker は任意です。
- 許可する接続元のグローバル IPv4 アドレス。IP が変わると画面にアクセスできなくなるため、VPN などの利用時は実際の送信元を確認してください。

Azure 上に B1 App Service Plan と Basic ACR を作るため、稼働中は課金されます。`make down` で専用 Resource Group を削除します。

## 設定

1. このディレクトリの `terraform.tfvars.example` を `terraform.tfvars` にコピーし、空欄を埋めます。`allowed_ip_cidr` は自分の接続元 IPv4 アドレスに `/32` を付けた値にします。`name_suffix` は英小文字と数字 4～12 文字で、ACR 名が Azure 全体で一意になる値を選びます。
2. 必要ならリージョン、App Service Plan SKU、ACR SKU を変更します。Issue #62 の検証候補は `japaneast`、`B1`、`Basic` です。Always On を使うため Free / Shared の App Service Plan は対象外です。
3. 操作するサブスクリプション ID を環境変数 `AZURE_SUBSCRIPTION_ID` に設定します。ラッパーは Azure CLI で選択されている ID と一致するか確認し、同じ ID を Terraform に渡します。

`terraform.tfvars`、state、`.terraform/`、`.env` は Git 管理対象外です。実値や秘密情報を `terraform.tfvars.example` に書かないでください。ビルド対象も `.dockerignore` でアプリ、依存定義、Dockerfile に限定します。

## 操作

リポジトリ直下で次を順番に実行します。

```bash
make up
make deploy
make down
```

`make up` は専用 Resource Group、ACR、B1 App Service Plan、Web App、Managed Identity と `AcrPull` を作成します。初期イメージはまだ ACR に存在しないため、`make deploy` までは Web App が起動しないことがあります。失敗しても自動で destroy はしません。

`make deploy` はコミット済みの作業ツリーを要求します。ACR Build にリポジトリを送信してコミット SHA のタグを付け、Web App のイメージを更新します。ACR の admin user やパスワードは使いません。イメージ取得と起動が遅い場合はヘルスチェックを最大約 5 分再試行します。ビルドまたは pull が失敗した場合は、Azure のログと `az webapp config show` の `acrUseManagedIdentityCreds` を確認して再実行します。

`make down` は local state にある sandbox を削除し、Azure CLI で専用 Resource Group の不在を確認します。apply が途中で失敗して outputs がない場合も、state に Resource Group が記録されていれば削除できます。state や `terraform.tfvars` を片付け前に失うと自動削除できないため保管してください。削除後も Resource Group が残る場合は、表示された名前を Azure CLI または Portal で確認してください。

## 受け入れ確認

- `infra/sandbox/hello-world/` で `terraform init -backend=false` の後、`terraform fmt -check -recursive`、`terraform validate`、`terraform test` が成功する。テストは mock provider を使い、Azure リソースを作成しません。
- 許可した IP から Web App URL を開き、`Hello World` が表示され、ボタンを押すと回数が増える。
- 別の接続元 IP からメインサイトと SCM サイトへのアクセスが拒否される。別 IP を用意できなければ実接続の確認は未検証と記録する。
- ACR の admin user が無効で、Web App の System-assigned Managed Identity に ACR スコープの `AcrPull` が付き、イメージが pull されている。
- `make down` 後に Resource Group と配下リソースが存在しない。
- 構築、イメージ pull、起動、片付けの所要時間、B1 での動作、失敗と対処を Issue #62 に記録する。
