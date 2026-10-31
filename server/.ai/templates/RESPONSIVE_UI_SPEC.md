# Responsive UI Specification

This specification records layout relationships. Device/input/context scope, component variants and business-operation continuity are authoritative in `ADAPTIVE_UI_CONTRACT.md`.

UI ID:
Prototype:

## Reference Viewports

| Name | Width | Height | Fidelity |
|---|---:|---:|---|
| Primary |  |  | HIGH |

## Experience Profile Links

| Profile ID | Terminal / Platform | Input | Orientation | Support | Adaptive Contract Row |
|---|---|---|---|---|---|
|  |  |  |  | REQUIRED / OPTIONAL / UNSUPPORTED |  |

## Layout Relationships

- content max behavior:
- horizontal padding behavior:
- section rhythm:
- density:

## Responsive Modes

### Compact
Range:
Structure:
Density:

### Standard
Range:
Structure:
Density:

### Wide
Range:
Structure:
Density:

## Typography Relationships

- page title vs body:
- stat value vs label:
- metadata hierarchy:

## Component Sizing

Use tokens/relationships rather than universal fixed pixels.

Record visual size and interaction hit target separately. Component family/variant tokens must match `ADAPTIVE_UI_CONTRACT.md`; do not improvise per-screen button/input/icon values.

## Must Preserve

- hierarchy
- primary actions
- information order
- readability
- promised business operations
- input/focus usability

## Allowed Adaptation

- wrapping
- column count
- fluid gaps
- content-driven height
