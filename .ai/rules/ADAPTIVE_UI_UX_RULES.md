# Adaptive Multi-Device UI/UX Rules

## Purpose

Make device adaptation, component consistency and business-operation continuity executable parts of UI design and acceptance. A layout that merely shrinks or rearranges at one breakpoint is not a professional responsive experience.

## 1. Design by experience profile, not width alone

Before the HTML prototype, identify each product-relevant experience profile using:

- terminal/platform: web, iOS, Android, desktop app, tablet, kiosk, TV or embedded surface;
- representative viewport/window and resize behavior;
- orientation: portrait, landscape or both;
- input modality: touch, pointer, keyboard, remote, scanner or mixed;
- usage context: desk, counter, field, commute, wall display, one-handed or accessibility technology;
- support level: REQUIRED, OPTIONAL or UNSUPPORTED;
- density, navigation and disclosure strategy;
- primary business operations promised on that profile.

Breakpoints are implementation tools. They do not replace product decisions about terminal capability or user context.

Do not force every product to support every device. A truthful desktop-only, mobile-only or kiosk-only product may declare one REQUIRED profile. Every declared REQUIRED profile is an acceptance obligation.

## 2. One HTML prototype, multiple required renderings

The isolated HTML prototype remains the mandatory review artifact. Render it for every REQUIRED profile using representative content, orientation and input assumptions.

Before approval, the user must be able to inspect the materially different layouts and interaction patterns. A single desktop screenshot cannot approve an unshown mobile/tablet target.

Materially different profiles require prototype evidence for their:

- navigation and page shell;
- primary content hierarchy;
- primary and destructive actions;
- forms, tables/lists and dialogs/sheets/pages;
- loading, empty, error, permission and disabled states;
- fixed/sticky elements and safe-area behavior.

## 3. Component families and semantic variants

Equivalent components must belong to an explicit family and semantic variant. For each profile define as applicable:

- visual size token;
- interaction hit target;
- horizontal/vertical padding;
- icon size and stroke/style token;
- typography token;
- internal gap and adjacent-control spacing;
- radius/border/elevation treatment;
- wrapping, collapse or replacement behavior;
- default, hover/focus, pressed, selected, disabled, loading, error and success states.

Do not mix arbitrary button/input/icon sizes in the same hierarchy. Primary, secondary, tertiary, destructive and icon-only controls may differ intentionally, but the reason must be semantic and represented by variants.

Visual bounds and hit targets are separate. A compact desktop icon may keep a larger keyboard/pointer affordance; a visually small mobile icon must still have an adequate touch area.

Platform guidance is contextual rather than universal:

- iOS touch targets normally use at least 44pt;
- Android touch targets normally use at least 48dp;
- web target sizing follows the applicable web accessibility requirement and interaction context;
- pointer-dense operational UI may use a compact visual control only when focus, hit area, spacing and error risk remain acceptable.

Never apply one unit or one button height blindly across platforms.

## 4. Business-operation continuity

Responsive design is incomplete until the user can finish the intended business task.

For every material operation record:

- priority;
- profiles on which it is promised;
- entry/navigation path;
- primary action and required data;
- completion feedback and persisted/shared outcome;
- validation, error and recovery behavior;
- permission and disabled behavior;
- device-specific interaction pattern;
- real capability/interaction contract link.

Adaptation may move a toolbar into a sheet, turn a dialog into a full-screen page, collapse a table into a list, or expose a sticky action bar. It may not silently remove, hide or fake an operation promised for that profile.

If an operation is intentionally unavailable on a device, mark that profile UNSUPPORTED for the operation or revise product scope and prototype explicitly. Do not let CSS accidentally decide product capability.

## 5. Layout and content adaptation

Use layout transformation rather than uniform scaling. Choose per profile as relevant:

- column count and region order;
- max content width and adaptive gutters;
- navigation shell;
- table overflow, prioritised columns, card/list substitution or detail drill-down;
- inline panel, drawer, sheet, dialog or full-page task flow;
- sticky/fixed action placement without covering scroll content;
- safe areas, system bars and virtual keyboard behavior;
- portrait/landscape and resizable window behavior;
- readable line length and typography scaling;
- localization, long content, zoom and dynamic-text stress;
- reduced motion and accessibility alternatives.

Avoid fixed heights where content or text scaling can grow. Avoid device detection when capability/layout queries are sufficient, but do not pretend capability queries answer product-support questions.

## 6. Required artifacts

For every UI-impacting Work Item create in the UI evidence directory:

- `ADAPTIVE_UI_CONTRACT.md` before production UI editing;
- `DEVICE_UX_VERIFICATION_REPORT.md` before UI acceptance.

Run:

```bash
python .ai/scripts/validate_ui_adaptive.py --root . --ui-dir <artifact-dir> --phase plan
python .ai/scripts/validate_ui_adaptive.py --root . --ui-dir <artifact-dir> --phase accept
```

## 7. Plan gate

The plan gate requires:

- at least one REQUIRED experience profile;
- every REQUIRED profile has complete terminal/input/context/layout decisions and prototype evidence;
- every component family has resolved semantic variants, tokens, hit targets, adaptation and states;
- arbitrary component size values = 0;
- unresolved component variants = 0;
- every material business operation maps to valid profiles and a real capability link;
- every REQUIRED profile has business-operation coverage;
- unmapped critical operations = 0.

A failed plan gate forbids production UI editing.

## 8. Acceptance gate

For every REQUIRED profile verify the real production stack with representative evidence:

- layout and component-family consistency;
- no unintended clipping or overflow;
- declared pointer/keyboard/touch/remote behavior;
- focus order and accessible control naming where applicable;
- orientation, resize, safe area and virtual-keyboard behavior where applicable;
- every declared operation/profile pair reaches its real business outcome;
- completion, error and recovery feedback remains usable;
- responsive content stress does not make the operation unusable.

Acceptance requires:

- all REQUIRED profiles VERIFIED;
- all declared operation/profile pairs PASS with evidence;
- failed required profiles = 0;
- critical operation failures = 0;
- component consistency violations = 0;
- unintended overflow/clipping findings = 0;
- input modality, orientation/safe-area and business-operation checks PASS.

Reference-viewport visual fidelity, adaptive-device UX and backend capability are separate gates. Passing one never overrides another.
