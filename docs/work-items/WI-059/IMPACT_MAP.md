# Impact Map — WI-059

## Authoritative Owner
`ApprovalService` owns issuance, binding validation and CAS consumption; `t_access_approval.binding_version` records policy version.

## Change Propagation Path
```text
cashier approval request + X-Terminal-Id/bindingVersion
→ CashierAccessController
→ ApprovalService issuance
→ t_access_approval binding_version
→ sensitive operation builds AccessContext
→ ApprovalService strict comparison
→ CAS consume or non-consuming reject
```

## Consumer Coverage
| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| Flutter cashier | creates/consumes tokens | AFFECTED | YES for v2 adoption | sibling repo search |
| Admin/mobile approver | views/confirms QR | AFFECTED | response additive only | access approval models |
| Mini program | no cashier approval calls found | VERIFIED_UNAFFECTED | NO | targeted search |
| Backend sensitive controllers/services | build AccessContext | AFFECTED | YES | `validateAndConsume` call sites |

## Layer Coverage
| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | backend-only; v1 remains usable |
| Interaction | AFFECTED | v2 contract handoff only |
| Frontend State | AFFECTED | retain bindingVersion/terminal |
| API Client | AFFECTED | additive v2 request/response fields |
| Request Contract | AFFECTED | bindingVersion, terminalId |
| Backend/Domain | AFFECTED | strict comparison policy |
| Persistence | AFFECTED | binding_version migration |
| Response Contract | AFFECTED | bindingVersion/legacyBinding |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | none |
| Config/Security | AFFECTED | compatibility telemetry |
| Runtime/NFR | AFFECTED | no extra query; comparison only |
| Tests | AFFECTED | approval/caller contract tests |

## Duplicate Logic / Patch Smells
Sensitive controllers assemble AccessContext separately; this slice propagates fields but does not yet create the WI-062 unified decision facade.

## Contract Delta Summary
Additive `bindingVersion` and `terminalId`; v2 changes validation semantics, v1 remains explicit compatibility.

## UI Semantic Impact
No production UI edit in this repository. Consumer handoff is required for v2 adoption.

## Risks
- Enforcing v2 by default would break current Flutter placeholder flows; default remains v1 during observation.
- Missing terminal propagation would make valid v2 tokens unusable; all backend consumers are mapped.
