# UI Design Track Rules

UI work belongs to the DESIGN phase of a Work Item.

Use the existing v3.6 methodology, refactor, implementation-aware and fidelity rules.

## Flow
Project context → product/user goal → IA/hierarchy → design methodology → component capability audit → HTML prototype → visual capture → critique → user presentation → explicit prototype approval → lock → production translation → visual/interaction verification.

## Refactor semantics
When the request is REFACTOR/REDESIGN, preserve required product capability, data and interactions, but do not preserve legacy appearance by default.

## Implementation awareness
Prototype technology/structure should be chosen after inspecting the real target stack and component constraints.

## Fidelity
Content, required elements and structure must not silently drift. Technical adaptation is allowed only with explicit reason/evidence.

## HTML prototype hard enforcement

For any UI impact or REFINE/REFACTOR/REDESIGN intent, this track is mandatory, `PROTOTYPE_REQUIREMENT=REQUIRED`, `PROTOTYPE_MODE=HTML`, and production UI edits are blocked until a real `.html/.htm` prototype, visual reference, critique, user presentation, explicit `Approval Status: APPROVED`, applicable coverage evidence, and UI lock exist. An engineering plan, design-strategy document, or native-framework preview does not satisfy the UI design gate.

The track must read `DESIGN_SYSTEM_PROFILE` first and perform Data Feasibility for material visible data/actions. Unsupported data requirements create a Backend Capability Request rather than being faked or deferred silently.
