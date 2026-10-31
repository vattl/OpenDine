# Prototype-to-Production Technical Plan

## Target Stack

Flutter + Riverpod in external same-product repository `my_project_admin_panel/admin_mini`, using shared `shop_core` repository/domain models.

## Prototype Mode

HTML

## HTML Review Entry

Path to `.html` / `.htm`: `daily-close-sequence.html`

## Reason / Scope

Review the visible date authority and sequence feedback before changing production UI. This is a focused refinement, not a page redesign.

## Production Component Mapping

- App bar → existing Flutter `AppBar`.
- Sequence context → existing bordered `Container` plus `StatusTag`/icons.
- Precheck and summary → existing cards.
- Action → existing full-width `FilledButton`.

## New / Extended Components

No shared component required; add a local sequence context section unless reuse proves clean.

## Styling & Token Strategy

Exact existing mobile tokens: brand `#EA580C`, brand soft `#FFF1E6`, canvas `#F4F4F2`, surface `#FFFFFF`, border `#E4E4E0`.

## Font Strategy

System Chinese sans stack matching existing design documentation.

## Icon Strategy

Prototype inline SVG; production Material Icons already used by the page.

## Responsive Implementation

Single `ListView`; progress row uses Expanded/Flexible and stays within page padding.

## Interaction / API Dependencies

See `PROTOTYPE_INTERACTION_CONTRACT.md`. Authority/backlog fields are API_EXTENSION via `../BACKEND_CAPABILITY_REQUEST.md`.

## Backend Coordination

Backend owner is WI-067. Consumer implementation is recorded in `../API_CONSUMER_HANDOFF.md`.

## Known Incompatibilities

Server repository cannot itself provide the Flutter production screenshot; final UI acceptance requires coordinated consumer implementation.

## Mitigation

Treat frontend integration as an explicit cross-repository slice and keep UI acceptance blocked until E2E evidence exists.

## Accepted Tradeoffs

None at review stage.
