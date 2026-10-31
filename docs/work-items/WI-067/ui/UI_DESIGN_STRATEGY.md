# UI Design Strategy — UI-DAILY-SEQUENCE-001

## UI Intent

REFINE

## Product Context

- Product type: restaurant cashier/owner mobile management app
- Target device(s): mobile, reference 390×844
- Main usage environment: owner/manager closing the business day

## User Goal

- Primary goal: confidently close the earliest outstanding business day.
- Primary information: authoritative business date, window, sequence backlog and precheck state.
- Primary action: close that exact business day.
- Secondary actions/information: revenue summary, refresh, Z report after close.

## Information Hierarchy

- L1: earliest pending business day and close action.
- L2: sequence/backlog explanation and precheck result.
- L3: sales/discount/refund/order summary.
- L4: window and permission metadata.

## Information Architecture

Keep the current single-column page. Upgrade the existing date card into a sequence context card; add one compact backlog notice and a two-step date progression row.

## Density

COMFORTABLE

## Visual Hierarchy

The authoritative date is the largest non-monetary value. The destructive close button remains the strongest action. Orange communicates sequence attention; red remains reserved for blockers/destructive confirmation.

## Spacing Strategy

Reuse 14px page/card padding and 12–16px section gaps from the mobile design system.

## Typography Strategy

Reuse Noto Sans SC/PingFang SC/Microsoft YaHei stack, 18px title, 22px key values, 14px body and 12px metadata.

## Action Hierarchy

Primary: “结算 10月24日”. Secondary: refresh icon. Historical report remains after successful close, not a competing initial action.

## Progressive Disclosure

Show only the count and next step initially; detailed financial summary remains in existing cards.

## State Coverage

- historical day pending with one later day locked
- precheck passed
- blocked/error text pattern
- after-close advancement described in sequence row

## Responsive Strategy

Single column from 320–480px; no horizontal overflow; progress row wraps labels below nodes on narrow screens.

## Implementation Constraints

Flutter Material widgets and existing `MobileColors`, `MobileMetrics`, `MobileTypography`; no new external package. Backend must provide authoritative date/backlog fields.

## Design Risks

- Do not imply today is closable until yesterday succeeds.
- Do not let prototype mock dates become production constants.
- Avoid presenting sequence warning as a financial error.
