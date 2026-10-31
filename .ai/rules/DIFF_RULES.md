# Diff Rules

## Principle

All material changes should be expressed as Current State → Target State → Structural Diff.

## Operations

- UNCHANGED
- ADD
- MODIFY
- MOVE
- REPLACE
- REMOVE
- DEPRECATE
- MIGRATE

## Semantics

### MOVE

MOVE means remove from old location, preserve intended capability, and place in new location.

### REPLACE

REPLACE means the new implementation supersedes the old active implementation. Coexistence requires an explicit compatibility reason.

### REMOVE

Removal is part of implementation, not optional cleanup.

### DEPRECATE

Must document remaining consumers, removal condition, and planned removal version.

### MIGRATE

Must model Old State → Transitional State → Target State.

## Negative Acceptance Criteria

REPLACE / MOVE / REMOVE require explicit criteria for what must no longer exist or execute.

## Diff Drift

If implementation discovers the planned Diff is incomplete, update the Diff before silently expanding implementation.

## Completion

Actual State must match Target State. New behavior existing while obsolete behavior remains unexpectedly active is PARTIAL, not DONE.
