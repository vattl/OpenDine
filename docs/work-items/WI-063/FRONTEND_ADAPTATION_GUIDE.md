# 前端适配指南 — WI-063 高风险订单动作权限

## 1. 影响范围

收银端需要适配以下动作：

| UI 动作 | 业务接口 | execute permission |
|---|---|---|
| 现金/组合退款、退菜 | `/cashier/order/refund`、`/cashier/order/refundDish` | `order:operate:refund` |
| 改价、赠送 | `/cashier/order/updatePrice` | `order:operate:changePrice` |
| 优惠、折扣、抹零 | `/cashier/order/discount` | `order:operate:discount` |
| 反结账 | `/cashier/order/unCheckout` | `order:operate:reopen` |
| 运营微信退款 | `/admin/order/refund` | `order:operate:refund` |

## 2. 统一调用流程

1. 正常调用业务接口，并始终发送 `X-Shop-Id`、`X-Terminal-Id`、`X-Client-Request-Id`。
2. `code=0`：按原成功流程处理。
3. `outcome=REQUIRE_APPROVAL`：读取 `approval.permission`，打开现场密码/PIN 或扫码授权。
4. `outcome=DENY`：展示 `msg`；不得自动打开审批，也不得自动重试。
5. 获得 `approvalToken` 后，只对原请求重试一次并增加 `approvalToken`；订单号、金额、门店、终端和操作员必须保持不变。

不要再以 `code=401/403` 或中文 `msg` 猜测是否需要审批，权威判断是 `outcome`。

## 3. 现场授权请求

推荐调用 `POST /cashier/access/authorize`：

```json
{
  "permission": "order:operate:discount",
  "bizType": "ORDER",
  "bizId": "ORD-20261024-001",
  "amount": 10.00,
  "authorizerAccount": "M1001",
  "credential": "******",
  "authMethod": "PASSWORD",
  "terminalId": "POS-01",
  "requestId": "c4b7...",
  "bindingVersion": 2,
  "reason": "会员九折"
}
```

金额绑定规则：

- 现金退款：本次退款金额；业务请求省略金额时，后端按“现金列剩余与剩余可退额的较小值”解析权威金额。前端建议先明确展示并传实际退款额，避免独立授权请求与最终金额不一致。
- 改价/赠送：`total_price` 新值，赠送为 `0`。
- 优惠：服务端最终优惠额；前端使用 payRate/wipeZero 时，建议先计算展示值并确保与服务端舍入口径一致。若无法确保，直接使用业务接口的兼容 `authorization` 完成同请求授权。
- 退菜、反结账：当前版本金额为空。

兼容期也可直接在原业务请求带：

```json
{
  "authorization": {
    "account": "M1001",
    "password": "******"
  }
}
```

服务端会把该凭据转换为严格 v2 单次令牌并立即核销。新代码应优先使用独立授权接口，便于 PIN、扫码和统一交互。

## 4. 权限与按钮

- `cashier:operate`：按钮可见/可发起，但不代表能直接执行。
- 有对应 execute permission：按钮可直接执行，不弹审批。
- 没有 execute 但有入口权限：按钮仍可见，提交后按 `REQUIRE_APPROVAL` 弹审批。
- 后端返回 `DENY`：即使本地权限缓存显示可用也必须阻断并刷新权限。
- 不要用 `order:operate`、`admin:manage`、`refund:approve` 等宽泛权限替代精确动作权限。

## 5. 响应模型

前端建议增加统一模型：

```dart
enum AccessOutcome { allow, requireApproval, deny }

class ActionAccessFailure {
  final int code;
  final String message;
  final AccessOutcome outcome;
  final String? reasonCode;
  final String? approvalPermission;
}
```

兼容处理：旧服务端没有 `outcome` 时暂沿用现有错误流程；新服务端存在 `outcome` 时必须以它为准。

## 6. 验收用例

- 收银员点击四类动作均能发起审批，但未批准前业务数据不变化。
- 店长只有退款审批权限时，只能批准退款/退菜，不能批准改价、优惠或反结账。
- token 换订单、换门店、换终端、换动作或改金额后重试均失败。
- 同一 token 第二次使用失败。
- 反结账即使审批成功，包含外部实收或已日结订单仍被业务规则拒绝。
- execute 权限员工可直接执行对应动作，但不能因此执行其他动作。
