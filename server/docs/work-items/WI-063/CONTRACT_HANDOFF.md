# Contract Handoff — HIGH-RISK-ACTION-AUTHZ-V1

- Work Item: WI-063
- Origin: server
- Target: Flutter cashier/admin
- Status: READY_FOR_CONSUMER_IMPLEMENTATION

## Consumer obligations
- 退款/退菜、改价、优惠、反结账分别使用精确 permission。
- 业务接口返回 `REQUIRE_APPROVAL` 时打开现场/PIN/扫码审批；`DENY` 直接展示原因且不自动重试。
- `/cashier/access/authorize` 必须发送 `bindingVersion=2`、ORDER 资源、真实订单号、实际动作金额（适用时）、终端 ID 和请求 ID。
- 获取 token 后只重试原动作一次；不得跨订单、跨动作、跨终端复用。

详细前端实施清单见 `FRONTEND_ADAPTATION_GUIDE.md`。
