# Frontend Adaptation Guide — WI-062

## 1. 适配范围

本阶段后端修改 `POST /admin/access/evaluate` 的决策语义，并收紧服务器入口权限映射来源。接口路径和请求字段不变，响应新增 `data.outcome`。退款、改价、优惠、反结账四个实际提交接口将在 WI-063 接入统一决策；前端可先完成模型与状态机适配。

## 2. 响应模型

建议 Flutter 增加：

```dart
enum AuthorizationOutcome { allow, requireApproval, deny }

AuthorizationOutcome parseOutcome(Map<String, dynamic> data) {
  switch (data['outcome']) {
    case 'ALLOW':
      return AuthorizationOutcome.allow;
    case 'REQUIRE_APPROVAL':
      return AuthorizationOutcome.requireApproval;
    case 'DENY':
      return AuthorizationOutcome.deny;
    default:
      // 兼容旧服务端，升级窗口内才使用；后续删除。
      if (data['allow'] == true) return AuthorizationOutcome.allow;
      if (data['approvalRequired'] == true) {
        return AuthorizationOutcome.requireApproval;
      }
      return AuthorizationOutcome.deny;
  }
}
```

不要只用 `allow == false` 显示“无权限”：`REQUIRE_APPROVAL` 表示当前员工可以发起审批，`DENY` 才是硬拒绝。

## 3. 交互状态机

```text
evaluate
├─ ALLOW → 直接提交动作
├─ REQUIRE_APPROVAL → 打开现场授权/扫码授权
│  ├─ 获得 approvalToken → 携带原始完整上下文重新 evaluate/提交
│  └─ 取消/超时 → 返回动作页，不提交
└─ DENY → 展示 reasonCode/explanation，不自动重试
```

授权重试必须复用相同 `permission/resourceType/resourceId/amount/shopId/operatorId/terminalId/requestId`，否则严格绑定核销会失败。

## 4. 动作权限常量

```dart
const refundPermission = 'order:operate:refund';
const changePricePermission = 'order:operate:changePrice';
const discountPermission = 'order:operate:discount';
const reopenPermission = 'order:operate:reopen';
```

前端不得把 `cashier:operate` 当作敏感动作执行权限，也不得自行拼接宽泛的 `order:operate`。审批端展示的权限分别为上述权限加 `:approve`。

## 5. 错误处理

- `ACCESS_APPROVAL_INVALID`：令牌无效、过期或已使用，清除本地 token，允许用户重新发起审批一次；不要无限自动重试。
- `ACCESS_EXPLICIT_DENY` / `ACCESS_PERMISSION_DENIED`：硬拒绝，显示权限原因并停止。
- HTTP 403 “接口权限未配置”：这是部署/权限映射异常，不应降级继续请求；上报 traceId 和接口路径。
- HTTP 429：继续沿用 WI-061 的 `retryAfterSeconds` 倒计时。

## 6. 兼容顺序

1. 先发布能识别 `outcome` 且兼容旧布尔字段的客户端。
2. 验证退款、改价、优惠、反结账授权弹窗都由三态驱动。
3. WI-063 后端切换实际动作接口后做端到端验收。
4. 观察期结束后再移除客户端旧布尔推断分支。

## 7. 前端验收用例

- 普通收银退款评估得到 REQUIRE_APPROVAL 并打开授权弹窗。
- 普通收银取消授权后没有提交退款。
- 有退款权限的员工得到 ALLOW，但不能因此直接改价或优惠。
- 无效/过期/已使用 token 得到 DENY，且不会重复提交动作。
- DB 映射缺失 403 被识别为系统配置异常并带 traceId 上报。
- 老服务端无 `outcome` 时仍能按 `allow + approvalRequired` 工作。
