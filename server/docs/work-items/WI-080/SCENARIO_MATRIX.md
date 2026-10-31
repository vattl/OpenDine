# Scenario Matrix — WI-080
| ID | Context | Expected outcome | Verification | Result |
|---|---|---|---|---|
| S1 | New reader | Merchant value, limitations and deployment link clear | doc review | NOT_RUN |
| S2 | Required secret missing | Actionable configuration failure | automated config checks | NOT_RUN |
| S3 | Empty database | Current schema, permission seed and BCrypt admin | isolated MySQL integration | NOT_RUN |
| S4 | Nonempty database | Refused without changing existing data | isolated MySQL integration | NOT_RUN |
| S5 | Backend startup | Required schema validators pass and login works | real backend smoke | NOT_RUN |
| S6 | Client setup | Correct production address and build path | source/document cross-check | NOT_RUN |
| S7 | Persistent secrets | Backup/rotation/injection explained, key files private | config/security review | NOT_RUN |

