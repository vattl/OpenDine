# Measured UI Specification

UI ID: UI-DAILY-SEQUENCE-001

Prototype: `daily-close-sequence.html`

Approved Revision: review candidate v1

Target Viewport: 390×844

Measurement Status: COMPLETE

Material UNKNOWN Count: 0

Reference Viewport: 390×844 CSS pixels

Measurement Confidence: HIGH

## 1. Page Geometry

Viewport Width: 390px

Viewport Height: 844px

Content Max Width: 480px

Horizontal Page Padding: 14px

Top Padding: 12px after app bar

Bottom Padding: 28px

Primary Section Gap: 12px

## 2. Header

Header Height / Natural Height: 56px

Title Font Size: 18px

Title Weight: 700

Subtitle Font Size: 12px

Title-to-Subtitle Gap: 0

Header Bottom Gap: 12px

## 3. Tabs / Navigation

Height: not applicable

Item Gap: not applicable

Horizontal Padding: not applicable

Radius: not applicable

Typography: not applicable

Bottom Gap: not applicable

## 4. Summary / Statistics

Columns: 2

Grid Gap: 8px

Card Height: natural, minimum 70px

Card Padding X: 12px

Card Padding Y: 12px

Label Font Size: 12px

Value Font Size: 20px

Value Weight: 700

Radius: 8px

## 5. Toolbar / Search / Actions

Toolbar Height: 44px primary action

Search Width / Flex Ratio: not applicable

Input Height: not applicable

Primary Button Height: 48px

Secondary Button Height: 44px

Button Horizontal Padding: 16px

Action Gap: 8px

Toolbar Bottom Gap: 12px

## 6. Table / List

Table Header Height: not applicable

Row Height: sequence row 58px

Cell Horizontal Padding: 8px

Avatar / Icon Size: 18px

Header Font Size: 12px

Body Font Size: 14px

Column Proportions: equal sequence nodes

Table Radius: 8px

## 7. Typography Hierarchy

Page Title: 18/700

Section Title: 14/700

Body: 14/1.55

Metadata: 12/1.5

Label: 12/600

Numeric Emphasis: 20–24/700 tabular

## 8. Visual Density

Selected: COMFORTABLE

Approximate Visible Rows at Target Viewport: all primary close context and action visible

## 9. Color / Border / Shadow

Background: #F4F4F2

Surface: #FFFFFF

Border: #E4E4E0

Primary Accent: #EA580C

Status Colors: success #166534, warning #B45309, danger #B91C1C

Shadow Policy: subtle header only; cards use borders

## 10. Responsive Measurements

### 320–480px

Target behavior: single column, full-width cards and action.

Changed dimensions: summary remains two equal columns down to 320px.

Collapsed regions: none.

## 11. Must Match Closely

- date-first hierarchy
- sequence backlog notice and two-node progression
- date-specific primary action label
- existing mobile color tokens and card spacing

## 12. Allowed Adaptation

- browser/font rendering
- Material icon substitution for prototype SVG
- minor sub-pixel border differences

## 13. Production Token Mapping

| Prototype Constraint | Target Value | Production Token / Component | Status |
|---|---:|---|---|
| page padding | 14px | `MobileMetrics.pagePadding` | VERIFIED |
| card radius | 8px | `MobileMetrics.radius` | VERIFIED |
| accent | #EA580C | `MobileColors.brand` | VERIFIED |
| surface | #FFFFFF | `MobileColors.surface` | VERIFIED |

## 14. Measurement Notes

- Prototype fixture is intentionally one-day backlog to make the defect state reviewable.
