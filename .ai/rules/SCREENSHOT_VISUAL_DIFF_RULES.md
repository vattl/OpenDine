# Screenshot Visual Diff Rules

## Purpose

Make prototype-to-production UI acceptance evidence-based by comparing real rendered screenshots under controlled conditions.

## 1. Screenshot Comparison Is Evidence, Not Pixel Worship

The goal is visual fidelity, not mathematically identical raster output across machines.

Programmatic pixel differences can be caused by:

- font antialiasing
- OS font rendering
- device pixel ratio
- browser rasterization
- subpixel layout
- image decoding

Use programmatic diff to locate suspicious regions, then use structural and visual judgment to classify whether the difference is meaningful.

## 2. Equivalent Capture Conditions

Meaningful reference comparisons require equivalent conditions whenever practical:

- viewport
- browser engine
- zoom
- theme
- locale
- data state
- scroll position
- loaded fonts
- stable animations

Record deviations from these conditions in the report.

## 3. Reference Viewport

Every approved structural prototype should define at least one Reference Viewport.

At the Reference Viewport:

- structure must match
- component presence/absence must match
- major geometry and proportions should closely match
- spacing rhythm and density should closely match

At other viewports, use Responsive Fidelity rather than pixel identity.

## 4. Comparison Layers

Perform visual verification in layers:

### Layer A — Structural

- page shell
- section order
- required regions
- removed regions
- duplicate regions

### Layer B — Geometry

- bounding boxes
- width/height relationships
- card proportions
- toolbar/table proportions
- whitespace distribution

### Layer C — Typography and Spacing

- hierarchy
- scale relationships
- line-height
- gaps/padding

### Layer D — Surface Styling

- colors
- borders
- radii
- shadows
- icon treatment

### Layer E — Rendering Variance

Ignore harmless raster-level noise after higher-level structure is confirmed.

## 5. Hard Failures

The following normally fail visual acceptance regardless of aggregate score:

- missing approved major section
- legacy section still rendered after REMOVE/REPLACE
- wrong page shell or major layout mode
- primary action moved to materially wrong hierarchy
- major clipping or overlap
- unusable text/control scale
- desktop prototype unintentionally rendered in compact/mobile density at the same reference viewport

## 6. Programmatic Metrics

If a script reports pixel-difference ratio, treat it as a diagnostic signal only.

Do not set a universal pixel-difference threshold across all UI.

More useful evidence includes:

- changed-region bounding boxes
- large connected change areas
- image dimension equality
- overlay inspection
- edge/geometry displacement

## 7. Dynamic Content Masks

If stable comparison is blocked by dynamic regions, define masks/exclusions for items such as:

- timestamps
- randomized images
- live counters
- animated charts
- cursors

Masks must be narrow and justified. Do not mask large layout regions merely to force a pass.

## 8. Approved Prototype Is Immutable During Verification

Do not alter the approved reference to reduce diff.

If design intent changes:

1. revise prototype
2. obtain approval
3. create a new reference screenshot
4. continue production implementation

## 9. Correction Priority

Fix deltas in this order unless evidence suggests otherwise:

1. structural
2. major geometry/proportion
3. density
4. spacing/alignment
5. typography
6. surface/color details
7. raster-level variance

## 10. Evidence Retention

For material UI changes, retain at least:

- prototype screenshot
- latest production screenshot
- final diff/overlay when generated
- visual verification report

Store them under `design/visual-verification/<UI-ID>/` or an equivalent project-approved path.
