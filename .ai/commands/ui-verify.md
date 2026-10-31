# /ui-verify — Screenshot-to-Screenshot UI Acceptance Gate

Use this command after production UI implementation. It is mandatory for every UI-impacting change and ends by running the strict fidelity gate; without a PASS, UI acceptance is forbidden.

Input:

$ARGUMENTS

---

# Objective

Verify the rendered production UI against the approved prototype using real screenshots, not source-code resemblance alone.

The default flow is:

APPROVED PROTOTYPE
→ REFERENCE VIEWPORT
→ CONTROLLED TEST DATA
→ PROTOTYPE SCREENSHOT
→ PRODUCTION SCREENSHOT
→ PROGRAMMATIC VISUAL DIFF
→ AI VISUAL REVIEW
→ DELTA CLASSIFICATION
→ CORRECTION LOOP
→ MULTI-VIEWPORT RESPONSIVE CHECK
→ UI ACCEPTANCE DECISION

A UI must not be marked visually accepted merely because the same components exist.

---

# Phase 0 — Preconditions

Locate or determine:

- approved prototype/reference
- prototype approval record
- production route/page
- Reference Viewport
- browser zoom / device scale assumptions where relevant
- stable test data / fixture state
- authentication state required to render production
- dynamic regions that need normalization

If no approved visual target exists, this command may still perform visual QA, but it must not claim prototype fidelity.

---

# Phase 1 — Normalize the Comparison Environment

Prototype and production screenshots must be captured under equivalent conditions whenever possible:

- same viewport width and height
- same browser engine
- same zoom
- same device scale factor where controllable
- same theme
- same locale
- same representative content
- same scroll position
- same loading-complete condition

Freeze or normalize unstable visual regions when practical:

- current timestamps
- random avatars
- rotating banners
- animated counters
- blinking cursors
- loading skeletons
- asynchronous content still changing

Do not compare screenshots from materially different environments and then interpret scale differences as implementation failures.

---

# Phase 2 — Capture Reference Screenshot

Capture the approved prototype at the Reference Viewport.

Recommended artifact path:

`design/visual-verification/UIXXX/run-YYYYMMDD-HHMM/prototype.png`

Record:

- prototype source
- viewport
- browser
- capture time
- fixture/data profile

---

# Phase 3 — Capture Production Screenshot

Capture the actual production implementation at the same Reference Viewport and equivalent state.

Recommended path:

`design/visual-verification/UIXXX/run-YYYYMMDD-HHMM/production.png`

Do not substitute a component story or isolated screenshot if the approved target represents the whole page unless the verification scope is explicitly component-level.

---

# Phase 4 — Programmatic Visual Diff

When tooling is available, generate:

- `diff.png`
- `overlay.png` when useful
- machine-readable metrics/report

The programmatic diff is a detector, not the final judge.

It may identify:

- large displaced regions
- missing sections
- size drift
- whitespace drift
- color changes
- typography-area changes

Do not fail solely on antialiasing, subpixel font rendering, platform font metrics, or harmless rasterization noise.

Follow `.ai/rules/SCREENSHOT_VISUAL_DIFF_RULES.md`.

---

# Phase 5 — AI Visual Review

Compare prototype.png and production.png visually.

Evaluate separately:

1. STRUCTURE
2. GEOMETRY / SCALE
3. SPACING RHYTHM
4. TYPOGRAPHY HIERARCHY
5. ALIGNMENT / GRID
6. DENSITY
7. COLORS / SURFACES
8. COMPONENT PROPORTIONS
9. LEGACY UI RESIDUE
10. CONTENT FIT

Classify each material delta:

- CRITICAL
- HIGH
- MEDIUM
- LOW
- ACCEPTABLE_RENDERING_VARIANCE

---

# Phase 6 — Fidelity Scoring

Use scoring as decision support, not as a substitute for judgment.

Recommended dimensions:

- Structural fidelity: 0–100
- Geometry/proportion fidelity: 0–100
- Spacing fidelity: 0–100
- Typography fidelity: 0–100
- Density fidelity: 0–100
- Color/token fidelity: 0–100

Hard gates override aggregate scores.

Hard gates for any UI governed by an approved HTML prototype:

- required structure/presence: 100%
- REMOVE/REPLACE legacy absence: 100%
- critical interaction placement: must match intended structure
- no clipping/overflow of critical content

A high aggregate score cannot compensate for a missing header, duplicate old toolbar, wrong page shell, or broken primary action hierarchy.

---

# Phase 7 — Correction Loop

If material visual deltas remain:

CORRECTION_REQUIRED
→ update production implementation
→ run relevant functional checks
→ recapture production screenshot
→ regenerate diff
→ repeat visual review

