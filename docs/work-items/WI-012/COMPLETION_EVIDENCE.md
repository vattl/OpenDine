# Completion Evidence — WI-012

## Current Status

ACCEPTED。

## Evidence

- RED：`calculateUsesPersistedOrderAmountWhenComboDetailsDrift` 在旧实现下预期 116、实际 124，按预期失败。
- GREEN：桌台金额使用订单持久化字段，并复用 `OrderNetRevenue.netRevenueYuan` 作为统一净应付口径；明细只保留展示和赠送/退款审计用途。
- 专项回归：46 tests，0 failures，0 errors，0 skipped。
- 完整回归：1246 tests，0 failures，0 errors，5 skipped。
- API 文档：`docs/API.md` 与 `docs/openapi.yaml` 已同步 v1.2.287 契约。
- 完整打包：`.\mvnw.cmd clean package -DskipTests`，BUILD SUCCESS。
- JAR：`target/diancan-0.0.1-SNAPSHOT.jar`，73,921,906 bytes。
- SHA-256：`A512AD66EF5D514DBAE97DCC037BBBE3D38DC23810CB6BC81A9414FB7FA0994D`。
- Secret scan：PASS；无依赖变更。
