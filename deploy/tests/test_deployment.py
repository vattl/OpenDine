"""Deployment safety contract; run from the repository root with Python + PyYAML."""
import pathlib
import re
import unittest
import yaml

ROOT = pathlib.Path.cwd()


class DeploymentContractTest(unittest.TestCase):
    def setUp(self):
        self.compose = yaml.safe_load((ROOT / "deploy/docker-compose.yml").read_text(encoding="utf-8"))
        self.services = self.compose["services"]

    def test_application_receives_required_independent_secrets(self):
        app = self.services["opendine-server"]
        env = app["environment"]
        for key in ("AUTH_JWT_CURRENT_SECRET", "APPROVAL_TOKEN_ENVELOPE_KEY", "PAYMENT_CONFIG_MASTER_KEY"):
            self.assertRegex(env.get(key, ""), r"\$\{[^}:]+:\?[^}]+\}", key + " must fail closed when unset")
        self.assertNotEqual("root", env.get("SPRING_DATASOURCE_USERNAME"), "business application must not use MySQL root")

    def test_state_stores_and_private_keys_are_not_published(self):
        for name in ("opendine-mysql", "opendine-redis"):
            self.assertFalse(self.services[name].get("ports"), name + " must remain on the private Compose network")
        app = self.services["opendine-server"]
        private_dir = app["environment"].get("PAYMENT_PRIVATE_KEY_UPLOAD_DIR", "")
        self.assertTrue(private_dir.startswith("/var/lib/opendine/private/"), "payment keys require a private filesystem path")
        nginx_volumes = str(self.services["opendine-nginx"].get("volumes", []))
        self.assertNotIn("payment-keys", nginx_volumes, "nginx must never mount the payment key volume")

    def test_edge_and_data_networks_are_explicitly_segmented(self):
        self.assertTrue(self.compose["networks"]["data"].get("internal"), "data network must be internal")
        self.assertEqual(["edge"], self.services["opendine-nginx"].get("networks"))
        self.assertEqual({"edge", "data"}, set(self.services["opendine-server"].get("networks", [])))
        for name in ("opendine-mysql", "opendine-redis", "bootstrap"):
            self.assertEqual(["data"], self.services[name].get("networks"), name + " must only join the data network")

    def test_upstream_container_images_are_digest_pinned(self):
        digest = re.compile(r"^[^@]+@sha256:[0-9a-f]{64}$")
        for name in ("opendine-mysql", "opendine-redis", "opendine-nginx"):
            self.assertRegex(self.services[name]["image"], digest, name + " image must be immutable")
        dockerfile = (ROOT / "deploy/Dockerfile").read_text(encoding="utf-8")
        from_lines = [line for line in dockerfile.splitlines() if line.startswith("FROM ")]
        self.assertEqual(2, len(from_lines))
        for line in from_lines:
            self.assertRegex(line.split()[1], digest, "Dockerfile base image must be immutable")

    def test_fresh_bootstrap_is_explicit_and_not_a_restart_side_effect(self):
        bootstrap = self.services.get("bootstrap", {})
        self.assertTrue(bootstrap, "fresh installation must have an executable bootstrap service")
        self.assertIn("tools", bootstrap.get("profiles", []))
        self.assertNotIn("bootstrap", self.services["opendine-server"].get("depends_on", {}))
        env = bootstrap.get("environment", {})
        self.assertRegex(env.get("BOOTSTRAP_ADMIN_PASSWORD", ""), r"\$\{[^}:]+:\?[^}]+\}")
        self.assertNotIn("BOOTSTRAP_ADMIN_PASSWORD", self.services["opendine-server"]["environment"])

    def test_schema_import_cannot_switch_away_from_selected_database(self):
        sql = (ROOT / "deploy/sql/init.sql").read_text(encoding="utf-8")
        self.assertNotRegex(sql, r"(?im)^\s*(CREATE\s+DATABASE|USE\s+)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
