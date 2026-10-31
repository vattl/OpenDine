# Agent Provider Selection and Readiness Rules

The workflow may use either the built-in fresh-context Agent or a registered external Agent CLI. When no provider has been selected, the operator must be shown the available choices; the workflow must not silently choose an external provider.

## State machine

`CHOICE_REQUIRED → CLI_MISSING → CONFIRMATION_REQUIRED → INSTALLED_RECHECK_REQUIRED → AUTH_REQUIRED → LOGIN_RECHECK_REQUIRED → LIVE_CHECK_REQUIRED → READY`

The path may skip states already satisfied by the environment. Failures remain explicit (`PREREQUISITE_MISSING`, `INSTALL_FAILED`, `AUTH_FAILED`, `HEALTH_FAILED`, or `HEALTH_TIMEOUT`) and include a safe next action. Cancellation is always allowed.

## Installation and authentication safety

- External installation is a system mutation. Show the exact argv and official source first, then require an explicit confirmation (`--yes` or an interactive `y`). Never install silently.
- Execute only registry-defined argv arrays with `shell=False`. The versioned repository registry is a trusted configuration surface and must be reviewed like executable policy.
- Never accept an API key or token as a command-line argument, chat value, evidence field, or repository file. Direct the user to the provider's interactive login or terminal/vendor credential store.
- Detect only whether a documented credential environment variable is present. Never print, persist, hash, compare, or transmit its value as workflow evidence.
- Sanitize diagnostics before display, including exact replacement of any configured credential value known to the controller, and omit provider diagnostics from durable readiness evidence. Do not claim that pattern redaction alone makes arbitrary provider output safe for unrestricted reuse.

## Readiness proof

CLI presence, a version response, cached login, or credential-variable presence does not prove usability. An external provider is `READY` only after a bounded live model probe:

- uses a generated nonce and requires that exact marker in the response;
- uses the provider's read-only or plan mode;
- has a finite timeout;
- returns exit code zero;
- records `Live Probe: PASS` and `Secret Values Recorded: NO` in `AGENT_PROVIDER_READINESS.md`.

Network, quota, billing, region, account, and provider outages cannot be bypassed. The provider remains non-ready until a real retry passes.

## Audit integration

An audit declaring `Audit Mode: EXTERNAL_PROVIDER` must reference the canonical `AGENT_PROVIDER_READINESS.md` and its SHA-256 in both `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`. The readiness artifact must name a non-built-in provider and contain:

- `Provider Mode: EXTERNAL_CLI`
- `Provider State: READY`
- `Ready: YES`
- `Live Probe: PASS`
- `Secret Values Recorded: NO`

External model output is untrusted review input. It cannot modify implementation, approve itself, waive acceptance controls, or override repository evidence. The normal sealed-packet, fresh-context, read-only, identity, coverage, and findings gates still apply.

