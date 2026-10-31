# AI Development OS v4.3

**Edition:** Prototype Enforcement Full Edition

v4.3 is a full superset of v4.2 and this package policy enforces HTML prototype review for all UI-impacting work.

New in v4.3:
- sets `PROTOTYPE_REQUIREMENT=REQUIRED` and `PROTOTYPE_MODE=HTML` for REFINE/REFACTOR/REDESIGN and MINOR/STRUCTURAL UI impact
- requires explicit user review with `Approval Status: APPROVED`; per-Work-Item waivers do not pass
- design strategy, blueprint, component map and implementation plan no longer count as prototype evidence
- keeps target-stack/component feasibility mapping while using HTML as the mandatory review artifact
- distinct design-direction approval vs prototype approval
- Prototype Coverage Matrix for primary, secondary, tertiary pages and dialogs
- prototype screenshot/visual-reference evidence
- stronger `IMPLEMENTATION_READY` and pre-edit blocking
- hardened UI gate validator based on artifact evidence
- mandatory prototype-to-production translation plan gate before production UI edits
- strict post-implementation fidelity gate with same-viewport evidence, legacy-removal proof and final user confirmation

No v4.2 capability is intentionally removed.
