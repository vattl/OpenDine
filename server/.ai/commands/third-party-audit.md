# /third-party-audit

Run the mandatory independent Agent cross-audit before Work Item acceptance.

Input: Work Item directory.

1. Confirm implementation, self-verification, internal review, security review, and test evidence are complete.
2. Finalize the acceptance criteria and create `AUDIT_PACKET.md` from the template.
3. Inventory the final evidence and record SHA-256 for every item; set `Packet Status: SEALED` only after the inventory is immutable.
4. If no audit provider is selected, run `/agent-provider` and let the user choose the built-in Agent or a registered external CLI. For an external provider, require `AGENT_PROVIDER_READINESS.md` with a successful bounded live probe before dispatch.
5. Start a different Agent with fresh context. Give it the sealed packet, no implementer reasoning, and no implementation-edit permission.
6. The auditor writes an actual `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`, covering every required axis and every acceptance criterion. For `EXTERNAL_PROVIDER`, both artifacts also reference the readiness artifact and SHA-256.
7. If the auditor reports a valid finding, return the Work Item to implementation. After correction, reseal a new packet and run a new independent audit.
   Before overwriting canonical artifacts, archive the blocked receipt/report under `audit-history/<session-id>/`. Require code/configuration remediation, retest evidence and `AUDIT_REMEDIATION.md`; do not close findings by editing audit prose.
8. Run:

   `python .ai/scripts/validate_third_party_audit.py --root . --work-item <dir>`

9. Set `Third Party Audit: PASS` only when the validator passes. Otherwise keep acceptance blocked.

Do not treat the audit as a request for the reviewer to finish the implementation. The auditor reports; the implementation owner fixes and resubmits.
