# Prototype-to-Code Rules

## Purpose

Prevent visual drift when converting an approved HTML prototype into production React/Vue/Svelte/etc. code.

## 1. Do Not Treat Prototype as a Loose Reference

For every UI-impacting task, the user-approved HTML prototype is the target design artifact.

Before implementation, extract measurable constraints and map prototype regions to production components.

---

## 2. Required Handoff Artifacts

For every UI-impacting change, create:

- `MEASURED_UI_SPEC.md`
- `UI_IMPLEMENTATION_MAP.md`
- `STRUCTURAL_DIFF.md`
- approved prototype reference
- final `SCREENSHOT_VISUAL_DIFF_REPORT.md`
- `PROTOTYPE_INTERACTION_CONTRACT.md`
- `BACKEND_COORDINATION_REPORT.md`
- `ADAPTIVE_UI_CONTRACT.md`
- final `DEVICE_UX_VERIFICATION_REPORT.md`

Suggested location:

`design/prototypes/UIXXX-name/`

---

## 3. Production Mapping

Map every major prototype region to its production destination.

Before production UI editing:

- `Mapping Status: COMPLETE`
- `All Prototype Regions Mapped: YES`
- `Unmapped Prototype Regions: 0`
- `Legacy Structure Reused Without Approval: NO`
- `Plan Status: APPROVED`
- `Unclassified Legacy Regions: 0`

Run the translation plan gate. No production UI edit is authorized while it fails.

Also run the interaction capability plan gate. Every prototype interaction must map to a real existing capability or an assigned backend request. A visual control with no real production path is not a completed mapping.

Run the adaptive UI plan gate. Every REQUIRED terminal/input/context profile needs prototype evidence; every component family needs resolved semantic variants and tokens; every promised business operation needs a complete device-specific path. A breakpoint with missing actions or arbitrary control sizes is not a completed translation plan.

Example:

| Prototype Region | Production Component | Operation | Critical Constraints |
|---|---|---|---|
| summary-grid | MemberStats.tsx | MODIFY | 4 columns, target gap/height |
| search-toolbar | MemberToolbar.tsx | REPLACE | target control scale |
| member-table | MemberTable.tsx | MODIFY | target header/row density |
| legacy-tabs | production page | REMOVE | must not render |

---

## 4. Preserve Business Logic, Not Accidental Styling

Reuse existing production components and logic where safe.

However, distinguish:

BUSINESS_BEHAVIOR_TO_PRESERVE
from
LEGACY_VISUAL_STYLE_TO_REPLACE

Do not preserve obsolete compactness, wrappers, spacing, or layout merely because they live inside an existing business component.

Refactor presentation boundaries when required while preserving business behavior.

---

## 5. Token Mapping

For each important measured prototype value, identify the production implementation source:

- existing token
- existing component variant
- new scoped token
- responsive calculation

Do not leave major dimensions to incidental browser defaults.

---

## 6. Same Viewport Comparison

Compare prototype and production using the same viewport dimensions whenever possible.

Do not compare a 1900px-wide prototype to a 1440px production screenshot and conclude the proportions match.

---

## 7. Realistic Data

Use realistic production-like content density for comparison.

Different row counts, very long names, empty states, or missing labels can make a layout appear falsely similar or different.

The prototype need not contain identical data, but density and content shape should be representative.

---

## 8. No Blind Copying

Do not copy prototype HTML/CSS directly into production when doing so:

- bypasses component architecture
- duplicates business logic
- creates parallel design systems
- introduces inaccessible markup
- conflicts with framework patterns

Transfer the measured design intent, not accidental prototype implementation details.

---

## 9. Completion

Prototype-to-code handoff is complete only when the production implementation has been visually compared against the approved target and material deltas are resolved or explicitly accepted.

Run:

```bash
python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir <artifact-dir> --phase accept
```

Functional correctness does not override this result. A failed fidelity gate requires correction and blocks UI acceptance.

Visual fidelity does not override functional contract gaps. Run `validate_ui_capabilities.py --phase accept`; any unresolved backend item, unverified integration, missing E2E evidence or production fake blocks UI acceptance.

Visual and functional fidelity do not override device UX failures. Run `validate_ui_adaptive.py --phase accept`; any missing REQUIRED profile evidence, component consistency violation, unintended overflow/clipping, input-mode failure or failed business operation blocks UI acceptance.
