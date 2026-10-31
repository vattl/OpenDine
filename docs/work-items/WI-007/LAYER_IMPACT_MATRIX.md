# Layer Impact Matrix — WI-007

| Layer | Status | Owner | Change | Verification |
|---|---|---|---|---|
| Client UI | NOT_APPLICABLE | external consumers | 无字段或交互改动 | 合同审查 |
| API boundary | AFFECTED | admin controllers | 门店上下文及层级语义收紧 | 控制器测试 |
| Domain/service | AFFECTED | ShopMenuSortService | 事务锁与稳定重排 | 服务测试 |
| Persistence | AFFECTED | category/dish shop mappers | 分类门店覆盖与读取 join | SQL契约/构建 |
| Read consumers | AFFECTED | admin/C menu controllers | 应用分类门店覆盖 | 回归测试 |
| Events | AFFECTED | DishMenuPushService | 成功后刷新菜单 | mock验证 |
| Security | VERIFIED_UNAFFECTED | SysInterceptor | 复用已授权门店上下文 | 代码审查 |
| Documentation | AFFECTED | OpenAPI/API/DB docs | 同步语义和迁移 | 文档 diff |

Material UNKNOWN count: 0

