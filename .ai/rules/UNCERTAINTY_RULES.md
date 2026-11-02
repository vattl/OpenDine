# Uncertainty Rules

## Confidence levels

HIGH: direct repository/test evidence supports the conclusion.
MEDIUM: evidence is incomplete but converges strongly.
LOW: important assumptions remain unverified.

## Required behavior

- HIGH: proceed normally.
- MEDIUM: proceed conservatively and identify the assumption.
- LOW: inspect more evidence before broad or destructive changes.

Never invent:
- existing APIs,
- schemas,
- callers,
- environment variables,
- production behavior,
- test results.

When deletion, migration, or compatibility depends on an uncertain assumption, verify before proceeding.
