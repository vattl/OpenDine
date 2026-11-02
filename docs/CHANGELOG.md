# Changelog

## Unreleased

### Added
- Prototype interaction capability contract, backend coordination report and two-stage executable UI capability gate.
- Scope-honest package/work/release Gate Orchestrator.
- Product inception, research, PRD approval, multi-agent orchestration, security audit, test report and release evidence contracts.
- Explicit deploy and submit commands with evidence-backed completion states.

### Changed
- Release validation now requires Work Item, Git integration, artifact, deployment, smoke and production-verification evidence.
- Unified workflow authority is v4.3 and distinguishes product, engineering, deployment and monitoring states.
- Removed remaining UI prototype/fidelity waiver language.

Record significant product/system changes. Do not record every minor internal edit.

## Unreleased

### Added
- v4.3 workflow-validation regression tests for semantic and manifest drift.
- HTML-only UI gate regression tests covering explicit approval, user presentation, non-HTML rejection, and compatibility routing.
- Two-phase prototype-to-production fidelity validator covering translation planning and final UI acceptance.
### Changed
- `/policy-check` now identifies and validates the current v4.3 workflow semantics.
- Release validation now verifies manifest count, paths, sizes, and SHA-256 hashes while normal validation tolerates expected runtime/baseline state changes.
- Every UI-impacting request now requires an HTML/HTM prototype, screenshot, user presentation, explicit approval, and UI lock before production UI editing.
- UI production editing now requires zero unmapped prototype/legacy regions; UI acceptance additionally requires same-viewport diff evidence, no legacy residue, target-state match and final user confirmation.
### Fixed
- Aligned the agent entry, skill entry, usage guide, and README lifecycle with the authoritative `IMPLEMENTATION_READY` flow and explicit completion levels.
- Removed native/component prototype and `WAIVED_BY_USER` paths from the executable UI approval gate.
### Removed
- 
### Security
- 
### Breaking
- 

## v0.1.0

Release Date:

### Added
- Initial project foundation.

## v3.4 — Capability-Aware Repair & Evidence-Verified Recovery

### Added
- `/repair`, `/verify`, `/capability`
- capability/consumer coverage rules and templates
- requirement traceability and completion evidence
- anti-fake production integrity rules
- crash-safe runtime registry/journal guidance
- heuristic evidence scanner
