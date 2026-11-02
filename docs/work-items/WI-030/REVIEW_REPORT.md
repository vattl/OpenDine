# Review Report — WI-030

Independent Review: PASS

## Review axes

- Correctness: route, callback and refund identities converge on the transaction-bound merchant configuration.
- Security: cross-shop, missing identity and unknown-refund paths fail closed before ledger/order mutation.
- Concurrency/idempotency: existing DB locks and unique refund keys remain authoritative; callback does not create missing requests.
- Compatibility: endpoint paths and success response shapes are unchanged; historical unbound orders retain a strict compatibility path based on the order's stored merchant marker.
- Performance: new-payment configuration reads are selective DB reads; callback credential discovery uses serial indexes instead of scanning all merchant history.
- Data migration: nullable columns are backfilled before use; order-number uniqueness intentionally blocks ambiguous production data.
- Documentation: OpenAPI, API narrative, schema baseline and architecture baseline are synchronized.

## Findings resolved during review

- Added `out_refund_no` equality to idempotent refund-request replay validation.
- Changed missing registered-order callback handling from a false/no-op result to an exception so the controller returns `FAIL` and WeChat retries.
- Legacy payment callback resolution now prefers the order's stored merchant marker over a callback candidate's arbitrary first legacy marker.
- Preserved the original refund-ledger `Entry` constructor for the existing compensation test seam.

## Remaining findings

No HIGH or CRITICAL finding remains in the WI-030 payment scope.

The review was performed locally because no pull request exists. The repository-wide KDS test failures are recorded in `TEST_REPORT.md` and prevent claiming whole-worktree integration.

## Verdict

APPROVE
