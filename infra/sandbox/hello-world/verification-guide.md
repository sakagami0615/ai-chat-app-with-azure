# Hello World sandbox 動作確認手順

Hello World sandbox（#62）をAzureへデプロイし、ブラウザでStreamlitのHello Worldが表示されることを確認してから、最後にすべて片付けるまでの手順です。上から順に実行します。

所要時間の目安は30〜40分です。App Service Plan（B1）とACR（Basic）は、構築してから片付けるまで課金されます。確認が終わったら、必ず「7. 片付ける」まで実行してください。

`make up`と`make down`は確認のプロンプトを出さずに、apply・destroyを実行します（`-auto-approve`）。Issue #62の要件に従い、実行前にオーナーの明示的な承認を得てください。承認を得たうえで、対象のサブスクリプションが正しいことも確認してください。承認がない場合は実行しないでください。

## 1. 準備（初回のみ）

### 1.1 ツールのインストール（Ubuntu）

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Terraformのzipを展開するためにunzipを用意する
sudo apt-get update && sudo apt-get install -y unzip

# Terraform 1.16.5（versions.tfでバージョンを固定しているため、このバージョンを入れる）
curl -sSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/1.16.5/terraform_1.16.5_linux_amd64.zip
sudo unzip -o /tmp/terraform.zip terraform -d /usr/local/bin
```

確認:

```bash
az version --query '"azure-cli"' -o tsv
terraform version     # Terraform v1.16.5 と表示される
```

Dockerは不要です。イメージはACR Buildを使い、Azure上でビルドします。

### 1.2 Azureへのログイン

```bash
az login
az account list -o table          # 使うサブスクリプションを確認する
az account set --subscription <サブスクリプションID>
az account show -o table          # 選ばれていることを確認する
```

サブスクリプションに対して、次の権限が必要です。

- Resource Group、ACR、App Service Plan、Web Appを作成・削除できる権限
- ACRのスコープで`AcrPull`を割り当てられる権限（Owner、またはUser Access Administrator）
- ACR Buildを実行できる権限

## 2. 設定する

以降のコマンドは、すべて**リポジトリ直下**で実行します。

### 2.1 terraform.tfvars

```bash
cp infra/sandbox/hello-world/terraform.tfvars.example infra/sandbox/hello-world/terraform.tfvars
curl -s https://api.ipify.org; echo    # 自分の接続元IPv4アドレスを確認する
```

`infra/sandbox/hello-world/terraform.tfvars`を開き、空欄をすべて埋めます。空文字のまま残すと、変数の既定値が使われずにエラーになります。

```hcl
location             = "japaneast"
app_service_plan_sku = "B1"
acr_sku              = "Basic"
name_suffix          = "abc123"           # 英小文字と数字4〜12文字。ACR名がAzure全体で一意になる値
allowed_ip_cidr      = "203.0.113.10/32"  # 上で確認したIPに/32を付ける
```

`terraform.tfvars`は`.gitignore`の対象なので、Gitには入りません。VPNを使っている場合は、実際の送信元IPを指定してください。

### 2.2 サブスクリプションID

```bash
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
echo "$AZURE_SUBSCRIPTION_ID"
```

ラッパー（`manage.sh`）は、この値がAzure CLIで選ばれているサブスクリプションと一致するかを確認します。一致しなければ、Azureへの操作を始める前に止まります。新しいターミナルを開いたら、もう一度設定してください。

## 3. 事前チェック（任意）

Azureに接続せずに、コードの状態を確認できます。

```bash
(cd infra/sandbox/hello-world && terraform init -backend=false && terraform fmt -check -recursive && terraform validate && terraform test)
python3.14 -m venv ~/.venvs/aichat-sandbox && ~/.venvs/aichat-sandbox/bin/pip install -r requirements.txt
~/.venvs/aichat-sandbox/bin/python -m unittest discover -s tests
```

`terraform test`はmock providerを使うため、Azureのリソースは作られません。venvをリポジトリの外に作るのは、`.venv/`がGitの無視対象になっておらず、リポジトリ内に作ると`make deploy`が未追跡のファイルを検出して止まるためです。

## 4. 構築する

```bash
make up
```

確認なしでapplyが始まります。作られるのは次の5つです。

- Resource Group（`rg-aichat-sandbox-<name_suffix>`）
- Container Registry
- App Service Plan
- Web App（System-assigned Managed Identity付き）
- AcrPullのロール割り当て

完了すると`Resource Group: ...`と`Web App: https://...`が表示されます。所要時間は3〜5分程度です。

