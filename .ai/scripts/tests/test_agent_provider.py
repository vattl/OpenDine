from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout
from io import StringIO


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".ai" / "scripts" / "agent_provider.py"
REGISTRY = ROOT / ".ai" / "config" / "agent-providers.json"


def load_module():
    spec = importlib.util.spec_from_file_location("agent_provider", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class FakeRunner:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, argv, **kwargs):
        self.calls.append((list(argv), kwargs))
        response = self.responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        return response


def completed(argv, code=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(argv, code, stdout, stderr)


class AgentProviderTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self.registry = self.module.load_registry(REGISTRY)

    def manager(self, responses=(), installed=("npm", "codex"), environ=None):
        installed_set = set(installed)
        return self.module.ProviderManager(
            self.registry,
            runner=FakeRunner(responses),
            which=lambda name: f"/fake/{name}" if name in installed_set else None,
            environ={} if environ is None else environ,
            timeout_seconds=1,
        )

    def test_builtin_is_ready_without_external_checks(self):
        manager = self.manager(installed=())
        result = manager.status("builtin", live=True)
        self.assertEqual(result["state"], "BUILTIN_READY")
        self.assertTrue(result["ready"])

    def test_missing_external_cli_is_not_ready(self):
        manager = self.manager(installed=("npm",))
        result = manager.status("codex", live=True)
        self.assertEqual(result["state"], "CLI_MISSING")
        self.assertFalse(result["ready"])
        self.assertNotIn("sk-", json.dumps(result))

    def test_install_previews_without_confirmation_or_execution(self):
        manager = self.manager(installed=("npm",))
        result = manager.install("codex", execute=False)
        self.assertEqual(result["state"], "CONFIRMATION_REQUIRED")
        self.assertEqual(result["install_argv"], ["npm", "install", "-g", "@openai/codex"])
        self.assertEqual(manager.runner.calls, [])

    def test_install_failure_is_structured_and_sanitized(self):
        secret = "sk-install-failure-secret-123456"
        manager = self.manager(
            responses=[completed([], 1, "", f"TOKEN={secret}")], installed=("npm",)
        )
        result = manager.install("codex", execute=True)
        self.assertEqual(result["state"], "INSTALL_FAILED")
        self.assertFalse(result["ready"])
        self.assertNotIn(secret, json.dumps(result))

    def test_login_preview_never_accepts_or_exposes_a_key_value(self):
        manager = self.manager(environ={"OPENAI_API_KEY": "opaque-real-value"})
        result = manager.login("codex", execute=False)
        encoded = json.dumps(result)
        self.assertEqual(result["state"], "CONFIRMATION_REQUIRED")
        self.assertNotIn("opaque-real-value", encoded)
        self.assertEqual(manager.runner.calls, [])

    def test_plain_install_preview_shows_exact_argv_and_official_url(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(ROOT), "install", "--provider", "codex"],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 4)
        self.assertIn("Install argv: npm install -g @openai/codex", result.stdout)
        self.assertIn("https://github.com/openai/codex", result.stdout)

    def test_plain_login_preview_shows_command_url_and_key_guidance(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(ROOT), "login", "--provider", "claude"],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 4)
        self.assertIn("Login argv: claude auth login", result.stdout)
        self.assertIn("https://docs.anthropic.com/en/docs/claude-code/getting-started", result.stdout)
        self.assertIn("Configure ANTHROPIC_API_KEY", result.stdout)

    def test_confirmed_install_uses_argv_without_shell(self):
        manager = self.manager(
            responses=[completed([], 0, "installed")], installed=("npm",)
        )
        result = manager.install("codex", execute=True)
        self.assertEqual(result["state"], "INSTALLED_RECHECK_REQUIRED")
        argv, kwargs = manager.runner.calls[0]
        self.assertEqual(argv, ["npm", "install", "-g", "@openai/codex"])
        self.assertFalse(kwargs.get("shell", False))

    def test_confirmed_install_rechecks_executable_and_version(self):
        runner = FakeRunner([
            completed([], 0, "installed"),
            completed([], 0, "codex 2.0"),
            completed([], 0, "logged in"),
        ])
        def which(name):
            if name == "npm":
                return "/fake/npm"
            if name == "codex":
                return "/fake/codex"
            return None

        manager = self.module.ProviderManager(
            self.registry, runner=runner, which=which, environ={}, timeout_seconds=1
        )
        result = manager.install("codex", execute=True)
        self.assertEqual(result["installation"], "SUCCEEDED")
        self.assertEqual(result["state"], "LIVE_CHECK_REQUIRED")
        self.assertEqual(result["version"], "codex 2.0")

    def test_setup_accepts_explicit_builtin_provider_without_prompt(self):
        manager = self.manager(installed=())
        result = self.module.interactive_setup(manager, "builtin")
        self.assertEqual(result["state"], "BUILTIN_READY")

    def test_interactive_setup_retries_until_external_provider_is_ready(self):
        class StubManager:
            registry = {"claude": {}}

            def __init__(self):
                self.calls = 0

            def status(self, provider_id, live=False):
                self.calls += 1
                if self.calls == 1:
                    return {
                        "provider": provider_id,
                        "state": "HEALTH_FAILED",
                        "ready": False,
                        "next_actions": ["retry"],
                    }
                return {
                    "provider": provider_id,
                    "state": "READY",
                    "ready": True,
                    "next_actions": [],
                }

        manager = StubManager()
        with patch("builtins.input", side_effect=["r"]):
            result = self.module.interactive_setup(manager, "claude")
        self.assertEqual(result["state"], "READY")
        self.assertEqual(manager.calls, 2)

    def test_interactive_install_preview_is_visible_before_confirmation(self):
        manager = self.manager(installed=("npm",))
        output = StringIO()
        with patch("builtins.input", side_effect=["i", "n", "c"]), redirect_stdout(output):
            result = self.module.interactive_setup(manager, "codex")
        rendered = output.getvalue()
        self.assertEqual(result["state"], "CANCELLED")
        self.assertIn("Install argv: npm install -g @openai/codex", rendered)
        self.assertIn("https://github.com/openai/codex", rendered)

    def test_interactive_login_preview_is_visible_before_confirmation(self):
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 1, "", "not logged in"),
                completed([], 0, "codex 1.0"),
                completed([], 1, "", "not logged in"),
            ]
        )
        output = StringIO()
        with patch("builtins.input", side_effect=["l", "n", "c"]), redirect_stdout(output):
            result = self.module.interactive_setup(manager, "codex")
        rendered = output.getvalue()
        self.assertEqual(result["state"], "CANCELLED")
        self.assertIn("Login argv: codex login", rendered)
        self.assertIn("https://developers.openai.com/codex/auth", rendered)
        self.assertIn("Configure OPENAI_API_KEY", rendered)

    def test_registry_argv_metacharacters_are_passed_literally_without_shell(self):
        provider = dict(self.registry["codex"])
        provider["version_argv"] = ["codex", "--version;remove-everything"]
        registry = {"codex": provider}
        runner = FakeRunner([completed([], 0, "codex 1.0"), completed([], 0, "logged in")])
        manager = self.module.ProviderManager(
            registry,
            runner=runner,
            which=lambda name: f"/fake/{name}",
            environ={},
            timeout_seconds=1,
        )
        result = manager.status("codex", live=False)
        self.assertEqual(result["state"], "LIVE_CHECK_REQUIRED")
        argv, kwargs = runner.calls[0]
        self.assertEqual(argv[1], "--version;remove-everything")
        self.assertFalse(kwargs["shell"])

    def test_auth_failure_never_becomes_ready(self):
        manager = self.manager(
            responses=[completed([], 0, "codex 1.0"), completed([], 1, "", "not logged in")]
        )
        result = manager.status("codex", live=True)
        self.assertEqual(result["state"], "AUTH_REQUIRED")
        self.assertFalse(result["ready"])

    def test_auth_success_without_live_probe_requires_live_check(self):
        manager = self.manager(
            responses=[completed([], 0, "codex 1.0"), completed([], 0, "logged in")]
        )
        result = manager.status("codex", live=False)
        self.assertEqual(result["state"], "LIVE_CHECK_REQUIRED")
        self.assertFalse(result["ready"])

    def test_live_probe_requires_exact_nonce_marker(self):
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 0, "logged in"),
                completed([], 0, "AGENT_READY_deadbeef"),
            ]
        )
        result = manager.status("codex", live=True, nonce="AGENT_READY_deadbeef")
        self.assertEqual(result["state"], "READY")
        self.assertTrue(result["ready"])

    def test_wrong_live_marker_is_health_failed(self):
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 0, "logged in"),
                completed([], 0, "almost ready"),
            ]
        )
        result = manager.status("codex", live=True, nonce="AGENT_READY_deadbeef")
        self.assertEqual(result["state"], "HEALTH_FAILED")

    def test_timeout_is_structured_and_not_ready(self):
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 0, "logged in"),
                subprocess.TimeoutExpired(["codex"], 1),
            ]
        )
        result = manager.status("codex", live=True, nonce="AGENT_READY_deadbeef")
        self.assertEqual(result["state"], "HEALTH_TIMEOUT")
        self.assertFalse(result["ready"])

    def test_secret_shaped_output_is_redacted(self):
        secret = "sk-super-secret-value-123456789"
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 1, "", f"OPENAI_API_KEY={secret}"),
            ],
            environ={"OPENAI_API_KEY": secret},
        )
        result = manager.status("codex", live=False)
        encoded = json.dumps(result)
        self.assertNotIn(secret, encoded)
        self.assertIn("[REDACTED]", encoded)

    def test_configured_opaque_key_is_removed_from_structured_diagnostics(self):
        secret = "opaque-real-key-value-123456"
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 1, "", f"credential={secret}"),
            ],
            environ={"OPENAI_API_KEY": secret},
        )
        result = manager.status("codex", live=True)
        encoded = json.dumps(result)
        self.assertEqual(result["state"], "AUTH_REQUIRED")
        self.assertNotIn(secret, encoded)
        self.assertIn("[REDACTED]", encoded)
        output = StringIO()
        with redirect_stdout(output):
            self.module._print(result, False)
        self.assertNotIn(secret, output.getvalue())

    def test_gemini_without_key_still_requires_live_check_for_cached_oauth(self):
        manager = self.manager(
            responses=[completed([], 0, "gemini 1.0")],
            installed=("npm", "gemini"),
        )
        result = manager.status("gemini", live=False)
        self.assertEqual(result["state"], "LIVE_CHECK_REQUIRED")
        self.assertEqual(result["credential_presence"], "NOT_DETECTED")

    def test_readiness_evidence_contains_no_secret_values(self):
        secret = "sk-super-secret-value-123456789"
        manager = self.manager(
            responses=[
                completed([], 0, "codex 1.0"),
                completed([], 0, "logged in"),
                completed([], 0, "AGENT_READY_deadbeef"),
            ],
            environ={"OPENAI_API_KEY": secret},
        )
        result = manager.status("codex", live=True, nonce="AGENT_READY_deadbeef")
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "AGENT_PROVIDER_READINESS.md"
            self.module.write_readiness(target, result)
            text = target.read_text(encoding="utf-8")
        self.assertNotIn(secret, text)
        self.assertIn("Provider State: READY", text)

    def test_readiness_evidence_never_persists_provider_diagnostics(self):
        opaque_secret = "vendor-secret-format-DO-NOT-PERSIST"
        result = {
            "provider": "claude",
            "mode": "EXTERNAL_CLI",
            "state": "AUTH_FAILED",
            "ready": False,
            "diagnostic": opaque_secret,
            "install_diagnostic": opaque_secret,
            "next_actions": ["Retry vendor login."],
        }
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "AGENT_PROVIDER_READINESS.md"
            self.module.write_readiness(target, result)
            text = target.read_text(encoding="utf-8")
        self.assertNotIn(opaque_secret, text)

    def test_invalid_registry_rejects_string_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "registry.json"
            path.write_text(
                json.dumps({
                    "schema_version": 1,
                    "providers": [{
                        "id": "evil",
                        "display_name": "Evil",
                        "executable": "evil",
                        "version_argv": "evil --version; remove-all",
                        "install": {"prerequisite": "npm", "argv": ["npm"], "official_url": "https://example.com"},
                        "auth": {"status_argv": [], "login_argv": [], "env_names": [], "official_url": "https://example.com"},
                        "live_probe_argv": ["evil", "{nonce}"],
                        "model_hint": "model"
                    }]
                }),
                encoding="utf-8",
            )
            with self.assertRaises(self.module.RegistryError):
                self.module.load_registry(path)

    def test_doctor_without_provider_returns_choice_required_json(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(ROOT), "doctor", "--json"],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["state"], "CHOICE_REQUIRED")
        self.assertIn("builtin", payload["choices"])


if __name__ == "__main__":
    unittest.main()
