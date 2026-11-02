# Impact Map — WI-027

## Authoritative Owner

- Git integration: commits `49e5e847` and `ea447567` onto `integration/unified-baseline-20261012`.
- Receivables API: `CashierReceivableController` / `ReceivableService`.
- Permissions: `ApiPermissionMapping` plus permission migrations/initialization SQL.
- Migration order: Flyway filenames under `src/main/resources/db/migration`.

## Change Propagation Path

```text
cashier request
→ Spring controller registration
→ receivable:view authorization
→ X-Shop-Id scoped ReceivableService
→ t_receivable_account
→ 200 account list / authorization business error
```

## Consumer Coverage

| Consumer | Classification | Evidence |
|---|---|---|
| Cashier client | AFFECTED | Already calls the documented route; 404 is current incident evidence |
| Admin receivables | AFFECTED | Same integrated capability and schema |
| Mini program payment | AFFECTED | JSAPI integrity commit integrated and regression tested |
| Existing version/member/report APIs | MUST_PRESERVE | Current HEAD commits retained during conflict resolution |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | No production UI repository edits |
| API/controller | AFFECTED | Missing controllers and routes enter integration branch |
| Domain/service | AFFECTED | Receivable/payment services integrated |
| Persistence | AFFECTED | Three migrations renumbered to avoid collisions |
| Response contract | AFFECTED | Existing documented APIs become available in integrated build |
| Security | AFFECTED | Permission map and tenant isolation must survive merge |
| KDS | VERIFIED_UNAFFECTED | No KDS source touched by the two commits |
| Tests/docs/build | AFFECTED | Full regression, OpenAPI and package required |

Material UNKNOWN count: 0

## Contract Delta Summary

No new contract beyond WI-020~026; this work makes those accepted contracts present in the integration artifact.

## Risks

- Duplicate Flyway versions would prevent startup.
- Conflict resolution could discard current branch changes or accepted payment invariants.
- Local integration alone does not resolve production until the new JAR and migrations are deployed.
