# Implementation-Aware UI Rules

## Core Principle

Prototype design must be implementation-aware. Production implementation must be prototype-faithful.

Technical constraints may require adaptation, but never silent visual deviation.

## Stack Audit Before HTML Prototype

Inspect relevant project reality before designing:
- language/framework
- UI library
- styling system
- design tokens/theme
- existing components
- fonts
- icons
- responsive system
- route/layout constraints
- target platform restrictions

Do not design the HTML review artifact before this audit.

## Component Capability Audit

For each major planned UI element, determine whether production can:
- REUSE
- RESTYLE
- EXTEND
- CREATE
- REPLACE

Record material fidelity risks before approval.

## Prototype Mode

The mandatory user-review artifact uses `PROTOTYPE_MODE=HTML` with a renderable `.html/.htm` entry. It must approximate production geometry, fonts, tokens, states and behavior as closely as practical. Native/component experiments may be attached as feasibility evidence, but only the reviewed HTML artifact is the approval reference.

## Prototype Technical Plan

Before the HTML prototype, record:
- target stack
- prototype mode (`HTML`)
- production component mapping
- new components required
- token strategy
- font/icon strategy
- responsive strategy
- known incompatibilities
- planned mitigations

## Production Translation Rule

Production implementation is translation, not redesign.

After approval, the implementation phase must not quietly reinterpret the page. Any material deviation caused by framework/component constraints must be recorded as a Technical Deviation and either resolved or explicitly accepted.

## Component-Library Conflict

If a production component cannot express an approved prototype without material fidelity loss, choose intentionally among:
- extend component
- add a variant
- local implementation
- replace component
- request approval for deviation

Do not silently accept a lower-fidelity default merely because it already exists.
