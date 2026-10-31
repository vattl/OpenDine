# Completion Evidence — WI-008

Status: ACCEPTED

## Evidence

- RED：默认窗口断言在旧 24 小时实现上失败，证明测试可捕获目标行为差异。
- GREEN：`CashierOrderControllerTest` 30 tests，0 failures，0 errors。
- 全量回归：1245 tests，0 failures，0 errors，5 skipped。
- OpenAPI：`docs/openapi.yaml` YAML 解析 PASS，`docs/API.md` 同步完成。
- 权限迁移：`docs/db_migration_cashier_bill_custom_range.sql` 幂等注册 `admin:super`、清理非 `super_admin` 授权并仅向 `super_admin` 授权。
- 安全：条件权限失败关闭、门店上下文强制绑定、时间范围最大 31 天；见 `SECURITY_AUDIT.md`。
- 打包：`.\mvnw.cmd clean package -DskipTests` BUILD SUCCESS。
- 产物：`target/diancan-0.0.1-SNAPSHOT.jar`，73922073 bytes，SHA-256 `6BF926176F00E770345A1C301FD31D3E29FD7ACD5081CD72B3666BEADD9A8CD3`。
- 发布状态：未部署、未发布；部署时必须先执行权限迁移，再发布 JAR。