この時点では、ACRにまだイメージがないため、Web Appは起動できません。異常ではありません。

## 5. デプロイする

`make deploy`は、未コミットの変更や未追跡のファイルがあると止まります。先に`git status`で作業ツリーがきれいなことを確認してください（`terraform.tfvars`とstateは無視されるので問題ありません）。

```bash
git status --short     # 何も表示されないこと
make deploy
```

次の順に処理が進みます。

1. ACR Buildでイメージをビルドし、コミットSHA（12文字）のタグを付ける
2. Web Appのイメージを更新する
3. ACRからのpullにManaged Identityを使う設定になっているか確認する
4. Web Appを再起動する
5. `/_stcore/health`が応答するまで、最大約5分待つ

最後に`Web App is healthy: https://...`と表示されれば完了です。

## 6. 動作を確認する

URLは`make up`の出力に表示されています。次のコマンドでも確認できます。

```bash
terraform -chdir=infra/sandbox/hello-world output -raw web_app_url; echo
```

### 6.1 Hello Worldの表示

URLをブラウザで開きます。

- [ ] 「Hello World」のタイトルが表示される
- [ ] 「Click」ボタンを押すたびに、`Clicks: 0` → `Clicks: 1` → `Clicks: 2`と回数が増える（WebSocketでサーバーと通信できている）

### 6.2 アクセス制限

許可したIP以外からは拒否されることを確認します。スマートフォンのWi-Fiを切り、モバイル回線で次の2つのURLを開きます。

- メインサイト: `https://<web_app_name>.azurewebsites.net`
- SCMサイト: `https://<web_app_name>.scm.azurewebsites.net`

`<web_app_name>`は`terraform -chdir=infra/sandbox/hello-world output -raw web_app_name`で確認できます。

- [ ] メインサイトで403（`Ip Forbidden`）が表示される
- [ ] SCMサイトで403が表示される

別の接続元を用意できない場合は、「未検証」として記録します。

### 6.3 Managed Identityでのpull

```bash
TF="terraform -chdir=infra/sandbox/hello-world"
az webapp config show -g "$($TF output -raw resource_group_name)" -n "$($TF output -raw web_app_name)" \
  --query '{acrUseManagedIdentityCreds:acrUseManagedIdentityCreds, linuxFxVersion:linuxFxVersion}' -o table
az acr show -n "$($TF output -raw registry_name)" --query adminUserEnabled -o tsv
az role assignment list --scope "$(az acr show -n "$($TF output -raw registry_name)" --query id -o tsv)" \
  --query "[].{role:roleDefinitionName, principalType:principalType}" -o table
```

- [ ] `acrUseManagedIdentityCreds`が`True`で、`linuxFxVersion`に`git rev-parse --short=12 HEAD`と同じタグが入っている
- [ ] ACRの`adminUserEnabled`が`false`
- [ ] ACRのスコープに、`AcrPull`（`ServicePrincipal`）の割り当てがある

## 7. 片付ける

```bash
make down
```

確認なしでdestroyが始まります。最後に`Resource Group deleted: rg-aichat-sandbox-...`と表示されれば完了です。所要時間は5〜10分程度です。

- [ ] `Resource Group deleted: ...`と表示される
- [ ] `az group list --query "[?starts_with(name, 'rg-aichat-sandbox-')].name" -o tsv`で何も表示されない