Do not modify the approved prototype to make a weak production implementation pass unless the user explicitly approves a design change.

If the target design changes, record a new prototype revision/approval first.

---

# Phase 8 — Responsive Verification

Pixel/screenshot fidelity is strict only at the Reference Viewport unless multiple reference targets are approved.

For additional viewports, evaluate responsive fidelity rather than pixel identity.

At minimum consider relevant:

- compact/mobile
- tablet/intermediate
- standard desktop
- wide desktop

Check:

- hierarchy preservation
- breakpoint behavior
- wrapping
- clipping/overflow
- control usability
- content density
- table/list adaptation
- stable primary actions
- declared input modality and focus behavior
- component family/variant consistency
- every business operation promised for that profile
- orientation, safe area, virtual keyboard and resize behavior where applicable

Use `.ai/rules/RESPONSIVE_FIDELITY_RULES.md` and `.ai/rules/ADAPTIVE_UI_UX_RULES.md`.

---

# Phase 9 — Content and Interaction Stress

Before final acceptance, combine visual verification with relevant:

- empty state
- long text
- large values
- many tags/statuses
- loading
- error
- permission state
- realistic table/list density
- hover/focus/disabled/loading interaction states

Screenshot fidelity on ideal mock data alone is not sufficient for production acceptance.

For every approved prototype interaction, verify:

- real production handler/client path exists;
- request/response/error/auth semantics match the contract;
- persistence/shared state/external side effect occurs where required;
- frontend success/error/loading state reflects the real response;
- API_EXTENSION/NEW_API capability request is VERIFIED;
- an end-to-end evidence path is recorded;
- no mock/static/local-only substitute is presented as production behavior.

Run:

```bash
python .ai/scripts/validate_ui_capabilities.py --root . --ui-dir <artifact-dir> --phase accept
```

If blocked, present `BACKEND_COORDINATION_REPORT.md` to the user with interaction, backend need, owner/status and next action. Do not summarize the page as complete.

Create `DEVICE_UX_VERIFICATION_REPORT.md` and run:

```bash
python .ai/scripts/validate_ui_adaptive.py --root . --ui-dir <artifact-dir> --phase accept
```

Every REQUIRED profile and declared operation/profile pair needs real production evidence. Missing profile evidence, inconsistent button/input/icon families, unintended clipping/overflow, failed input/orientation checks or an incomplete business operation blocks UI acceptance.

---

# Phase 10 — Acceptance Decision

Possible outcomes:

APPROVED
APPROVED_WITH_ACCEPTED_VARIANCES
CORRECTION_REQUIRED
BLOCKED

APPROVED requires:

- no unresolved structural mismatch
- no unintended legacy UI residue
- no HIGH/CRITICAL visual delta
- reference viewport fidelity acceptable
- responsive behavior acceptable
- required functional checks still pass
- `Target State Match: YES`
- `Legacy Remaining: NO`
- production screenshot presented to the user
- `User Fidelity Confirmation: APPROVED`
- UI capability acceptance gate PASS
- unresolved required backend capabilities = 0
- production fake/mock/placeholder interactions = 0
- backend coordination status CLEAR
- adaptive UI acceptance gate PASS
- all REQUIRED experience profiles VERIFIED
- component consistency violations = 0
- unintended overflow/clipping = 0
- all declared business operation/profile pairs PASS

Persist a report using `.ai/templates/SCREENSHOT_VISUAL_DIFF_REPORT.md`, keep the mapping/spec/structural artifacts in the same UI evidence directory, and run:

```bash
python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir <artifact-dir> --phase accept
```

`APPROVED_WITH_ACCEPTED_VARIANCES` does not pass the strict gate unless the prototype is revised and re-approved or workflow policy is explicitly changed. The implementing agent may not accept its own material variance.

Update PROJECT_STATE / active UI work with the result.

---

# Output

# UI Visual Verification

UI Work:
Reference Viewport:
Prototype Screenshot:
Production Screenshot:
Diff Artifact:

Structural Fidelity:
Geometry Fidelity:
Spacing Fidelity:
Typography Fidelity:
Density Fidelity:

Critical/High Deltas:
- ...

Accepted Rendering Variances:
- ...

Responsive Result:
Content Stress Result:

Decision:
APPROVED / APPROVED_WITH_ACCEPTED_VARIANCES / CORRECTION_REQUIRED / BLOCKED

Production Presented To User:
User Fidelity Confirmation:

Fidelity Gate:
PASS / BLOCKED

Capability Gate:
PASS / BLOCKED

Adaptive UI Gate:
PASS / BLOCKED

Backend Coordination Report:
Coordination Status: CLEAR / OPEN

Open Backend Items:
- interaction / required API or contract / owner / current status / next action

Next Action:
