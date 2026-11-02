# Scenario Matrix — WI-010

| Scenario | Expected Result | Status | Evidence |
|---|---|---|---|
| KDS branch integration | ledger/revision/event continuity merged without violating cloud authority | PASS | current implementation supersedes C010; focused KDS tests pass |
| Report branch integration | cross-day shop business windows and exports remain correct | PASS | current implementation supersedes C012; report tests pass |
| Takeout branch history | branch is ancestor while `.local` artifacts remain absent | PASS | ancestor check true; forbidden tree count 0 |
| Regression preservation | WI-007/008/009 behaviors remain correct | PASS | focused suite included sorting, bill range and add-dishes tests |
| Full package | full tests and runnable JAR succeed | PASS | 1245 tests; clean package success |
