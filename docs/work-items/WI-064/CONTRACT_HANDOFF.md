# Contract Handoff — ORDER-EXPECTED-VERSION-V1

- Work Item: WI-064
- Origin: server
- Targets: Flutter cashier/admin, mini program
- Status: READY_FOR_CONSUMER_IMPLEMENTATION

## Consumer Obligations
1. 读取订单/成功写响应中的 `revision` 并与订单快照一起保存。
2. 加菜、退菜、改价、优惠请求发送 `expectedVersion`。
3. 收到 HTTP 409 + `ORDER_VERSION_CONFLICT` 时停止自动重试，刷新订单并提示用户重新确认操作。
4. 不得拿最新 revision 自动套用旧操作意图，尤其是金额、退菜数量和审批动作。
5. 兼容期未适配客户端仍可不传，但不具备陈旧写保护。
6. 客户端统一只发送 `expectedVersion`，不要同时发送 camelCase 与 snake_case 两个别名。
