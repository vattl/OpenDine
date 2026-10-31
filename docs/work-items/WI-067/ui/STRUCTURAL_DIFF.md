# Structural Diff

Diff ID: UI-DAILY-SEQUENCE-001-DIFF

Parent Work: WI-067

Title: Daily close sequence authority refinement

Status: PROPOSED

Created: 2026-10-25

Last Updated: 2026-10-25

Plan Status: APPROVED

Unclassified Legacy Regions: 0

## 1. Change Intent

Replace client-clock date authority with server sequence authority while preserving the existing page composition.

## 2. Current State

### Structure

```text
AppBar → local date card → precheck → summary → generic settle button
```

### Behavior

Client computes and sends the date before contacting the server.

### Components

Existing Flutter containers, cards and button.

### Data Flow

local clock → all API calls.

### Styles

Mobile v2 tokens.

### Conditions

Blockers/warnings/already-settled.

### Dependencies

Current daily APIs.

## 3. Target State

### Structure

```text
AppBar → server authority/backlog card + sequence row → precheck → summary → date-specific settle button
```

### Behavior

Precheck returns target day first; all other calls and actions bind to it.

### Components

Existing components plus a local sequence row.

### Data Flow

server close context → page state → summary/actions.

### Styles

Same tokens, orange soft backlog emphasis.

### Conditions

Adds historical backlog; existing blocker/warning states preserved.

### Dependencies

WI-067 API extension.

## 4. Structural Diff

| ID | Element | Current | Target | Operation | Risk |
|---|---|---|---|---|---|
| D1 | Date authority | client local clock | server next close day | REPLACE | HIGH |
| D2 | Date card | date/window only | authority + backlog + progress | MODIFY | LOW |
| D3 | Close button | generic label | target-date label | MODIFY | LOW |
| D4 | Precheck/summary cards | existing | same bound to server date | UNCHANGED | MEDIUM |

## 5. Preserve / Unchanged

- App bar, precheck card, summary card, confirmation and permission behavior.

## 6. Add

- Backlog notice and sequence progress.

## 7. Modify

- Date source, card copy and action label.

## 8. Move

- None.

## 9. Replace

- Client-derived date authority.

## 10. Remove

- Hardcoded local date/window claim.

## 11. Deprecate

- None.

## 12. Migrate

- Page state initialization to server precheck response.

## 13. Negative Acceptance Criteria

- [ ] Old client-clock authority no longer active.
- [ ] Duplicate old/new date authority does not exist.

## 14. Compatibility Requirements

- Existing blocker, warning, authorization and report interactions remain.

## 15. Implementation Order

1. Backend context/guard.
2. Domain/repository mapping.
3. Page state and UI translation.

## 16. Verification

| Diff ID | Status | Evidence |
|---|---|---|
| D1 | NOT_VERIFIED | pending implementation |
| D2 | NOT_VERIFIED | pending implementation |
| D3 | NOT_VERIFIED | pending implementation |
| D4 | NOT_VERIFIED | pending regression |

## 17. Unexpected Diff

None.

## 18. Final State Verification

Target State Match: NO

Legacy Remaining: YES

Unexpected Active Behavior: NO

## 19. Final Status

Final Status: PROPOSED
