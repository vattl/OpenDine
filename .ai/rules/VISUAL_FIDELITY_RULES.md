# Visual Fidelity Rules

## Purpose

Ensure that an approved UI prototype is translated into production code with matching structure, scale, density, spacing, typography hierarchy, and proportions rather than only approximate visual resemblance.

## Core Principle

Prototype approval freezes more than layout intent.

For any UI work, the approved HTML prototype establishes a measurable target for:

- page proportions
- section hierarchy
- component scale
- spacing rhythm
- typography hierarchy
- control dimensions
- table/list density
- alignment
- responsive behavior

Production implementation is not complete when "the same elements exist".

It is complete when the rendered production UI reasonably matches the approved target.

---

## 1. Measure Before Production Implementation

After prototype approval and before production implementation, create a Measured UI Specification when fidelity matters.

Measure or explicitly estimate from the approved prototype:

- target viewport
- page/content width
- horizontal padding
- vertical section spacing
- major component height
- grid columns and gaps
- control height
- table header/row height
- avatar/icon size
- typography size/weight/line-height
- border radius
- density

Do not rely only on qualitative statements such as "large card" or "compact table".

---

## 2. Prototype Values vs Existing Design System

Existing production tokens should be reused when they preserve the approved visual result.

Do not silently substitute a smaller or denser existing token merely because it is already available.

Example failure:

Approved prototype:
- stat card height ~148px
- toolbar/control height ~64-72px
- table row height ~80px

Production system defaults:
- card padding 16px
- control height 40px
- table row height 48px

Blind reuse of the defaults materially changes the approved design and is not acceptable.

When the prototype and existing token system conflict:

1. identify the conflict
2. determine whether a suitable existing token can match the target
3. otherwise introduce the smallest justified page/component token extension
4. document the reason

Do not distort the target merely to avoid adding a justified token.

---

## 3. Fidelity Dimensions

Visual verification must consider at least:

### Structure
- section order
- component hierarchy
- presence/absence
- layout regions

### Scale
- card height
- control height
- table density
- element size relationships

### Spacing
- page padding
- section gaps
- component padding
- grid gaps

### Typography
- title/body/meta hierarchy
- size relationship
- weight relationship
- line-height where material

### Alignment
- baseline alignment
- columns
- action grouping
- edge alignment

### Proportion
- search area vs actions
- cards vs content
- table vs surrounding chrome
- whitespace distribution

### Density
- number of visible rows/items
- vertical compression
- interaction target sizing

---

## 4. Default Tolerance Guidance

These are default engineering tolerances, not absolute universal laws.

For an approved desktop prototype:

- Structure: must match unless adaptation is explicitly approved
- Major dimensions: target within approximately ±5%
- Major spacing: target within approximately ±8px
- Typography: target within approximately ±2px where exact tokens are unavailable
- Grid/column count: must match at the same target viewport
- Presence/absence: exact
- Major alignment: exact enough that no visible drift is apparent

If the user requests pixel-level reproduction, tighten the tolerances.

If responsive constraints require deviation, document the adaptive rule instead of silently changing the design.

---

## 5. Rendered Comparison Is Required When Available

For UI work governed by an approved HTML prototype, do not stop at source-code inspection.

When the environment can render or capture the page:

1. render the approved prototype at the target viewport
2. render production at the same viewport
3. compare them side-by-side
4. record fidelity differences
5. correct material differences
6. repeat until the fidelity gate passes

If rendering is unavailable, perform the strongest available DOM/style/token comparison and state the limitation.

Never claim visual fidelity was verified if no visual or equivalent measurable comparison was performed.

---

## 6. Correction Loop

Production UI may require more than one implementation pass.

Use:

IMPLEMENT
→ RENDER
→ COMPARE
→ CLASSIFY DELTAS
→ CORRECT
→ RENDER AGAIN

Do not treat the first successful build as final visual completion.

Classify visual deltas:

- STRUCTURAL
- SCALE
- SPACING
- TYPOGRAPHY
- ALIGNMENT
- COLOR/TOKEN
- RESPONSIVE
- CONTENT_DENSITY

Fix the highest-impact deltas first.

---

## 7. Negative Fidelity Verification

Verify not only what exists, but what must no longer exist.

Examples:

- old compact row-height token is no longer applied to this page
- old two-column wrapper is absent
- legacy toolbar does not render
- duplicate old/new controls do not coexist
- old page-level CSS does not override approved dimensions

---

## 8. Fidelity vs Functional Safety

Visual fidelity must not break business behavior, accessibility, or platform constraints.

If exact reproduction conflicts with a genuine functional requirement:

1. preserve correctness
2. document the constraint
3. choose the closest safe visual result
4. surface the deviation instead of hiding it

---

## 9. Fidelity Completion Rule

For UI work governed by an approved HTML prototype, visual implementation is not DONE unless:

- approved HTML prototype exists
- measured UI spec exists when fidelity is material
- target-to-production mapping is clear
- production renders with correct structure
- material scale/spacing/typography differences are resolved
- legacy UI is removed where required
- responsive behavior is validated where relevant
- visual comparison result is PASS or accepted deviation is documented

## 11. v3.2 Screenshot-to-Screenshot Acceptance

For approved structural prototypes, visual fidelity should be proven with real rendered screenshots when capture tooling is available.

Use the approved prototype screenshot and production screenshot at the same Reference Viewport, then apply `.ai/rules/SCREENSHOT_VISUAL_DIFF_RULES.md`.

Programmatic visual diff is only diagnostic evidence. Final acceptance combines screenshot evidence with structural/visual reasoning.
