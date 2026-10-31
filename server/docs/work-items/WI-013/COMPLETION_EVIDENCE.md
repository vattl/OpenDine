# Completion Evidence — WI-013

## 变更概述

增加强制结账能力并严格校验 `admin:manage` 权限，消除因扫码收款会话已确认（`CONFIRMED`）但订单未结或会话冲突导致结账被锁死、无法出码收银的问题。

## 修改清单

1. **实体与意向服务扩展**：
   - `Order.java`：增加 `@JsonProperty("force") Boolean force` 与 `@JsonProperty("approvalToken") String approvalToken` 瞬态字段；
   - `CashierCollectionIntentService.java`：
     - 新增 `completeAllForOrder(shopId, orderNo)` 原子收敛该订单名下所有待确认与已确认收款意向为 `COMPLETED`；
     - 重载 `validateCheckout(shopId, orderNo, sessionId, wechatFen, alipayFen, boolean force)`，当 `force=true` 时放行并清理冲突待确认占用。
2. **结账服务层业务串联与特权鉴权**：
   - `CashierCheckoutService.java`：
     - 实现 `checkForceCheckoutPermission`：支持操作人具备 `admin:manage` / 超管身份豁免、店长现场密码授权（`SensitiveOperationAuthorizationService`）及审批令牌核销（`ApprovalService`）；
     - `checkoutInternal` 串联权限校验，并在结账成功后原子调用 `completeAllForOrder`，记录特权安全审计日志（`securityAuditService.recordPrivilegedAction`），返回 `forced: true`。
3. **接口层与权限映射**：
   - `CashierOrderController.java`：暴露 `POST /cashier/order/force-checkout` 端点；
   - `AdminOrderController.java`：暴露 `POST /admin/order/force-checkout` 端点；
   - `ApiPermissionMapping.java`：为两个专用端点显式映射 `admin:manage` 权限码。
4. **单元测试与门禁验证**：
   - 新增 `CashierForceCheckoutTest`：全覆盖无权限拒绝 (403)、超管放行、权限持有放行及安全审计日志写入；
   - 专项测试通过：44 tests 全部 PASS；
   - 全量编译打包完成：`target/diancan-0.0.1-SNAPSHOT.jar` 生成完成；
   - 门禁通过：`python .ai/scripts/gate.py work --work-item docs/work-items/WI-013 --phase accept` -> **PASS**。
5. **文档与契约同步**：
   - 同步更新 `docs/openapi.yaml`（发布日志 v1.2.288、各接口参数与端点定义）；
   - 同步更新 `docs/API.md`（新增《强制结账支持 admin:manage 权限契约（v1.2.288 / WI-013）》）。
