# Acceptance Rules

Acceptance is requirement validation, not merely test execution.

Before ACCEPTED/VERIFIED_DONE:
1. Re-read original Requirement Contract.
2. Map each acceptance criterion to implementation evidence.
3. Confirm all material affected layers/consumers are classified.
4. Confirm no required path is mocked/faked/placeholder production behavior.
5. Confirm regression checks proportionate to the impact.
6. Confirm unresolved consumer handoffs keep status partial/pending.
7. Confirm evidence actually exists (test output, code/diff, screenshots, contract checks, etc.).
8. For any UI impact, require `validate_ui_fidelity.py --phase accept` to pass. Functional usability, build success, interaction success, or approximate visual similarity cannot override a failed fidelity gate.
9. For any UI impact, require `validate_ui_capabilities.py --phase accept` to pass. Visual fidelity cannot override unresolved backend capabilities, fake/placeholder production interactions, unverified capability requests or missing end-to-end evidence.
10. If `BACKEND_COORDINATION_REPORT.md` contains OPEN items, output them to the user and keep the UI decision BLOCKED/PARTIAL.
11. For any UI impact, require `validate_ui_adaptive.py --phase accept` to pass. Single-viewport fidelity cannot override missing REQUIRED device evidence, inconsistent component families, broken input modes, overflow/clipping or failed business operations.
12. Seal the final evidence in `AUDIT_PACKET.md`, then require a different fresh-context, read-only Agent to produce `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md` under `.ai/rules/THIRD_PARTY_AUDIT_RULES.md`.
13. Require `validate_third_party_audit.py` to pass with zero open CRITICAL/HIGH findings, every required review axis PASS, and every acceptance criterion independently covered. Implementer self-review, tests, or security approval cannot waive this gate.
14. Require every routed behavior task's observed RED/GREEN/REFACTOR/REGRESSION evidence to pass `validate_execution_discipline.py`.
15. Require every implementation task to have a unique fresh implementer and two distinct fresh read-only PASS reviews bound to the same final snapshots.
16. When Workflow Diagnosis Gate is REQUIRED, require a validated CLEAR diagnosis; a valid BLOCKED diagnostic report is not acceptance.

Allowed decisions:
- ACCEPTED
- PARTIAL
- BLOCKED
- FALSE_COMPLETION
- REJECTED_FOR_REWORK
