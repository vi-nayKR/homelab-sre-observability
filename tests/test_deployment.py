import copy
import importlib.util
from pathlib import Path
import secrets
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("deployment", Path(__file__).resolve().parents[1] / "scripts/check-deployment.py")
deployment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deployment)


class DeploymentGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.directory.chmod(0o700)
        self.model = {"name": "homelab-sre-prod", "services": {}, "secrets": {}}
        for name in ("demo-api", "prometheus", "alertmanager", "grafana", "blackbox-exporter", "alert-receiver"):
            self.model["services"][name] = {
                "cap_drop": ["ALL"], "security_opt": ["no-new-privileges:true"],
                "mem_limit": 128000000, "cpus": 0.25,
                "logging": {"options": {"max-size": "10m", "max-file": "3"}},
            }
        for name in ("demo-api", "alert-receiver"):
            self.model["services"][name]["image"] = "homelab-sre-observability/demo-api:" + "a" * 40
        self.model["services"]["demo-api"]["environment"] = {"LAB_CONTROLS_ENABLED": "false"}
        self.model["services"]["alert-receiver"]["environment"] = {
            "LAB_CONTROLS_ENABLED": "false", "ALERT_WEBHOOK_TOKEN_FILE": "/run/secrets/receiver_token"}
        self.model["services"]["grafana"]["environment"] = {
            "GF_SECURITY_ADMIN_PASSWORD": "", "GF_SECURITY_ADMIN_PASSWORD__FILE": "/run/secrets/grafana_password"}
        self.model["services"]["prometheus"]["command"] = ["--storage.tsdb.retention.time=35d"]
        for name in ("grafana_password", "receiver_token"):
            path = self.directory / name
            path.write_text(secrets.token_hex(32))
            path.chmod(0o444)
            self.model["secrets"][name] = {"file": str(path)}

    def errors(self, model=None):
        return deployment.validate(self.model if model is None else model, self.directory)

    def test_valid_fixture(self):
        self.assertEqual(self.errors(), [])

    def test_unsafe_models_fail(self):
        mutations = [
            lambda m: m.update(name="another-existing-app"),
            lambda m: m["services"]["demo-api"]["environment"].update(LAB_CONTROLS_ENABLED="true"),
            lambda m: m["services"]["demo-api"].update(ports=[{"host_ip": "0.0.0.0"}]),
            lambda m: m["services"]["demo-api"].update(privileged=True),
            lambda m: m["services"]["demo-api"].update(network_mode="host"),
            lambda m: m["services"]["demo-api"].update(pid="host"),
            lambda m: m["services"]["demo-api"].update(cap_add=["SYS_ADMIN"]),
            lambda m: m["services"]["demo-api"].update(devices=["/dev/sda"]),
            lambda m: m.update(networks={"observability": {"external": True, "name": "existing-app"}}),
            lambda m: m.update(volumes={"prometheus-data": {"name": "existing-app-data"}}),
            lambda m: m["services"]["demo-api"].update(cap_drop=[]),
            lambda m: m["services"]["demo-api"].update(logging={}),
            lambda m: m["services"]["demo-api"].update(mem_limit=0),
            lambda m: m["services"]["demo-api"].update(volumes=[{"source": "/var/run/docker.sock"}]),
            lambda m: m["services"]["alert-receiver"].update(ports=[{"host_ip": "127.0.0.1"}]),
            lambda m: m["services"].pop("alert-receiver"),
            lambda m: m["services"]["grafana"]["environment"].update(GF_SECURITY_ADMIN_PASSWORD="plaintext"),
            lambda m: m["services"]["prometheus"]["command"].append("--web.enable-lifecycle"),
        ]
        for number, mutate in enumerate(mutations):
            with self.subTest(number=number):
                model = copy.deepcopy(self.model)
                mutate(model)
                self.assertTrue(self.errors(model))

    def test_weak_or_missing_secrets_fail(self):
        path = self.directory / "receiver_token"
        path.chmod(0o600)
        path.write_text("replace-with-a-long-local-password")
        path.chmod(0o444)
        self.assertTrue(self.errors())
        path.unlink()
        self.assertTrue(self.errors())

    def test_world_accessible_secret_directory_fails(self):
        self.directory.chmod(0o755)
        self.assertTrue(self.errors())

    def test_writable_or_symlink_secrets_fail(self):
        path = self.directory / "receiver_token"
        path.chmod(0o644)
        self.assertTrue(self.errors())
        target = self.directory / "real-token"
        path.rename(target)
        path.symlink_to(target)
        self.assertTrue(self.errors())


if __name__ == "__main__":
    unittest.main()
