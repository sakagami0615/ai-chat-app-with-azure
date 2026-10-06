#!/usr/bin/env bash
set -euo pipefail

sandbox_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$sandbox_dir/../../.." && pwd)

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

tf() {
  (cd "$sandbox_dir" && terraform "$@")
}

tf_output() {
  tf output -raw "$1"
}

require_state() {
  [[ -f "$sandbox_dir/terraform.tfstate" ]] || fail "sandbox Terraform state is missing: $sandbox_dir/terraform.tfstate"
}

state_resource_group() {
  local group state_text
  group=$(tf_output resource_group_name 2>/dev/null || true)
  if [[ -z "$group" ]]; then
    state_text=$(tf state show azurerm_resource_group.sandbox 2>/dev/null) || fail "Resource Group is absent from sandbox state"
    group=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\(rg-aichat-sandbox-[a-z0-9]*\)".*/\1/p' <<< "$state_text" | head -n 1)
  fi
  [[ "$group" =~ ^rg-aichat-sandbox-[a-z0-9]{4,12}$ ]] || fail "Unexpected Resource Group name in sandbox state: $group"
  printf '%s\n' "$group"
}

verify_state_subscription() {
  local state_subscription state_text
  state_subscription=$(tf_output subscription_id 2>/dev/null || true)
  if [[ -z "$state_subscription" ]]; then
    state_text=$(tf state show azurerm_resource_group.sandbox 2>/dev/null) || fail "Subscription is absent from sandbox state"
    if [[ "$state_text" =~ /subscriptions/([0-9a-fA-F-]{36})/resourceGroups/ ]]; then
      state_subscription=${BASH_REMATCH[1]}
    fi
  fi
  [[ "$state_subscription" == "$AZURE_SUBSCRIPTION_ID" ]] || fail "Sandbox state subscription does not match AZURE_SUBSCRIPTION_ID"
}

preflight() {
  [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]] || fail "Set AZURE_SUBSCRIPTION_ID before running this command"
  command -v az >/dev/null || fail "Azure CLI (az) is required"
  command -v terraform >/dev/null || fail "Terraform is required"
  local selected_subscription
  selected_subscription=$(az account show --query id --output tsv) || fail "Sign in with az login"
  [[ "$selected_subscription" == "$AZURE_SUBSCRIPTION_ID" ]] || fail "Selected Azure subscription does not match AZURE_SUBSCRIPTION_ID"
}

up() {
  [[ -f "$sandbox_dir/terraform.tfvars" ]] || fail "Copy terraform.tfvars.example to terraform.tfvars and fill in its values"
  tf init -lockfile=readonly
  if [[ -f "$sandbox_dir/terraform.tfstate" ]] && [[ -n "$(tf state list)" ]]; then
    verify_state_subscription
  fi
  printf 'Subscription: %s\n' "$AZURE_SUBSCRIPTION_ID"
  tf apply -auto-approve -input=false -var "subscription_id=$AZURE_SUBSCRIPTION_ID"
  printf 'Resource Group: %s\n' "$(tf_output resource_group_name)"
  printf 'Web App: %s\n' "$(tf_output web_app_url)"
}

deploy() {
  require_state
  tf init -lockfile=readonly
  verify_state_subscription
  [[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=normal)" ]] || fail "Commit product changes before deploying a commit SHA image"

  local group registry login_server web_app web_app_url tag image managed_identity
  group=$(state_resource_group)
  registry=$(tf_output registry_name)
  login_server=$(tf_output registry_login_server)
  web_app=$(tf_output web_app_name)
  web_app_url=$(tf_output web_app_url)
  tag=$(git -C "$repo_root" rev-parse --short=12 HEAD)
  [[ "$tag" =~ ^[0-9a-f]{12}$ ]] || fail "Cannot determine a 12-character commit SHA"
  image="$login_server/hello-world:$tag"

  az acr build --subscription "$AZURE_SUBSCRIPTION_ID" --registry "$registry" --image "hello-world:$tag" --file Dockerfile "$repo_root"
  az webapp config container set --subscription "$AZURE_SUBSCRIPTION_ID" --resource-group "$group" --name "$web_app" --container-image-name "$image"
  managed_identity=$(az webapp config show --subscription "$AZURE_SUBSCRIPTION_ID" --resource-group "$group" --name "$web_app" --query acrUseManagedIdentityCreds --output tsv)
  [[ "$managed_identity" == "true" ]] || fail "Managed Identity ACR pull setting is not enabled after image update"
  az webapp restart --subscription "$AZURE_SUBSCRIPTION_ID" --resource-group "$group" --name "$web_app"
  curl --fail --silent --show-error --retry 30 --retry-delay 10 --retry-all-errors --max-time 10 "$web_app_url/_stcore/health" >/dev/null
  printf 'Web App is healthy: %s\n' "$web_app_url"
}

down() {
  require_state
  tf init -lockfile=readonly
  verify_state_subscription
  [[ -f "$sandbox_dir/terraform.tfvars" ]] || fail "terraform.tfvars is required to destroy the sandbox"
  local group exists
  group=$(state_resource_group)
  printf 'Destroying sandbox Resource Group %s in subscription %s\n' "$group" "$AZURE_SUBSCRIPTION_ID"
  tf destroy -auto-approve -input=false -var "subscription_id=$AZURE_SUBSCRIPTION_ID"
  exists=$(az group exists --subscription "$AZURE_SUBSCRIPTION_ID" --name "$group" --output tsv)
  [[ "$exists" == "false" ]] || fail "Resource Group still exists after destroy: $group"
  printf 'Resource Group deleted: %s\n' "$group"
}

case "${1:-}" in
  up|deploy|down)
    preflight
    "$1"
    ;;
  *)
    fail "Usage: $0 {up|deploy|down}"
    ;;
esac
