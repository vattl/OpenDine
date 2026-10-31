# Implementation Design — WI-062

## Root Fix / Owner
扩展现有 `AccessDecisionService` 作为统一授权决策器，不再增加第二个并行服务；用显式 `Outcome` 保证结果互斥。数据库映射成为请求时唯一权威，代码映射仅提供清单快照供测试和迁移校验。

## Permission Vocabulary
首批冻结：

| Action | Entry | Execute | Approve |
|---|---|---|---|
| refund | `cashier:operate` | `order:operate:refund` | `order:operate:refund:approve` |
| change price | `cashier:operate` | `order:operate:changePrice` | `order:operate:changePrice:approve` |
| discount | `cashier:operate` | `order:operate:discount` | `order:operate:discount:approve` |
| reopen/uncheckout | `cashier:operate` | `order:operate:reopen` | `order:operate:reopen:approve` |

目录仅建立语义和决策能力；实际 Controller 切换及角色迁移属于 WI-063。

## Decision Rules
1. 账号、门店范围或显式 DENY 失败：`DENY`。
2. 拥有动作执行权限：继续策略评估。
3. 缺少执行权限但拥有该动作入口权限：无令牌返回 `REQUIRE_APPROVAL`；有效且严格绑定的令牌返回 `ALLOW`；无效令牌返回 `DENY`。
4. 未登记动作或连入口权限也没有：`DENY`。
5. 三态与兼容布尔值由工厂方法一次构造，不允许调用方自行组合。

## Mapping Authority
- `DbApiPermissionMapping` 成功加载后提供唯一运行时映射。
- 加载异常保留上一份已成功快照；首次加载失败则为空并失败关闭。
- `SysInterceptor` 不再调用 `ApiPermissionMapping` 放行请求。
- 自动测试比较代码清单和 `docs/init_api_permission.sql`，防止提交时漂移；数据库动态管理仍以运行时表为准。

## Interfaces / Compatibility
`POST /admin/access/evaluate` 响应新增 `outcome`。保留 `allow`、`approvalRequired`、`permissionGranted` 等字段。无 context 调用不再走旧实现，但普通 ALLOW/DENY 的线级字段保持兼容。

## Security
- 审批令牌仍由 `ApprovalService.validateAndConsume` 严格绑定并一次性核销。
- 显式 DENY 优先于入口、动作权限和审批令牌。
- 映射加载失败不降级为另一套策略。

## Verification Strategy
先以单元测试证明三态互斥、入口权限发起审批、令牌核销与跨动作隔离，再以拦截器/映射测试证明 DB 未命中失败关闭及失败重载保留最后成功快照；最后运行权限治理测试集、OpenAPI 解析和完整 Maven clean package。

## UI Design Track
NOT_APPLICABLE：无生产 UI 编辑；前端改造通过 Contract Handoff 明确交付。

## Rollback
应用回滚可恢复旧决策响应；数据库变更均为新增词汇/初始化同步。不得通过恢复静默兜底作为长期回滚方案。

