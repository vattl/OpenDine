# C007 audit remediation

Status: LOCAL_IMPLEMENTATION_COMPLETE / EXTERNAL_VERIFICATION_PENDING
Diff: docs/diffs/D007-audit-remediation.md
Exclusions: S01, S04, S10.

- [x] 1 S02/P01 proxy retirement and bounded JSON — 291fe10; 4 targeted tests pass; package pass
- [x] 2 S05 unique shop-bound payment matching — 8c26148; 28 tests and package PASS
- [x] 3 S03/S06/S07/S08/E02 local changes — 40e1392 (external rotation/SCA results remain pending)
- [x] 4 S09/P02/P03 images and HTTP resilience — 7d7e850; 7 tests and package PASS
- [x] 5 E01/A01 schema lifecycle and multi-instance state — 6719e0f; 32 targeted tests/package, 3 MySQL/readiness tests PASS
- [x] 6 C01/C02 controller boundaries and money — 20b7fbf; 90 tests/package PASS; broader controller/entity debt remains incremental
- [x] 7 T01/D01 verification and contracts — eca32c4; final 749 tests, 0 failures/errors, 1 skip; clean quality verify/JAR gate PASS

External work: provider credential rotation, deployment, coordinated history/old-artifact cleanup, production MySQL/load/failover/restore evidence remain unverified.

Baseline: 719 tests, 0 failures/errors, 1 local DB test skipped. Re-verify after changes.

Slice 3 local verification: 730 tests, 0 failures/errors, 1 skipped; quality verify and production JAR gate PASS. SBOM and JaCoCo generated. Provider rotation/history cleanup not performed.

Residual findings are not all closed: see docs/C007-VERIFICATION.md. SCA initialization stopped without a report; coverage 35.21% overall, 83.78% for the filter gate. No production readiness claim.
