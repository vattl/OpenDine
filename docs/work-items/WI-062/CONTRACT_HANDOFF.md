# Contract Handoff — AUTHORIZATION-DECISION-V1

- Work Item: WI-062
- Origin: server
- Target: Flutter cashier/admin
- Status: READY_FOR_CONSUMER_IMPLEMENTATION

## Required consumer behavior
优先读取 `outcome`：`ALLOW` 继续操作，`REQUIRE_APPROVAL` 打开现场或二维码审批，`DENY` 显示 `reasonCode/explanation` 且不得自动重试。迁移期可继续读取 `allow` 与 `approvalRequired`。

## Follow-up
WI-063 将把退款、改价、优惠和反结账实际操作接入该决策器，届时补充每个动作的请求上下文和端到端测试。

