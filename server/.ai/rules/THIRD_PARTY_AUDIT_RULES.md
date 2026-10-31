# Third-Party Agent Cross-Audit Rules

Third-party Agent cross-audit is a mandatory, independent acceptance control. It does not replace implementer self-review, security review, test evidence, UI fidelity approval, human approval, integration, or release verification.

## Required timing

Run the audit after implementation, self-verification, internal review, security review, and test evidence are complete, but before a Work Item may become `ACCEPTED`.

The implementer must first create a sealed `AUDIT_PACKET.md`. The auditor reviews only that declared snapshot and its referenced evidence. Any audited evidence changed after sealing invalidates the audit and requires a new packet and a new audit.

## Independence requirements

The auditor must:

- be a different Agent identity from the implementer;
- start with fresh context rather than inheriting the implementer's reasoning;
- have no permission to edit implementation files;
- operate adversarially and seek omissions, false completion, weak evidence, and acceptance gaps;
- record a concrete provider/model and audit session identity;
- write only `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md` when audit-artifact writing is allowed.

An internal second pass by the same Agent is not third-party review. A different model/provider is preferred for high-risk work, but a genuinely separate fresh-context Agent is valid as `INDEPENDENT_AGENT` when cross-model execution is unavailable.

When the operator has not selected an audit provider, invoke `/agent-provider` and offer the built-in Agent or the registered external CLIs. External selection is never proof of readiness: follow `.ai/rules/AGENT_PROVIDER_RULES.md` until a bounded live probe passes or the user cancels.

## Required artifacts

1. `AUDIT_PACKET.md` — sealed evidence inventory, SHA-256 hashes, implementer identity, reviewed snapshot, material unknown count, the complete acceptance contract, and the canonical acceptance-contract SHA-256 derived from exact `WORK_ITEM.md` criterion text.
2. `AUDIT_RECEIPT.md` — canonical actual invocation/session receipt identifying the auditor, provider/model, timestamps, reviewed packet, context mode, mutation permission, and a non-empty invocation record. An arbitrary substitute filename is invalid.
3. `THIRD_PARTY_AUDIT.md` — independent decision, reviewed packet/receipt hashes, required review axes, criterion-by-criterion audit, findings, and reverification.
4. `AGENT_PROVIDER_READINESS.md` — mandatory only for `EXTERNAL_PROVIDER`; records a real live-probe PASS without secret values and is hash-bound into both receipt and report.

The required review axes are:

- `REQUIREMENT`
- `CORRECTNESS`
- `ARCHITECTURE`
- `SECURITY`
- `TEST_EVIDENCE`
- `FALSE_COMPLETION`
- `ACCEPTANCE`

## Passing conditions

The third-party audit gate passes only when:

- the packet status is `SEALED` and every inventoried evidence hash still matches;
- the canonical IDs and exact text of every `WORK_ITEM.md` acceptance criterion match the packet and its contract hash;
- every comma-separated evidence reference in the packet, review axes, and criterion audit resolves individually to the inventory; one valid reference cannot mask an invented one;
- implementer and auditor identities differ;
- fresh-context and read-only constraints are confirmed;
- the receipt and report identify the same real audit session;
- external-provider audits reference the same canonical readiness artifact/hash, with `Provider State: READY`, `Ready: YES`, `Live Probe: PASS`, and no recorded secrets;
- every required review axis is `PASS`;
- every original acceptance criterion is independently reviewed and `PASS`;
- evidence integrity is `VERIFIED` and acceptance coverage is `COMPLETE`;
- open `CRITICAL` and `HIGH` findings are both zero;
- all other required findings are closed and reverified;
- `.ai/scripts/validate_third_party_audit.py` passes.

Any failure keeps `Third Party Audit: BLOCKED` or `PENDING` and forbids `ACCEPTED`.

Template identity/session/provider tokens and unchanged invocation instructions are never real session evidence. Severity `NONE` is reserved for the sole canonical `AUDIT-NONE` row when there are no findings; it cannot hide an open issue.

## Trust boundary

The repository validator proves consistency of the declared identities, session receipt, immutable evidence hashes, coverage tables, and decisions. It cannot cryptographically prove that a provider actually executed the session unless the runtime supplies a signed receipt. Never describe an unsigned Markdown receipt as cryptographic provider attestation.

An external CLI and its output are untrusted. The provider may report findings but may not edit implementation, change the sealed packet, self-approve, or waive any normal acceptance gate.

