# Scenario Matrix — WI-080
| ID | Context | Expected outcome | Verification | Result |
|---|---|---|---|---|
| S1 | New reader | Merchant value, limitations and deployment link clear | source/document review | PASS |
| S2 | Required secret missing | Actionable configuration failure | deployment test and negative Compose config | PASS |
| S3 | Empty database | Current schema, permission seed and BCrypt admin | isolated pristine MySQL integration | PASS |
| S4 | Nonempty database | Refused without changing existing data | second bootstrap plus before/after counts | PASS |
| S5 | Backend startup | Required schema validators pass and login works | real packaged-backend HTTP smoke | PASS |
| S6 | Client setup | Correct production address and build path | source/document cross-check | PASS |
| S7 | Persistent secrets | Backup/rotation/injection explained, key files private | configuration/security review | PASS |

