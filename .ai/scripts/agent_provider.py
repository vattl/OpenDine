#!/usr/bin/env python3
"""Select, prepare, and prove readiness of built-in or external Agent providers."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
from typing import Callable


DEFAULT_TIMEOUT = 60
MAX_DIAGNOSTIC = 2000
READINESS_NAME = "AGENT_PROVIDER_READINESS.md"
EXIT_CODES = {
    "READY": 0,
    "BUILTIN_READY": 0,
    "CHOICE_REQUIRED": 2,
    "CLI_MISSING": 3,
    "PREREQUISITE_MISSING": 3,
    "CONFIRMATION_REQUIRED": 4,
    "AUTH_REQUIRED": 5,
    "AUTH_FAILED": 5,
    "LIVE_CHECK_REQUIRED": 6,
    "HEALTH_FAILED": 6,
    "HEALTH_TIMEOUT": 6,
    "INSTALL_FAILED": 7,
    "CONFIG_INVALID": 8,
    "CANCELLED": 130,
    "INSTALLED_RECHECK_REQUIRED": 6,
    "LOGIN_RECHECK_REQUIRED": 6,
}


class RegistryError(ValueError):
    pass


class ProviderError(ValueError):
    pass


def _argv(value: object, label: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or (not value and not allow_empty):
        raise RegistryError(f"{label} must be an argv array")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        raise RegistryError(f"{label} must contain non-empty strings")
    return list(value)


def load_registry(path: Path) -> dict[str, dict[str, object]]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RegistryError(f"cannot read provider registry: {exc}") from exc
    if not isinstance(raw, dict) or raw.get("schema_version") != 1:
        raise RegistryError("provider registry schema_version must be 1")
    providers = raw.get("providers")
    if not isinstance(providers, list) or not providers:
        raise RegistryError("provider registry must contain providers")

    result: dict[str, dict[str, object]] = {}
    for index, provider in enumerate(providers):
        if not isinstance(provider, dict):
            raise RegistryError(f"provider {index} must be an object")
        provider_id = provider.get("id")
        if not isinstance(provider_id, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{1,31}", provider_id):
            raise RegistryError(f"provider {index} has invalid id")
        if provider_id in result:
            raise RegistryError(f"duplicate provider id: {provider_id}")
        for name in ("display_name", "executable", "model_hint"):
            if not isinstance(provider.get(name), str) or not str(provider[name]).strip():
                raise RegistryError(f"provider {provider_id} missing {name}")
        _argv(provider.get("version_argv"), f"{provider_id}.version_argv")
        probe = _argv(provider.get("live_probe_argv"), f"{provider_id}.live_probe_argv")
        if not any("{nonce}" in item for item in probe):
            raise RegistryError(f"{provider_id}.live_probe_argv must contain {{nonce}}")
        for section_name in ("install", "auth"):
            if not isinstance(provider.get(section_name), dict):
                raise RegistryError(f"provider {provider_id} missing {section_name}")
        install = provider["install"]
        auth = provider["auth"]
        _argv(install.get("argv"), f"{provider_id}.install.argv")
        _argv(auth.get("status_argv"), f"{provider_id}.auth.status_argv", allow_empty=True)
        _argv(auth.get("login_argv"), f"{provider_id}.auth.login_argv")
        env_names = auth.get("env_names")
        if not isinstance(env_names, list) or any(
            not isinstance(name, str) or not re.fullmatch(r"[A-Z][A-Z0-9_]+", name)
            for name in env_names
        ):
            raise RegistryError(f"{provider_id}.auth.env_names must be environment names")
        for section, label in ((install, "install"), (auth, "auth")):
            url = section.get("official_url")
            if not isinstance(url, str) or not url.startswith("https://"):
                raise RegistryError(f"{provider_id}.{label}.official_url must use HTTPS")
        result[provider_id] = provider
    return result


def redact(value: str) -> str:
    text = value[:MAX_DIAGNOSTIC]
    patterns = (
        (r"(?i)\b([A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|PASSWORD))\s*=\s*[^\s]+", r"\1=[REDACTED]"),
        (r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}", "Bearer [REDACTED]"),
        (r"\bsk-[A-Za-z0-9_-]{8,}", "[REDACTED]"),
        (r"\bAIza[A-Za-z0-9_-]{12,}", "[REDACTED]"),
    )
    for pattern, replacement in patterns:
        text = re.sub(pattern, replacement, text)
    return text


class ProviderManager:
    def __init__(
        self,
        registry: dict[str, dict[str, object]],
        *,
        runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
        which: Callable[[str], str | None] = shutil.which,
        environ: dict[str, str] | os._Environ[str] = os.environ,
        timeout_seconds: int = DEFAULT_TIMEOUT,
    ) -> None:
        self.registry = registry
        self.runner = runner
        self.which = which
        self.environ = environ
        self.timeout_seconds = timeout_seconds

    def provider(self, provider_id: str) -> dict[str, object]:
        if provider_id not in self.registry:
            raise ProviderError(f"unknown provider: {provider_id}")
        return self.registry[provider_id]

    def _run(self, argv: list[str], *, interactive: bool = False) -> subprocess.CompletedProcess[str]:
        kwargs: dict[str, object] = {
            "shell": False,
            "check": False,
            "timeout": self.timeout_seconds,
        }
        if not interactive:
            kwargs.update({"text": True, "capture_output": True})
        return self.runner(argv, **kwargs)

    def _sanitize(self, value: str, provider: dict[str, object]) -> str:
        sanitized = redact(value)
        auth = provider["auth"]
        for name in auth["env_names"]:
            secret_value = self.environ.get(name)
            if secret_value:
                sanitized = sanitized.replace(secret_value, "[REDACTED]")
        return sanitized

    def _diagnostic(
        self, result: subprocess.CompletedProcess[str], provider: dict[str, object]
    ) -> str:
        combined = "\n".join(
            part for part in (result.stdout, result.stderr) if part
        ).strip()
        return self._sanitize(combined, provider)

    def _base(self, provider_id: str, provider: dict[str, object]) -> dict[str, object]:
        auth = provider["auth"]
        env_names = list(auth["env_names"])
        detected = [name for name in env_names if bool(self.environ.get(name))]
        return {
            "provider": provider_id,
            "mode": "EXTERNAL_CLI",
            "display_name": provider["display_name"],
            "model_hint": provider["model_hint"],
            "ready": False,
            "executable": provider["executable"],
            "credential_env_names": env_names,
            "credential_presence": "DETECTED" if detected else "NOT_DETECTED",
            "credential_sources_detected": detected,
            "install_url": provider["install"]["official_url"],
            "auth_url": auth["official_url"],
            "next_actions": [],
        }

    def status(
        self, provider_id: str, *, live: bool = False, nonce: str | None = None
    ) -> dict[str, object]:
        if provider_id == "builtin":
            return {
                "provider": "builtin",
                "mode": "BUILTIN",
                "display_name": "Built-in fresh-context Agent",
                "state": "BUILTIN_READY",
                "ready": True,
                "next_actions": ["Dispatch a different fresh-context built-in Agent."],
            }

        provider = self.provider(provider_id)
        result = self._base(provider_id, provider)
        executable = str(provider["executable"])
        executable_path = self.which(executable)
        result["executable_path"] = executable_path or ""
        if not executable_path:
            result.update(
                state="CLI_MISSING",
                next_actions=[
                    f"Preview installation with: agent_provider.py install --provider {provider_id}",
                    "Review the official installation URL before confirming.",
                ],
            )
            return result

        try:
            version_result = self._run(list(provider["version_argv"]))
        except subprocess.TimeoutExpired:
            result.update(state="HEALTH_TIMEOUT", next_actions=["Retry version detection or reinstall the CLI."])
            return result
        result["version"] = self._sanitize(
            (version_result.stdout or version_result.stderr or "").strip(), provider
        )
        if version_result.returncode != 0:
            result.update(
                state="HEALTH_FAILED",
                diagnostic=self._diagnostic(version_result, provider),
                next_actions=["Repair or reinstall the CLI, then retry doctor."],
            )
            return result

        auth = provider["auth"]
        auth_argv = list(auth["status_argv"])
        if auth_argv:
            try:
                auth_result = self._run(auth_argv)
            except subprocess.TimeoutExpired:
                result.update(state="AUTH_FAILED", next_actions=["Retry authentication status or login interactively."])
                return result
            if auth_result.returncode != 0:
                result.update(
                    state="AUTH_REQUIRED",
                    diagnostic=self._diagnostic(auth_result, provider),
                    next_actions=[
                        f"Review login guidance: {auth['official_url']}",
                        f"Preview login with: agent_provider.py login --provider {provider_id}",
                    ],
                )
                return result

        if not live:
            result.update(
                state="LIVE_CHECK_REQUIRED",
                next_actions=[
                    f"Run a bounded live check: agent_provider.py doctor --provider {provider_id} --live",
                    "A detected CLI or cached login does not prove model usability.",
                ],
            )
            return result

        marker = nonce or f"AGENT_READY_{secrets.token_hex(8)}"
        probe_argv = [item.replace("{nonce}", marker) for item in provider["live_probe_argv"]]
        result["probe_mode"] = "READ_ONLY_OR_PLAN"
        try:
            probe_result = self._run(probe_argv)
        except subprocess.TimeoutExpired:
            result.update(
                state="HEALTH_TIMEOUT",
                next_actions=["Check network/provider status and retry the bounded live probe."],
            )
            return result
        diagnostic = self._diagnostic(probe_result, provider)
        if probe_result.returncode != 0:
            auth_failure = re.search(
                r"(?i)(not logged|login required|authenticate|authentication|unauthorized|api key|\b401\b)",
                diagnostic,
            )
            result.update(
                state="AUTH_REQUIRED" if auth_failure else "HEALTH_FAILED",
                diagnostic=diagnostic,
                next_actions=[
                    "Complete authentication and retry." if auth_failure else "Check network, quota, billing, region and provider diagnostics, then retry."
                ],
            )
            return result
        lines = [line.strip() for line in f"{probe_result.stdout}\n{probe_result.stderr}".splitlines()]
        if marker not in lines:
            result.update(
                state="HEALTH_FAILED",
                diagnostic=diagnostic,
                next_actions=["The model call returned without the exact readiness marker; inspect CLI/model configuration."],
            )
            return result
        result.update(
            state="READY",
            ready=True,
            live_probe="PASS",
            next_actions=["Provider is ready for external read-only audit dispatch."],
        )
        return result

    def install(self, provider_id: str, *, execute: bool = False) -> dict[str, object]:
        provider = self.provider(provider_id)
        install = provider["install"]
        argv = list(install["argv"])
        base = self._base(provider_id, provider)
        base["install_argv"] = argv
        if not execute:
            base.update(
                state="CONFIRMATION_REQUIRED",
                next_actions=["Review the official URL and rerun with --yes to authorize installation."],
            )
            return base
        prerequisite = str(install["prerequisite"])
        if not self.which(prerequisite):
            base.update(
                state="PREREQUISITE_MISSING",
                next_actions=[f"Install {prerequisite} from its official source, then retry."],
            )
            return base
        try:
            install_result = self._run(argv)
        except subprocess.TimeoutExpired:
            base.update(state="INSTALL_FAILED", diagnostic="installation timed out", next_actions=["Check package-manager/network state and retry."])
            return base
        if install_result.returncode != 0:
            base.update(
                state="INSTALL_FAILED",
                diagnostic=self._diagnostic(install_result, provider),
                next_actions=["Review the official installation guide and package-manager permissions."],
            )
            return base
        recheck = self.status(provider_id, live=False)
        recheck["installation"] = "SUCCEEDED"
        recheck["install_argv"] = argv
        recheck["install_diagnostic"] = self._diagnostic(install_result, provider)
        if recheck["state"] == "CLI_MISSING":
            recheck.update(
                state="INSTALLED_RECHECK_REQUIRED",
                next_actions=[
                    "The installer succeeded but the executable is not visible on PATH yet.",
                    f"Refresh the terminal/PATH, then run doctor --provider {provider_id} --live.",
                ],
            )
        return recheck

    def login(self, provider_id: str, *, execute: bool = False) -> dict[str, object]:
        provider = self.provider(provider_id)
        auth = provider["auth"]
        argv = list(auth["login_argv"])
        base = self._base(provider_id, provider)
        base["login_argv"] = argv
        base["key_guidance"] = [
            f"Configure {name} in your terminal or the vendor credential store; never paste it into Agent chat."
            for name in auth["env_names"]
        ]
        if not execute:
            base.update(
                state="CONFIRMATION_REQUIRED",
                next_actions=["Rerun with --yes to launch the vendor's interactive login flow."],
            )
            return base
        try:
            login_result = self._run(argv, interactive=True)
        except subprocess.TimeoutExpired:
            base.update(state="AUTH_FAILED", next_actions=["Retry the interactive login flow."])
            return base
        if login_result.returncode != 0:
            base.update(state="AUTH_FAILED", next_actions=[f"Review {auth['official_url']} and retry."])
            return base
        base.update(
            state="LOGIN_RECHECK_REQUIRED",
            next_actions=[f"Run doctor --provider {provider_id} --live."],
        )
        return base


def write_readiness(path: Path, result: dict[str, object]) -> None:
    safe = json.loads(redact(json.dumps(result, ensure_ascii=False)))
    # Provider diagnostics are useful at the terminal but are not durable evidence:
    # vendors may echo credential material in formats no generic redactor recognizes.
    safe.pop("diagnostic", None)
    safe.pop("install_diagnostic", None)
    lines = [
        "# Agent Provider Readiness",
        "",
        f"Provider: {safe.get('provider', '')}",
        f"Provider Mode: {safe.get('mode', '')}",
        f"Provider State: {safe.get('state', '')}",
        f"Ready: {'YES' if safe.get('ready') else 'NO'}",
        f"Display Name: {safe.get('display_name', '')}",
        f"Version: {safe.get('version', '')}",
        f"Credential Presence: {safe.get('credential_presence', 'NOT_APPLICABLE')}",
        f"Live Probe: {safe.get('live_probe', 'NOT_RUN')}",
        "Secret Values Recorded: NO",
        "",
        "## Next Actions",
        "",
    ]
    lines.extend(f"- {action}" for action in safe.get("next_actions", []))
    lines.extend(
        [
            "",
            "## Sanitized Machine Evidence",
            "",
            "```json",
            json.dumps(safe, ensure_ascii=False, indent=2),
            "```",
            "",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def _choice(registry: dict[str, dict[str, object]]) -> dict[str, object]:
    return {
        "state": "CHOICE_REQUIRED",
        "ready": False,
        "choices": ["builtin", *registry.keys()],
        "message": "Choose the built-in Agent or one external CLI provider.",
    }


def _print(result: dict[str, object], as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    print(f"Provider: {result.get('provider', '<not selected>')}")
    print(f"State: {result.get('state')}")
    print(f"Ready: {'YES' if result.get('ready') else 'NO'}")
    if result.get("diagnostic"):
        print(f"Diagnostic: {result['diagnostic']}")
    if result.get("install_argv"):
        print(f"Install argv: {shlex.join(result['install_argv'])}")
    if result.get("install_url"):
        print(f"Official install guide: {result['install_url']}")
    if result.get("login_argv"):
        print(f"Login argv: {shlex.join(result['login_argv'])}")
    if result.get("auth_url"):
        print(f"Official authentication guide: {result['auth_url']}")
    for guidance in result.get("key_guidance", []):
        print(f"- {guidance}")
    for action in result.get("next_actions", []):
        print(f"- {action}")


def _evidence_path(root: Path, value: str | None) -> Path | None:
    if not value:
        return None
    target = Path(value)
    if not target.is_absolute():
        target = root / target
    resolved = target.resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as exc:
        raise ProviderError("evidence path must remain inside repository root") from exc
    return resolved


def interactive_setup(
    manager: ProviderManager, initial_provider: str | None = None
) -> dict[str, object]:
    provider_ids = ["builtin", *manager.registry.keys()]
    if initial_provider:
        provider_id = initial_provider
    else:
        print("Choose audit Agent provider:")
        for index, provider_id in enumerate(provider_ids, 1):
            print(f"  {index}. {provider_id}")
        try:
            selected = input("Selection (or q to cancel): ").strip()
        except (EOFError, KeyboardInterrupt):
            return {"state": "CANCELLED", "ready": False, "next_actions": []}
        if selected.lower() in {"q", "quit", "cancel"}:
            return {"state": "CANCELLED", "ready": False, "next_actions": []}
        provider_id = provider_ids[int(selected) - 1] if selected.isdigit() and 0 < int(selected) <= len(provider_ids) else selected
    if provider_id == "builtin":
        return manager.status("builtin", live=True)
    while True:
        result = manager.status(provider_id, live=True)
        _print(result, False)
        if result.get("ready"):
            return result
        action = input("Choose: [r]etry, [i]nstall, [l]ogin, [c]ancel: ").strip().lower()
        if action == "c":
            return {**result, "state": "CANCELLED", "ready": False}
        if action == "i":
            preview = manager.install(provider_id, execute=False)
            _print(preview, False)
            if input("Run this official install command? [y/N]: ").strip().lower() == "y":
                _print(manager.install(provider_id, execute=True), False)
        elif action == "l":
            preview = manager.login(provider_id, execute=False)
            _print(preview, False)
            if input("Launch the vendor login flow? [y/N]: ").strip().lower() == "y":
                _print(manager.login(provider_id, execute=True), False)


def main() -> int:
    parser = argparse.ArgumentParser(description="Agent provider selection and readiness controller")
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2], type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    sub = parser.add_subparsers(dest="command", required=True)

    list_parser = sub.add_parser("list")
    list_parser.add_argument("--json", action="store_true")
    for name in ("status", "doctor"):
        item = sub.add_parser(name)
        item.add_argument("--provider")
        item.add_argument("--live", action="store_true")
        item.add_argument("--json", action="store_true")
        item.add_argument("--evidence")
    for name in ("install", "login"):
        item = sub.add_parser(name)
        item.add_argument("--provider", required=True)
        item.add_argument("--yes", action="store_true")
        item.add_argument("--json", action="store_true")
    setup_parser = sub.add_parser("setup")
    setup_parser.add_argument("--provider")
    setup_parser.add_argument("--evidence")

    args = parser.parse_args()
    root = args.root.resolve()
    registry_path = args.registry or root / ".ai" / "config" / "agent-providers.json"
    try:
        registry = load_registry(registry_path)
        manager = ProviderManager(registry, timeout_seconds=max(1, args.timeout))
        if args.command == "list":
            result = _choice(registry)
        elif args.command in {"status", "doctor"}:
            result = _choice(registry) if not args.provider else manager.status(args.provider, live=args.live)
        elif args.command == "install":
            result = manager.install(args.provider, execute=args.yes)
        elif args.command == "login":
            result = manager.login(args.provider, execute=args.yes)
        else:
            result = interactive_setup(manager, args.provider)
        evidence = _evidence_path(root, getattr(args, "evidence", None))
        if evidence:
            write_readiness(evidence, result)
        _print(result, getattr(args, "json", False))
        return EXIT_CODES.get(str(result.get("state")), 6)
    except (RegistryError, ProviderError, ValueError, IndexError) as exc:
        result = {"state": "CONFIG_INVALID", "ready": False, "diagnostic": redact(str(exc)), "next_actions": []}
        _print(result, getattr(args, "json", False))
        return EXIT_CODES["CONFIG_INVALID"]


if __name__ == "__main__":
    raise SystemExit(main())
