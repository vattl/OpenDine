# Scenario Matrix — WI-060

| ID | Family | Input / Context | Expected outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | normal | AGREE with configured key | hash + non-plaintext envelope persisted | INV-APPROVAL-001 | service unit test | PASS |
| S02 | multi-instance | confirm/poll use separate cipher instances with same key | token recovered consistently | INV-APPROVAL-001 | service unit test | PASS |
| S03 | security | envelope copied to another approval code | authentication fails, no token | INV-APPROVAL-001 | cipher unit test | PASS |
| S04 | security | ciphertext tampered or wrong key | authentication fails, no token | INV-APPROVAL-001 | cipher unit test | PASS |
| S05 | configuration | key missing/short | confirmation fails before database update | INV-APPROVAL-001 | cipher/service unit test | PASS |
| S06 | integrity | decrypted token hash differs from row | no token returned | INV-APPROVAL-001 | service unit test | PASS |
| S07 | migration | historical raw `token_value` | row expired and value cleared | INV-APPROVAL-001 | migration inspection + packaged SQL | PASS |
| S08 | replay | valid token consumed twice | CAS permits exactly one success | INV-APPROVAL-001 | regression test | PASS |
| S09 | compatibility | existing client polls approved request | same `approvalToken` response field | INV-APPROVAL-001 | service/OpenAPI verification | PASS |
| S10 | integration | Flyway migrations | every version unique | deterministic version check | PASS |
| S11 | expiry | expired APPROVED envelope | status EXPIRED, envelope cleared, no token | INV-APPROVAL-001 | service unit test | PASS |
