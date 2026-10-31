# UI Design Methodology

## Purpose

Make UI design reasoning explicit before visual production. The agent must not jump from a user request directly into component arrangement or CSS for meaningful UI work.

## Core Principle

Design from user goals, information hierarchy, product context, and implementation reality before decoration.

## Required reasoning sequence for STANDARD+ UI work

1. Product Context
2. User Goal
3. Experience Profiles (terminal, orientation, input and usage context)
4. Information Hierarchy
5. Information Architecture
6. Interaction Priority and Business Operation Continuity
7. Density per Experience Profile
8. Visual Hierarchy
9. Spacing System
10. Typography Hierarchy
11. Component Family / Variant Strategy
12. State Coverage
13. Adaptive Layout Strategy
14. Implementation Feasibility
15. Design Critique

Do not treat this as ceremony. For small UI edits, use the lightest applicable subset.

## 1. Product Context

Identify the product type and optimize for its real job.

Examples:
- operational/admin: scanability, efficiency, stable patterns, information density
- KDS/POS: speed, high contrast, large targets, status clarity, low ambiguity
- consumer product: guidance, brand, emotion, conversion
- analytics: comparison, hierarchy, trend readability, filtering efficiency
- mobile tool: reachability, focus, progressive disclosure

Do not apply the same visual template to every product category.

## 2. User Goal First

Before layout, state:
- primary user goal
- primary information
- primary action
- secondary information/actions

The primary task must remain visually and interactionally obvious.

## 2A. Experience Profiles

Do not start responsive design from generic mobile/tablet/desktop widths alone. Identify product-relevant terminal/platform, orientation, input modality, usage context and business operations. Record them in `ADAPTIVE_UI_CONTRACT.md` and follow `.ai/rules/ADAPTIVE_UI_UX_RULES.md`.

Each REQUIRED profile is a design and acceptance obligation. Unsupported profiles should be declared honestly rather than receiving accidental broken layouts.

## 3. Information Hierarchy

Classify information approximately as:
- L1 page/core purpose
- L2 primary task content
- L3 primary controls
- L4 supporting information
- L5 metadata/help

Visual weight must reflect this hierarchy.

## 4. Information Architecture

Create the page structure before detailed styling.

Prefer semantic groups. Avoid adding containers merely for decoration.

## 5. Gestalt Grouping

Use practical gestalt rules:
- proximity: nearby items imply one group
- similarity: similar appearance implies similar role
- alignment: shared edges establish order
- common region: containers must communicate a real relationship
- continuity: reading flow should be natural

Avoid nested Card-on-Card layouts without semantic reason.

## 6. Visual Weight

A page should normally have one dominant focal area and a small number of secondary focal areas.

Do not make every card, title, action, filter, and table equally prominent.

## 7. Spacing System

Use a coherent spacing scale, adapted to the project design system. If the project has no scale, a baseline such as 4 / 8 / 12 / 16 / 24 / 32 / 48 may be used.

Relationship principle:
internal spacing < same-group spacing < section spacing < major-region spacing

## 8. Typography Hierarchy

Define roles, not arbitrary font sizes:
- display/page title
- section title
- body
- secondary
- caption/meta
- numeric emphasis

Use weight, line-height, color, and spacing in addition to size.

Prototype must use the production font stack whenever feasible.

## 9. Density

Explicitly select a density mode when meaningful:
- COMPACT
- COMFORTABLE
- SPACIOUS

Row heights, control heights, card padding, section gaps, and content density should be coherent with that choice.

Density may vary by experience profile. Pointer/keyboard operational UI may be compact while touch use requires larger hit targets and spacing. Do not mix density modes accidentally inside one profile or component hierarchy.

## 10. Progressive Disclosure

Keep frequent actions visible and defer advanced/rare controls when doing so improves clarity.

Do not expose every setting simultaneously by default.

## 11. Action Hierarchy

Classify actions:
- PRIMARY
- SECONDARY
- TERTIARY
- DANGER

Avoid multiple competing primary actions.

Map each material action to a complete business operation for every profile on which it is promised. Moving an action into a drawer/sheet is acceptable; losing it at a breakpoint is not.

## 12. State Coverage

For meaningful interactive UI, account for relevant states:
- default
- hover/focus/active/selected
- disabled
- loading
- empty
- error
- success
- permission denied

A UI design that only works with ideal data is incomplete.

## 13. Content Before Components

Choose a presentation because it communicates the information well, not because a component exists.

Examples:
- comparable records -> table/list
- key values -> stat group
- workflow progress -> step/timeline/status
- advanced controls -> disclosure/drawer/filter panel

## 14. Consistency Before Novelty

Internal consistency is more important than novelty.

Equivalent roles should share equivalent treatment.

## 15. Design Critique Gate

Before presenting a structural prototype, review:
- Is the primary task obvious?
- Is hierarchy clear?
- Are there too many containers?
- Are actions competing?
- Is spacing systematic?
- Is density coherent?
- Is typography hierarchical?
- Is the content scannable?
- Is decoration doing useful work?
- Does the design fit the product type?
- Are component families and semantic variants internally consistent?
- Can each promised business operation be completed on every REQUIRED experience profile?
- Are touch, pointer, keyboard, orientation and safe-area needs addressed where applicable?
- Is it feasible in the target stack?

Material failures require revision before approval.
