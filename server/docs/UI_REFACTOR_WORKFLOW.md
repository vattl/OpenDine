# UI Refactor Workflow

## Intent

UI work is classified as REFINE, REFACTOR, or REDESIGN.

For REFACTOR:
- preserve business capability and technical contracts
- do not preserve legacy appearance by default
- decompose old UI into capability vs visual implementation
- explicitly PRESERVE/MODIFY/MOVE/REPLACE/REMOVE legacy regions
- reconsider information architecture and component composition
- reject reskins that do not satisfy the requested refactor

## Project-Aware Prototype

Audit the real framework, component library, fonts, icons, tokens, platform restrictions, and existing components before building the HTML review prototype.

Prototype mode: `HTML`. Use an isolated `.html/.htm` entry with realistic content and states. Record exact mappings and incompatibilities for the target production stack.

## Production Translation

After explicit user approval, lock content/elements/style/component mapping/responsive intent. Production coding translates that locked HTML intent into the target framework. Technical deviations must be visible and justified.
