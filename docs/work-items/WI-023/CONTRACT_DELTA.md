# Contract Delta

Capability: accounts-receivable
Reason: 将占位“挂单”能力扩展为独立的商业应收闭环。

## Request

### Before

只有 `/cashier/order/hang {order_no}`，不产生状态变化。

### After

新增账户管理、eligible accounts、charge、collect、reverse、write-off、claims、statement、aging 端点。财务写请求均带 `requestId`；挂账金额由服务端订单计算。

### Consumers

| Consumer | Reviewed | Change needed | Evidence |
|---|---:|---:|---|
| Cashier | YES | YES | API_CONSUMER_HANDOFF.md |
| Admin | YES | YES | API_CONSUMER_HANDOFF.md |
| Mini program | YES | NO | 不开放 C 端权限 |

## Response

### Before

挂单仅返回 `order_no`；日结无应收摘要。

### After

返回 account/claim/ledger/aging 资源；日结增加 `receivable_summary` 和真实 `total_collections_fen`。

### Consumers

| Consumer | Reviewed | Change needed | Evidence |
|---|---:|---:|---|
| Cashier | YES | YES | API_CONSUMER_HANDOFF.md |
| Admin reporting | YES | YES | API_CONSUMER_HANDOFF.md |
| Existing payment clients | YES | NO | additive contract |

## Semantic Delta

“挂单”仍表示暂存未结订单；“挂账”表示完成销售并形成应收；“回款”才表示实际收款。

## UI Impact

- labels: 挂单、挂账、应收回款必须分开。
- controls: 账户选择、额度余额、到期日、回款和坏账权限。
- validation: 禁止客户端金额、超额度、超收和跨店。
- state/action mapping: ACTIVE/SUSPENDED/CLOSED；OPEN/PARTIAL/SETTLED/OVERDUE/WRITTEN_OFF/REVERSED。
- empty/error/loading states: 消费者需实现，详见 handoff。
