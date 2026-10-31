# API Rules

Before changing an API determine callers, public/private scope, old clients, and compatibility requirements.

Breaking examples:

- endpoint removal
- field rename/type change
- status semantic change
- auth behavior change
- incompatible error contract change

Validate external input server-side.

Authentication != authorization.

Prefer additive response changes.

Consider idempotency for payment/order/webhook/retryable operations.

Paginate growable datasets.

API behavior changes require API.md and docs/openapi.yaml synchronization.
API additions or modifications require compiling and building a production JAR (`mvn clean package -DskipTests`).
