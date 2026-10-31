# Device UX Verification Report

UI ID:
Production Revision:
Date:

Adaptive Verification Status: PENDING / VERIFIED / BLOCKED
Required Device Profiles: 0
Verified Required Profiles: 0
Failed Required Profiles: 0
Critical Operation Failures: 0
Component Consistency Violations: 0
Unintended Overflow / Clipping: 0
Input Modality Checks: NOT_RUN / PASS / BLOCKED
Orientation / Safe Area Checks: NOT_RUN / PASS / BLOCKED
Business Operation Checks: NOT_RUN / PASS / BLOCKED

## Required Profile Verification

| Profile ID | Production Evidence | Component Check | Operation Evidence | Overflow / Clipping | Input / Focus | Orientation / Safe Area | Status |
|---|---|---|---:|---:|---|---|---|
|  | production screenshot/evidence path | PASS / FAIL | operation evidence path | 0 | PASS / FAIL | PASS / NOT_APPLICABLE / FAIL | VERIFIED / BLOCKED |

Production evidence must come from the real target stack at the declared profile, not another prototype. Check the declared input modality, focus behavior, fixed/sticky element overlap, orientation and safe area where applicable.

## Operation Verification

| Operation ID | Profile ID | E2E / Manual Evidence | Result |
|---|---|---|---|
|  |  | repository-relative evidence path | PASS / FAIL |

Every operation/profile pair declared in `ADAPTIVE_UI_CONTRACT.md` requires a row. Evidence must show the real operation reaches its intended business result and exposes failure/recovery behavior.

## Component Consistency Findings

| Component Family | Profile | Expected Variant/Tokens | Actual | Severity | Resolution |
|---|---|---|---|---|---|

## Responsive and Content Stress Notes

- narrow width / zoom / text scaling:
- long content / localization:
- virtual keyboard / pointer / keyboard navigation:
- portrait / landscape / resize:
- table, navigation and primary-action adaptation:

## Decision

All REQUIRED profiles and declared operation/profile pairs must be VERIFIED with evidence. Any critical operation failure, component consistency violation, unintended clipping/overflow, missing input-mode verification or missing production evidence blocks UI acceptance.
