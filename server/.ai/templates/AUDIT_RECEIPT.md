# Third-Party Audit Receipt — WI-XXX

Audit Session ID: SESSION-ID
Auditor Agent: AUDITOR-ID
Auditor Provider / Model: PROVIDER / MODEL
Started At: ISO-8601 timestamp
Completed At: ISO-8601 timestamp
Context Mode: FRESH
Mutation Permission: NONE / AUDIT_ARTIFACTS_ONLY
Reviewed Packet: AUDIT_PACKET.md
Provider Readiness: NOT_APPLICABLE / AGENT_PROVIDER_READINESS.md
Provider Readiness SHA256: NOT_APPLICABLE / 64-character-sha256

## Invocation Record

Record how the independent Agent was started and the exact scope it was given. Do not include hidden reasoning or secrets.

The canonical filename is `AUDIT_RECEIPT.md`. All identity/provider/session fields must be concrete rather than template tokens. ISO-8601 timestamps, `Reviewed Packet`, and this non-empty invocation record are mandatory and are validated against the report. Replace this instruction with the actual dispatch mechanism, canonical auditor identity, and assigned scope; unchanged template boilerplate is invalid.

## Trust Note

This receipt is repository evidence of the declared audit session. Unless signed by the runtime/provider, it is not cryptographic provider attestation.

For `Audit Mode: EXTERNAL_PROVIDER`, both Provider Readiness fields are mandatory and must match the report. Built-in and cross-model audits may use `NOT_APPLICABLE`.

