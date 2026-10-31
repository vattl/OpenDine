# Adaptive UI Contract

UI ID:
Approved Prototype:
Parent Work Item:

Adaptive Contract Status: DRAFT / COMPLETE
Required Device Profiles: 0
Covered Required Profiles: 0
Unmapped Critical Operations: 0
Unresolved Component Variants: 0
Arbitrary Component Size Values: 0

## Device Experience Profiles

| Profile ID | Terminal / Platform | Viewport | Orientation | Input Modality | Usage Context | Support | Density / Navigation | Prototype Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| PHONE | Mobile Web / iOS / Android | representative width x height | Portrait / Landscape / Both | Touch / Keyboard / Pointer / Mixed | where and how the product is used | REQUIRED / OPTIONAL / UNSUPPORTED | density plus navigation pattern | screenshot or rendered prototype evidence | READY / BLOCKED |

Declare product scope truthfully. A desktop-only, mobile-only or kiosk-only product may have one REQUIRED profile. Do not add unsupported devices merely to satisfy a generic checklist. Every REQUIRED profile needs a representative HTML prototype rendering before production UI editing.

## Component Family Contract

| Component ID | Family / Role | Variant | Profiles | Visual Size Token | Hit Target | Icon Token | Typography Token | Spacing Token | Adaptation | States | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| BTN-PRIMARY | Button / Primary action | touch-prominent | PHONE,TABLET or ALL_REQUIRED | control-lg | platform/context-specific measured target | icon-md | label-md | space-3/4 | sticky action on compact screens | default/focus/pressed/disabled/loading | READY / BLOCKED |

Equivalent controls at the same hierarchy and device profile must share the same family/variant tokens. Visual bounds and interaction hit areas are separate concerns. Do not claim consistency while using unexplained per-component pixel values.

## Business Operation Coverage

| Operation ID | Business Operation | Priority | Required Profiles | Entry / Navigation | Primary Action | Completion Feedback | Error / Recovery | Adaptive Pattern | Capability Link | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| OP-001 | describe the user outcome | CRITICAL / HIGH / MEDIUM / LOW | profile IDs or ALL_REQUIRED | how the user reaches it | semantic action | visible persisted outcome | recoverable failure behavior | desktop dialog / phone page / tablet sheet, etc. | interaction/capability contract ID | READY / BLOCKED |

Every REQUIRED profile must participate in at least one real business operation. Device adaptation may change navigation and presentation, but it must not silently remove an operation promised for that profile.
