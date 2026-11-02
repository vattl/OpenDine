# Project Profile — PB-2

## Product

- Project type: restaurant ordering, cashier/POS, operations, reporting and KDS cloud backend.
- Primary users: diners using the WeChat mini program, cashiers, shop operators, administrators and KDS devices.
- Primary platforms: HTTP/JSON clients, WebSocket KDS clients and a runnable Spring Boot JAR.

## Technology

- Languages: Java 8, SQL, YAML and Markdown.
- Frontend framework: not owned by this repository; consumers include the mini program and Flutter/admin clients in sibling repositories.
- Backend framework: Spring Boot 2.3.2.RELEASE with embedded Tomcat 9.0.43.
- Runtime: Java 8.
- Package/build system: Maven Wrapper; artifact `diancan-0.0.1-SNAPSHOT.jar`.
- Database: MySQL in production, MyBatis-Plus 3.3.2, H2 for selected tests, Redis integration.
- API style: REST/JSON plus WebSocket; OpenAPI contract in `docs/openapi.yaml`.
- Test stack: Spring Boot Test/JUnit with focused unit and integration tests under `src/test/java`.
- Deployment/runtime environment: server process listening on port 8080 by default; production resources exclude debug configuration and key material.

## Repository Structure

- `src/main/java/com/lanf`: application code grouped by controller, service, payment, KDS, reporting, printing, security and supporting domains.
- `src/main/resources/db/migration`: ordered SQL migrations; applied migrations are immutable and corrected with higher versions.
- `src/test/java/com/lanf`: automated tests organized by production capability.
- `docs/openapi.yaml` and `docs/API.md`: machine-readable and human-readable API contract sources.
- `docs/project`: durable project baseline.
- `docs/work-items`: Work Item lifecycle evidence.

## Critical Modules

- `com.lanf.payment`: merchant configuration, WeChat APIv3 integration, callback processing, refunds and payment settlement helpers.
- `com.lanf.service.CashierCheckoutService`: authoritative cashier checkout state transition and ledger recording.
- `com.lanf.payment.success.PaymentSuccessHandler`: shared post-payment fulfillment, table, coupon, printing and KDS side effects.
- `com.lanf.kds`: cloud-authoritative KDS command, event and device flows.
- `com.lanf.service.impl.ReconciliationServiceImpl`: internal-ledger/channel-statement reconciliation.
- `com.lanf.config.ApiPermissionMapping` and interceptors: endpoint authentication and authorization mapping.

## Shared Services / Components

- `WechatMerchantKeyStore` resolves enabled shop merchant credentials from encrypted database configuration and loads referenced key files.
- `WechatPayV3Crypto` owns request signing, callback verification/decryption helpers and client pay signatures.
- `PaymentSettlementService` calculates authoritative payable amounts.
- `PaymentLedgerService` and `PaymentSettlementLedgerHelper` persist immutable settlement/refund evidence.
- `PaymentSuccessHandler` applies the observable business consequences of a confirmed payment.

## Engineering Conventions

- Server-calculated monetary amounts use integer fen at external payment boundaries.
- Public API changes must update both `docs/openapi.yaml` and `docs/API.md`.
- Any API change requires `mvnw.cmd clean package -DskipTests` before completion.
- Meaningful changes use one Work Item with Impact Map, design, Scenario Matrix and executable gates.
- Secrets and PEM contents are never committed; production packaging excludes `*.pem`, `*.pfx`, `*.p12` and `*.zip` resources.

## Known Constraints

- Spring Boot 2.3/Java 8 constrains language and framework APIs.
- The current WeChat integration uses `wechatpay-apache-httpclient` 0.4.9 plus project-owned request signing helpers; dependency migration is a separate concern.
- Cloud is the only KDS business authority; cashier/KDS proxy behavior must preserve `docs/KDS_ARCHITECTURE.md`.
- Consumer UI repositories are outside this checkout, so new consumer-visible contracts require explicit handoff when not changed in the same Work Item.

## Evidence / Last Verified

- Verified 2026-10-15 from `pom.xml`, `src/main/java/com/lanf/Application.java`, representative payment/KDS/controller/service modules, `src/main/resources/application.yml`, database migrations, API documentation and test layout.
