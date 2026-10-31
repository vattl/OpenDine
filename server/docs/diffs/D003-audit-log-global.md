# D003 — 全局操作审计日志（AOP 注解化）

状态：IMPLEMENTED（P0+P1 全部完成，2026-09-05）
日期：2026-09-05

## 目标态

高价值操作通过 `@AuditLog` 注解 + AOP 切面自动写入 `t_operation_log`（审计日志），覆盖收银全操作、运营退菜、退款全链路；审计记录失败不阻断业务。

## 变更分类

| 元素 | 操作 | 说明 |
|---|---|---|
| `pom.xml` | ADD | `spring-boot-starter-aop` 依赖 |
| `com.lanf.audit.annotation.AuditLog` | ADD | 方法级审计注解（module/action/target SpEL/diff 钩子） |
| `com.lanf.audit.aspect.AuditLogAspect` | ADD | `@Around` 切面：参数快照/脱敏/截断、结果状态、DiffProvider 前后状态、失败不阻断 |
| `com.lanf.audit.context.AuditContext` | ADD | 从 `RequestContextHolder`/`SysInterceptor` 属性解析 adminId/shopId/traceId/ip |
| `com.lanf.audit.diff.DiffProvider` / `NoopDiffProvider` / `OrderRefundDiffProvider` | ADD | 前后状态快照钩子（退款场景：refund_amount + 渠道列） |
| `SecurityAuditService` | MODIFY | 新增 `recordPrivilegedActionWithState`（含 before/after）与 `recordFailed`（FAILED 语义），persist 原逻辑不动 |
| `CashierOrderController` | MODIFY | 8 个写操作方法加注解：quickOrder/addDishes/refundDish/refund/updatePrice/discount/checkout/unCheckout |
| `AdminOrderDetailController.delete_menu` | MODIFY | 运营退菜加注解 |
| `OrderController.refund` | MODIFY | 退款发起（微信+余额）加注解 |
| `WechatRefundSettlementService.settle` | MODIFY | 回调/补偿入账加注解 |

## 第二批（2026-09-05 完成）

- 菜品管理 5 端点（save/updateOnSale/updateSaleStatus/importFromHq/sort；hqTemplateList 查询、uploadImage 上传不埋）
- 优惠券 9 端点（add/update/redeem-code 建删/batch-send/user-coupon grant/批量 Excel/void/unbind）
- 会员 2 端点（recharge/deductBalance；充值流水表保留）
- 运营订单 8 端点（changeId/receiving/reassignOpenidByPhone/rece/checkout/manualDiscount/addPoints/auto-accept）
- `AdminOrderController.wechatRefund` 不重复埋：内部委托 `OrderController#refund`，已由 refund_apply 覆盖
- 新增 `DishStockDiffProvider`（detailId → t_dish_shop.stock 前后态），运营退菜 delete_menu 挂载
- 未埋（低价值/查询/上传）：banner、文件上传、reprintKitchen、getUserInfo 等

## 第三批（2026-09-05 完成，P1 配置类）

- 备货预测 6 端点（BOM/配置/计划）、外卖 5 端点（配置/状态/派单）、物料 3 端点（保存/入库/出库）
- 类目 3 + 单位 1 + 套餐 1、桌台 2、公告 2、系统配置 6（AdminConfigController）
- KDS 运维 4（死信重试/替换/丢弃、设备权限）
- 不埋（查询/入站/设备级）：deliveryList、deadLetters、kds events 接收、push 设备注册/注销、banner/上传
- 库存批次核查：AdminInventoryBatchController 无写端点（0），无需补审计（修正前轮审计结论）

## 兼容性

- 存量手动埋点（inventory 5 controller、settings/printing/notification 等）**保留不动**，与注解切面并存
- 收银 `logOrder`（t_order_log 业务流水）保留，与审计日志职责不同
- 切面记录失败仅 error，不影响任何业务返回值