`terraform.tfvars`と`terraform.tfstate`は、片付けが終わるまで削除しないでください。どちらかがないと、`make down`で自動削除できません。

## 8. うまくいかないとき

| 症状 | 原因と対処 |
| --- | --- |
| `Set AZURE_SUBSCRIPTION_ID before running this command` | 環境変数が未設定です。「2.2 サブスクリプションID」を実行します。 |
| `Selected Azure subscription does not match AZURE_SUBSCRIPTION_ID` | `az account set`で選んだサブスクリプションと環境変数が違います。どちらかを合わせます。 |
| `Sandbox state subscription does not match AZURE_SUBSCRIPTION_ID` | 既存のstateは、別のサブスクリプションで作られたものです。そのサブスクリプションに切り替えて`make down`してから、作り直します。 |
| `make up`で`name_suffix`や`allowed_ip_cidr`の検証エラーになる | `terraform.tfvars`の値の形式を確認します（`name_suffix`は英小文字と数字4〜12文字、`allowed_ip_cidr`は`x.x.x.x/32`）。 |
| `make up`でACR名が使用済み（`AlreadyInUse`）になる | `name_suffix`を別の値に変えて、`make up`を再実行します。 |
| `make up`でロール割り当てが`AuthorizationFailed`になる | ロールを割り当てる権限がありません。サブスクリプションのOwner、またはUser Access Administratorが必要です。 |
| `make up`でApp Service Planの作成がクォータエラーになる | 無料・試用サブスクリプションでは、B1のクォータが0のことがあります。`location`を別のリージョン（`japanwest`など）に変えるか、クォータの引き上げを申請します。 |
| `make up`で`MissingSubscriptionRegistration`になる | リソースプロバイダーが未登録です。`az provider register -n Microsoft.Web`と`az provider register -n Microsoft.ContainerRegistry`を実行し、数分待ってから再実行します。 |
| `Commit product changes before deploying a commit SHA image` | 作業ツリーに変更があります。コミットするか、変更を戻してから`make deploy`を再実行します。 |
| `make deploy`の`az acr build`が`TasksOperationsNotAllowed`などで失敗する | 無料・試用サブスクリプションでは、ACR Tasks（ACR Build）が使えないことがあります。従量課金のサブスクリプションで試すか、この結果を#62に記録して対応を相談します。 |
| `make deploy`のヘルスチェックがタイムアウトする | AcrPullのロール割り当てが、まだ反映されていない可能性があります。`az webapp log tail -g <Resource Group名> -n <Web App名>`でログを確認し、数分待ってから`make deploy`を再実行します。 |
| 自分のPCからも403になる | 接続元IPが変わっています。`terraform.tfvars`の`allowed_ip_cidr`を更新し、`make up`を再実行します。 |
| 画面は出るが、ボタンを押しても回数が増えない | WebSocketが通っていません。`az webapp config show ... --query webSocketsEnabled`が`true`になっているか確認します。 |
| `make down`の途中で失敗した | まずエラー原因とTerraform stateを確認し、修正後に`make down`を再実行します。手動削除は最終手段です。実行する場合は、Azure CLIで選択中のサブスクリプションIDが`AZURE_SUBSCRIPTION_ID`と一致することを確認し、`make down`が表示した名前がこのsandbox専用の`rg-aichat-sandbox-<name_suffix>`であることを確認してください。確認後に限り、`GROUP="<確認したResource Group名>"`として`az group delete --subscription "$AZURE_SUBSCRIPTION_ID" --name "$GROUP" --yes`を実行します。Terraform stateは削除済みリソースを記録したままになるため、stateを整理・復旧するまで`make up`を再実行しないでください。 |

## 9. 結果の記録

確認が終わったら、次の内容を#62にコメントします。

- 6.1〜6.3と7のチェック結果（未検証の項目はその旨を書く）
- 所要時間（構築、イメージのビルドとpull、起動、片付け）
- B1での動作、詰まったところと対処
