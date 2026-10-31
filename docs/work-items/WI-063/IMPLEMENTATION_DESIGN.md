# Implementation Design — WI-063

## Root Fix / Owner
新增单一的高风险动作授权编排服务。Controller 只提供已解析的操作者、门店、动作、订单、金额、终端与请求号；编排服务调用 `AccessDecisionService`，并在需要审批且存在兼容现场凭证时，通过 `ApprovalService` 生成 bindingVersion=2 的令牌并立即回到统一决策器核销。

## Decision Flow
1. 以当前登录人和精确动作权限评估。
2. `ALLOW`：直接执行并记录当前操作人。
3. `DENY`：返回稳定原因，绝不尝试现场授权绕过显式拒绝/门店拒绝。
4. `REQUIRE_APPROVAL` 且无凭证/token：返回标准审批需求。
5. 携带 token：由决策器严格核销。
6. 携带兼容 `authorization.account/password`：签发 v2 严格令牌，立即重评并核销；授权人必须有精确 `:approve` 权限。

## Endpoint Mapping
| Endpoint | Action permission |
|---|---|
| `/cashier/order/refund`, `/cashier/order/refundDish`, `/admin/order/refund` | `order:operate:refund` |
| `/cashier/order/updatePrice` | `order:operate:changePrice` |
| `/cashier/order/discount` | `order:operate:discount` |
| `/cashier/order/unCheckout` | `order:operate:reopen` |

## Compatibility
- 请求继续接受 `approvalToken|approval_token` 与嵌套 `authorization`。
- 授权未完成响应补充 `outcome/reasonCode/approval`；旧 `code/msg` 仍存在。
- 不改变成功业务响应结构。

## Data Migration
V042 幂等回填四个 execute 和四个 approve 权限给明确的管理角色 `super_admin/owner/admin/boss/store_manager/shop_manager/shop_admin`；从内置 `cashier` 回收这些精确动作权限，不重写自定义角色或泛化 order operator。

## Verification Strategy
TDD 覆盖共享门面三态、现场授权严格绑定、跨动作隔离、Controller 精确动作接线、无授权不执行、角色迁移约束；再运行权限与订单相关回归、OpenAPI 解析和完整 Maven 打包。

## UI Design Track
NOT_APPLICABLE：本仓库无生产 UI 编辑；通过 Contract Handoff 交付前端适配。
