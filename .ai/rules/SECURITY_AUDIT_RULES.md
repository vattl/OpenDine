# Security Audit Rules

Security is a distinct acceptance and release gate, not a review-report heading.

## Required analysis

- assets, trust boundaries, actors and abuse cases;
- authentication, authorization and tenant/data isolation;
- input, output, file, command and network boundaries;
- secret handling and sensitive logging;
- dependency/supply-chain exposure;
- privacy, retention and destructive actions;
- applicable SAST, dependency, secret and dynamic scans.

## Decision

Record results in `SECURITY_AUDIT.md`.

`Security Decision: APPROVED` requires:

- `Threat Model Status: COMPLETE`;
- open CRITICAL = 0;
- open HIGH = 0 unless an authorized risk owner explicitly accepts each finding with expiry and mitigation;
- required scans are PASS, or NOT_APPLICABLE with rationale;
- fixes have re-verification evidence.

The implementing agent must not silently accept its own material security risk. Security approval does not imply product acceptance or release.
