# UI Acceptance Standard

## Purpose

Define the default production acceptance gate for UI work.

## Acceptance Layers

1. Structural fidelity
2. Screenshot visual fidelity at approved Reference Viewport
3. Responsive fidelity across relevant viewport classes
4. Content stress behavior
5. Interaction state behavior
6. Accessibility
7. Legacy cleanup
8. Functional safety

## Screenshot Gate

For UI work with an approved HTML prototype/reference, capture both prototype and production at equivalent Reference Viewport conditions and compare them.

Required evidence when tooling permits:

- prototype screenshot
- production screenshot
- visual diff/overlay
- Screenshot Visual Diff Report

Programmatic pixel difference is diagnostic, not the acceptance decision.

## Hard Gates

The following must pass. Material platform constraints may be recorded as explicit accepted variances, but they do not waive prototype approval or the fidelity gate:

- major structure/presence matches approved target
- REMOVE / REPLACE legacy UI is absent
- no critical clipping/overlap
- primary task/action hierarchy is preserved
- production does not use materially wrong density/scale at the reference viewport
- required responsive modes remain usable
- critical interaction states work

## Fidelity Scoring

Scores support prioritization but do not override hard failures.

Recommended dimensions:

- Structure: 0–100
- Geometry / Proportion: 0–100
- Spacing: 0–100
- Typography: 0–100
- Alignment: 0–100
- Density: 0–100
- Surface / Token Fidelity: 0–100

## Responsive Rule

Only the approved Reference Viewport should be judged for close screenshot fidelity unless multiple references exist.

Other viewports are judged on responsive relationships, hierarchy, usability, overflow, density, and breakpoint behavior.

## Decision States

- APPROVED
- APPROVED_WITH_ACCEPTED_VARIANCES
- CORRECTION_REQUIRED
- BLOCKED
