# Baseline History

Record Project Baseline (`PB-n`) and Design System (`DS-n`) changes only after intentional accepted changes.

## 2026-10-23 — PB-2

- Promoted the WI-058 accepted invariant baseline with explicit `ENFORCED` and `TARGET` states.
- Preserved the existing payment and KDS invariants and added order-time, order-version, server-pricing, table-amount, combo-pricing and approval-binding rules.
- Added a deterministic backend contract inventory and the WI-059～WI-069 governance roadmap.
- WI-060 established `ApprovalService / ApprovalTokenEnvelopeCipher` as the approval-token lifecycle owner, removed directly usable QR token plaintext from persistence, and recorded the shared-key multi-instance invariant.

## 2026-10-15 — PB-1 / DS-1

- Initialized the server repository baseline from manifests, runtime entry points, representative payment/KDS/report/security modules, migrations, API contracts and tests.
- Recorded DS-1 as backend-owned UI not applicable; future consumer UI changes still require the full HTML prototype gate in the relevant repository.
