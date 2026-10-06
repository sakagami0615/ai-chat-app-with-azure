import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "infra" / "sandbox" / "hello-world" / "manage.sh"
SUBSCRIPTION_ID = "11111111-1111-1111-1111-111111111111"


class ManageTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SOURCE.is_file(), "sandbox management script is missing")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sandbox = self.root / "infra" / "sandbox" / "hello-world"
        self.sandbox.mkdir(parents=True)
        shutil.copyfile(SOURCE, self.sandbox / "manage.sh")
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.log = self.root / "commands.log"

        self.write_command(
            "az",
            '''#!/usr/bin/env bash
echo "az $*" >> "$MOCK_COMMAND_LOG"
if [[ "$1 $2" == "account show" ]]; then
  printf '%s\\n' "$MOCK_ACCOUNT_ID"
elif [[ "$1 $2" == "acr build" ]]; then
  exit "${MOCK_ACR_EXIT:-0}"
elif [[ "$1 $2" == "group exists" ]]; then
  printf '%s\\n' "${MOCK_GROUP_EXISTS:-false}"
elif [[ "$1 $2" == "webapp config" ]]; then
  printf '%s\\n' true
fi
''',
        )
        self.write_command(
            "terraform",
            '''#!/usr/bin/env bash
echo "terraform $*" >> "$MOCK_COMMAND_LOG"
if [[ "$1" == "output" ]]; then
  if [[ "${MOCK_OUTPUTS_MISSING:-0}" == "1" ]]; then
    exit 1
  fi
  case "${3:-}" in
    resource_group_name) printf '%s\\n' rg-aichat-sandbox-abc123 ;;
    registry_name) printf '%s\\n' aichatsbxabc123 ;;
    registry_login_server) printf '%s\\n' aichatsbxabc123.azurecr.io ;;
    web_app_name) printf '%s\\n' app-aichat-sbx-abc123 ;;
    web_app_url) printf '%s\\n' https://app-aichat-sbx-abc123.azurewebsites.net ;;
    subscription_id) printf '%s\\n' "${MOCK_STATE_SUBSCRIPTION_ID:-$MOCK_ACCOUNT_ID}" ;;
  esac
elif [[ "$1 $2" == "state show" ]]; then
  printf '    id = "/subscriptions/%s/resourceGroups/rg-aichat-sandbox-abc123"\\n' "$MOCK_ACCOUNT_ID"
  printf '    name = "rg-aichat-sandbox-abc123"\\n'
elif [[ "$1 $2" == "state list" && "${MOCK_STATE_RESOURCES:-0}" == "1" ]]; then
  printf '%s\\n' azurerm_resource_group.sandbox
fi
''',
        )
        self.write_command(
            "git",
            '''#!/usr/bin/env bash
echo "git $*" >> "$MOCK_COMMAND_LOG"
if [[ "$*" == *"rev-parse --short=12 HEAD"* ]]; then
  printf '%s\\n' abcdef123456
fi
''',
        )

    def write_command(self, name, body):
        path = self.bin_dir / name
        path.write_text(body)
        path.chmod(0o755)

    def run_manage(self, action, subscription_id=SUBSCRIPTION_ID, **extra_env):
        env = os.environ.copy()
        env["PATH"] = f"{self.bin_dir}:{env['PATH']}"
        env["MOCK_ACCOUNT_ID"] = SUBSCRIPTION_ID
        env["MOCK_COMMAND_LOG"] = str(self.log)
        if subscription_id is None:
            env.pop("AZURE_SUBSCRIPTION_ID", None)
        else:
            env["AZURE_SUBSCRIPTION_ID"] = subscription_id
        env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.sandbox / "manage.sh"), action],
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def command_log(self):
        return self.log.read_text() if self.log.exists() else ""

    def test_missing_subscription_stops_before_azure_calls(self):
        result = self.run_manage("up", subscription_id=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AZURE_SUBSCRIPTION_ID", result.stderr)
        self.assertEqual(self.command_log(), "")

    def test_wrong_subscription_stops_before_apply(self):
        result = self.run_manage("up", subscription_id="22222222-2222-2222-2222-222222222222")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("subscription", result.stderr.lower())
        self.assertNotIn("terraform apply", self.command_log())

    def test_up_rejects_state_from_another_subscription(self):
        (self.sandbox / "terraform.tfstate").write_text("{}")
        (self.sandbox / "terraform.tfvars").write_text('name_suffix = "abc123"')
        new_subscription = "22222222-2222-2222-2222-222222222222"
        result = self.run_manage(
            "up",
            subscription_id=new_subscription,
            MOCK_ACCOUNT_ID=new_subscription,
            MOCK_STATE_SUBSCRIPTION_ID=SUBSCRIPTION_ID,
            MOCK_STATE_RESOURCES="1",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("state subscription", result.stderr.lower())
        self.assertNotIn("terraform apply", self.command_log())

    def test_missing_state_stops_deploy_before_build(self):
        result = self.run_manage("deploy")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("state", result.stderr.lower())
        self.assertNotIn("az acr build", self.command_log())

    def test_acr_build_failure_does_not_switch_image(self):
        (self.sandbox / "terraform.tfstate").write_text("{}")
        result = self.run_manage("deploy", MOCK_ACR_EXIT="17")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("az acr build", self.command_log())
        self.assertIn("--file Dockerfile", self.command_log())
        self.assertNotIn("az webapp config", self.command_log())

    def test_partial_state_can_be_destroyed_without_outputs(self):
        (self.sandbox / "terraform.tfstate").write_text("{}")
        (self.sandbox / "terraform.tfvars").write_text('name_suffix = "abc123"')
        result = self.run_manage("down", MOCK_OUTPUTS_MISSING="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("terraform destroy", self.command_log())
        self.assertIn("az group exists", self.command_log())

    def test_down_fails_when_resource_group_remains(self):
        (self.sandbox / "terraform.tfstate").write_text("{}")
        (self.sandbox / "terraform.tfvars").write_text('name_suffix = "abc123"')
        result = self.run_manage("down", MOCK_GROUP_EXISTS="true")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Resource Group still exists", result.stderr)


if __name__ == "__main__":
    unittest.main()
