# UI Fidelity Contract Rules

## Purpose

Freeze the approved design into explicit contracts so production code does not drift from content, elements, style, geometry, or responsive behavior.

## Lock Dimensions

For STRUCTURAL approved UI, lock relevant dimensions:
- Content
- Elements
- Structure
- Style/Tokens
- Fonts/Icons
- Component Mapping
- Responsive Rules
- Golden Screenshot at reference viewport

## Fidelity Categories

Verification should distinguish:
- Content Fidelity
- Element Fidelity
- Structural Fidelity
- Geometry Fidelity
- Style Fidelity
- Responsive Fidelity
- Interaction Fidelity

Content, required elements, and required structure should normally be 100% unless an accepted deviation exists.

## Shared Fixture

Prototype and production comparison should use equivalent deterministic fixture data where feasible.

Do not compare an empty production page to a dense approved prototype and then infer visual fidelity.

## Golden Reference

After approval, capture/freeze a golden reference. Avoid regenerating the target from mutable prototype code during every verification run.

## Geometry + Screenshot + Judgment

Prefer layered verification:
1. geometry/structure comparison
2. screenshot/region diff
3. visual judgment to classify material vs rendering-only differences

Pixel differences alone are not acceptance criteria.
