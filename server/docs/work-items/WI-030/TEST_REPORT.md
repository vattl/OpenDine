# Test Report — WI-030

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Scoped payment verification

Command:

`./mvnw.cmd -Dtest=PaymentMerchantBindingMigrationTest,PaymentRefundLedgerTest,WechatRefundSettlementServiceTest,WechatRefundQuerySchedulerTest,OrderRefundNotifyTest,WechatJsapiChannelTest,WechatPaymentSuccessServiceTest,WechatNativeApiClientTest,WechatMicropayApiClientTest,WechatMerchantKeyStoreTest,PaymentMerchantConfigServiceTest,WechatMerchantRoutingServiceTest test`

Result: **PASS** — 68 tests, 0 failures, 0 errors, 0 skipped.

Coverage includes server-authoritative routing, stale-cache rejection, bound credential shop isolation, callback `mchid/appid`, refund request binding, unknown/mismatched refund rejection, callback idempotency, refund compensation, migration columns/indexes and existing Native/MICROPAY/JSAPI paths.

## Contract and source checks

- `docs/openapi.yaml`: PyYAML parse **PASS**.
- `git diff --check`: **PASS**; only existing line-ending conversion warnings were emitted.
- Migration resource assertions: included in the 68-test scoped suite and **PASS**.

## Full repository suite

Command: `./mvnw.cmd test`

Result: **NOT GREEN OUTSIDE THIS WORK ITEM** — 1460 tests, 1 failure, 2 errors, 5 skipped. All payment tests pass. The remaining failures are existing KDS workflow tests in an unaffected module:

- `KdsWorkflowAdvanceIdempotencyTest.testAdvanceDetailThrowsWhenNotPassedAndNotInQueue`
- `KdsWorkflowServePrintTimingTest.cookingCompletionDoesNotPrintBeforeServing`
- `KdsWorkflowServePrintTimingTest.servingCompletionPrintsTheActuallyServedQuantity`

No `com.lanf.kds` production or test file was changed by WI-030. These failures block declaring the whole dirty worktree integrated, but do not invalidate the scoped payment acceptance evidence.

## Risk-derived minimum matrix

| Surface / Risk | Required Check | Command / Method | Result | Evidence |
|---|---|---|---|---|
| Merchant routing | Client value cannot choose merchant | `WechatMerchantRoutingServiceTest` | PASS | Scoped suite |
| Multi-node config | Stale cache cannot remain authoritative | `PaymentMerchantConfigServiceTest` | PASS | Scoped suite |
| Shop isolation | Bound credential must belong to order shop/global template | Key store + success tests | PASS | Scoped suite |
| Payment callback | `mchid/appid`, amount and transaction binding | Payment success + notify tests | PASS | Scoped suite |
| Refund callback | Registered exact request only | Ledger + controller + settlement tests | PASS | Scoped suite |
| Migration | Binding columns/indexes/order uniqueness | Migration resource test + review | PASS | Scoped suite |
| API contract | YAML remains parseable and behavior documented | PyYAML | PASS | Console evidence |
| Packaging | Runnable JAR | Maven clean package | PASS | SHA-256 recorded below |

## Requirement and scenario coverage

S01–S10 are all PASS in `SCENARIO_MATRIX.md`; no material scenario is skipped or unverified.

## Flaky, skipped and pre-existing failures

The three KDS failures are classified as pre-existing/out-of-scope integration failures. They do not overlap any file in the WI-030 Impact Map. The five skipped tests in the full run are repository-defined skips; no WI-030 required test is skipped.

## Package build

Command: `./mvnw.cmd clean package -DskipTests`

Result: **PASS**.

- Artifact: `target/diancan-0.0.1-SNAPSHOT.jar`
- Size: 74,162,231 bytes
- SHA-256: `07D3C7405191CCCEC31219F038617B59EDF8BC807EA5CA520701715C95860A6F`
