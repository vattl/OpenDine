# /ui-implement

Translate an approved and locked HTML UI prototype into production code. Do not run this command for any UI-impacting request before the HTML prototype gate passes with explicit user approval.

## Rules

1. Read the project stack/component capability audit.
2. Read the approved prototype and UI lock/implementation plan.
3. Complete `UI_IMPLEMENTATION_MAP.md`, `MEASURED_UI_SPEC.md`, `STRUCTURAL_DIFF.md`, `PROTOTYPE_INTERACTION_CONTRACT.md`, and `ADAPTIVE_UI_CONTRACT.md` before production UI edits.
4. Map every prototype region and every legacy region in scope; `Unmapped Prototype Regions` and `Unclassified Legacy Regions` must both be 0.
5. Run `python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir <artifact-dir> --phase plan`. A failed plan gate forbids production UI editing.
6. Run `python .ai/scripts/validate_ui_capabilities.py --root . --ui-dir <artifact-dir> --phase plan`. Missing capability requests, unmapped interactions or NOT_SUPPORTED prototype behavior forbid production UI editing.
7. Run `python .ai/scripts/validate_ui_adaptive.py --root . --ui-dir <artifact-dir> --phase plan`. Missing device profiles, unresolved component variants, arbitrary component sizing, missing profile prototype evidence or incomplete business operations forbid production UI editing.
8. Treat production implementation as translation, not redesign.
9. Reuse components only when they preserve the approved intent; familiarity or lower effort is not evidence.
10. Extend/variant/replace components when existing defaults materially distort the design.
11. Implement declared component families and semantic variants consistently; do not improvise button/input/icon sizes per page.
12. Preserve locked content, required elements, hierarchy, fonts/icons, and adaptive behavior.
13. Preserve every business operation promised for each REQUIRED profile, even when its navigation/dialog/table pattern changes.
14. Record any unavoidable Technical Deviation before claiming completion.
15. Implement interaction/API behavior against real cross-layer contracts. A fake button, local-only success, mock response or static server-derived value is forbidden in production.
16. For every API_EXTENSION/NEW_API, either implement backend + frontend in the same vertical slice or keep the UI item BLOCKED and emit `BACKEND_COORDINATION_REPORT.md`.
17. Remove replaced legacy UI after the new path is verified.

## Recommended execution

For complex pages:
- Phase A: Layout Lock — structure, grid, geometry, hierarchy
- Phase B: Visual Skin — typography, color, borders, radius, shadows, states
- Phase C: Interaction + data integration
- Phase D: `/ui-verify`

Do not mark UI work complete without rendered same-viewport verification. Functional usability, successful build, or approximate resemblance cannot substitute for the fidelity gate.
