# v4.0 Role

`/verify` supports SELF_VERIFY/ACCEPT. Re-read the parent Work Item Requirement Contract and evaluate evidence, not prior-agent claims.


---

# /verify

Verify the original requirement, not merely tests.

## Required evidence

1. Requirement coverage matrix
2. Capability/consumer coverage
3. Layer Impact Matrix has UNKNOWN = 0
4. Contract Delta resolved where applicable
5. Request propagation verified
6. Response propagation verified
7. Semantic UI impact verified
8. End-to-end flow verified where applicable
9. Fake/mock/hardcode scan reviewed
10. Relevant tests pass
11. Git diff matches intended scope

Decision must be one of:

- VERIFIED_DONE
- PARTIAL
- FALSE_COMPLETION
- BLOCKED
