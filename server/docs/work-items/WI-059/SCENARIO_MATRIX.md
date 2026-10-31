# Scenario Matrix — WI-059

| ID | Family | Input / Context | Expected outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | normal | v2 all fields exact | one CAS consume succeeds | INV-APPROVAL-001 | unit test | PASS |
| S02 | invalid | v2 placeholder resource | issuance rejected | INV-APPROVAL-001 | unit test | PASS |
| S03 | invalid | action/resource/operator/shop/terminal mismatch | reject without update | INV-APPROVAL-001 | unit test | PASS |
| S04 | boundary | 88.0 vs 88.00; null vs null | numeric equality succeeds | INV-APPROVAL-001 | unit test | PASS |
| S05 | invalid | amount null mismatch or numeric mismatch | reject without update | INV-APPROVAL-001 | unit test | PASS |
| S06 | repeated | same token repeated/CAS conflict | exactly one success | INV-APPROVAL-001 | existing replay/CAS tests | PASS |
| S07 | compatibility | version omitted/historical row | v1 works with legacy marker/log | INV-APPROVAL-001 | response assertions + regression | PASS |
| S08 | permission | another operator/shop consumes | reject without update | INV-APPROVAL-001 | unit test | PASS |
