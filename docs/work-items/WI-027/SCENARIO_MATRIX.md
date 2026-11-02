# Scenario Matrix — WI-027

| ID | Scenario | Expected Business Outcome | Verification | Result |
|---|---|---|---|---|
| S01 | 查询可挂账账户 | 路由存在并委托门店范围服务，不再返回 Spring 404 | `CashierReceivableControllerRouteTest` + contract inspection | PASS |
| S02 | 无可用账户 | 返回 200 空集合而非 404 | controller empty-list regression test | PASS |
| S03 | 无权限或跨门店 | 被权限/租户边界拒绝 | permission completeness + receivable service tests | PASS |
| S04 | 应用执行迁移 | V001~V029 版本唯一且依赖顺序正确 | migration uniqueness check | PASS |
| S05 | 集成后打包 | 两侧既有能力均通过回归并生成 runnable JAR | 1411 tests + clean package | PASS |

## Acceptance rule

全部场景 PASS；Material NOT_VERIFIED count: 0。
