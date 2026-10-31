# 前端适配指南 — WI-061

目标仓库：`G:/Mini Program/my_project_admin_panel/admin_panel_flutter`

## P0：审批上下文升级到 binding v2

### `lib/src/features/auth/data/access_approval_repository.dart`
- `authorize` 和 `createQrApproval` 请求体固定发送 `bindingVersion: 2`。
- 同时发送稳定、非空的 `terminalId`，并在后续敏感业务重试请求头发送相同的 `X-Terminal-Id`。
- 订单敏感操作统一发送 `bizType: ORDER`、真实 `bizId=orderNo`，禁止 `N/A`、`ID:` 或本地列表下标。
- `amount` 必须与后续核销请求使用同一十进制业务金额；非金额动作两边都不传。

### `lib/src/features/cashier_shell/presentation/cashier_approval_dialog.dart`
- 当前 `_terminalId` 返回 `null`，必须改为从登录会话/设备注册服务读取稳定终端 ID；应用重启后仍应保持一致，切换实际设备时才变化。
- 未取得终端 ID 时不要降级发 v1；阻止发起审批并提示完成终端初始化。

### 敏感操作调用点
- `table_order_page.dart`、`cashier_bill_page.dart` 发起退款、折扣、改价/赠送时，使用下列精确动作权限：
  - 退款/退菜：`order:operate:refund`
  - 改价/赠送：`order:operate:changePrice`
  - 折扣：`order:operate:discount`
- 审批签发和最终业务重试必须复用同一 `permission`、`orderNo`、金额、操作人、门店和 terminal ID。

## P0：处理 429，避免重试风暴

### `lib/src/features/auth/domain/access_approval_models.dart`
- 为 API 错误数据增加 `retryAfterSeconds`、`rateLimitScope` 解析。
- 为授权、二维码创建、二维码详情模型增加 `bindingVersion`、`legacyBinding`、`requiredApprovalPermission`。

### `cashier_approval_dialog.dart`
- 收到 HTTP 429 或错误码 `ACCESS_APPROVAL_RATE_LIMITED` 后，按 `retryAfterSeconds` 显示倒计时并禁用“授权/重新生成二维码/确认”按钮。
- 倒计时只在本地递减；不要每秒请求服务端。归零后由用户主动重试。
- `rateLimitScope=CREDENTIAL_FAILURE` 时提示“授权凭据尝试过多”；其他 scope 提示“审批请求过于频繁”。不要显示账号是否存在。
- 现有 QR 状态每 2 秒轮询可保持；状态接口未纳入限流。弹窗销毁或状态终结时必须停止定时器。

## P0：角色权限与审批页

- 权限中心/角色编辑器加入以下三个权限的中文标签，并支持单独分配：
  - `order:operate:refund:approve`：退款审批
  - `order:operate:changePrice:approve`：改价审批
  - `order:operate:discount:approve`：折扣审批
- 不要根据 `order:operate`、`admin:manage` 或岗位名称推断审批能力；以服务端权限集合为准。
- 店长扫码详情展示 `requiredApprovalPermission` 对应的人类可读名称。
- AGREE 和 REJECT 都可能返回 403；读取 `data.requiredApprovalPermission`，提示“缺少【退款审批】权限”，不要把 REJECT 当作无需权限的本地操作。

## P1：兼容观察与错误处理

### `lib/src/core/admin_api_client.dart`
- 保持审批接口的 401/403 为业务弹窗错误，不把授权人凭据失败误判成当前登录会话失效。
- 429 不触发登出、不刷新登录 token；将结构化 data 原样传给审批对话框。
- 若 v2 请求响应 `legacyBinding=true` 或 `bindingVersion != 2`，记录遥测并阻止使用该 token，避免静默安全降级。

## 验收测试

- 更新 `test/access_qr_approval_test.dart`：断言 create/authorize body 含 `bindingVersion: 2`、真实 `terminalId`，后续请求头 `X-Terminal-Id` 一致。
- 增加 429 对话框测试：显示倒计时、按钮禁用、无自动重建二维码、倒计时结束可手动重试。
- 增加 403 测试：AGREE/REJECT 均展示 `requiredApprovalPermission` 的中文名称。
- 增加模型测试：解析 `bindingVersion`、`legacyBinding`、`requiredApprovalPermission`、`retryAfterSeconds`、`rateLimitScope`。
- 对退款、折扣、改价/赠送各做一次端到端测试，确认签发与核销六项上下文完全一致，token 只消费一次。

## 联调顺序

1. 先部署数据库 V040 和本后端版本，确认旧角色已获得显式审批权限。
2. 发布前端 429/权限展示和 binding v2。
3. 观察服务端 `legacyBinding` 使用率归零。
4. 另开 Work Item 关闭 v1；WI-061 不宣称已经关闭兼容窗口。
