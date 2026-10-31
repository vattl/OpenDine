# Boundary Rules

## Purpose

Force realistic edge-condition thinking without turning every task into exhaustive formal verification.

## Boundary Categories

When relevant, test or reason about:

- empty input / zero rows
- minimum and maximum valid values
- null / missing / malformed input
- duplicate input
- stale data
- very large data sets
- slow dependency
- timeout
- partial failure
- network disconnect/reconnect
- user cancellation
- process restart
- repeated execution
- permission boundary
- timezone/date boundary
- pagination boundary
- integer/decimal precision

## Risk-Adaptive Rule

TRIVIAL work may need no explicit boundary artifact.

STANDARD work should cover likely business boundaries.

STRUCTURAL/CRITICAL work should record high-impact boundary assumptions and tests.

## Negative Path Rule

Do not validate only the happy path when failure is plausible and materially harmful.

## Completion

Critical boundary behavior must have an intentional outcome, not accidental behavior.
