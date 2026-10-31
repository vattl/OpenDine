# /agent-provider

Select and prepare the Agent provider used for an independent audit.

1. If no provider is configured, list `builtin` plus every provider in `.ai/config/agent-providers.json` and require a choice.
2. For `builtin`, dispatch a different fresh-context built-in Agent; no external CLI readiness artifact is required.
3. For an external provider, run the interactive controller:

   `python .ai/scripts/agent_provider.py setup --evidence <work-item>/AGENT_PROVIDER_READINESS.md`

4. If the CLI is absent, show its official installation URL and exact command. Install only after explicit confirmation.
5. If authentication is absent or invalid, launch the vendor login flow only after confirmation. Never request or record the secret value in chat, argv, or repository evidence.
6. Repeat diagnosis after installation/login until the bounded live probe passes or the user cancels. Do not translate an intermediate state into READY.
7. When used for `EXTERNAL_PROVIDER` audit mode, reference the readiness file and its SHA-256 in the audit receipt and report.

Non-interactive inspection examples:

```text
python .ai/scripts/agent_provider.py list --json
python .ai/scripts/agent_provider.py doctor --provider codex
python .ai/scripts/agent_provider.py doctor --provider codex --live --evidence docs/work-items/WI-XXX/AGENT_PROVIDER_READINESS.md
python .ai/scripts/agent_provider.py install --provider claude
python .ai/scripts/agent_provider.py login --provider claude
```

The install/login commands above are previews. Add `--yes` only after the user has reviewed and authorized that mutation.

