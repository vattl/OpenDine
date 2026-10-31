# Impact Map — WI-076

## Audit Routing Inputs

Risk Level: MEDIUM
UI Impact: NONE
Contract Impact: NONE
Security Impact: NO
Data / Migration Impact: NO
Reliability / Performance Impact: YES

## Authoritative Owner

- `TakeoutZsqIntegrationServiceImpl`: 外卖聚合配送调度服务，负责订单类型鉴权、配送状态检查与防重保护，以及向第三方平台发起呼叫骑手。
- `KdsEventListener`: KDS 领域事件监听器，负责在整单制作完成流转到 `ALL_DONE` 且事务提交后，触发外卖自动叫骑手协同。

## Change Propagation Path

```text
KDS 划菜出餐完成 (KdsFlowBatchService / KdsWorkflowV2Service)
→ 发布领域事件 KdsOrderStatusChangedEvent(ALL_DONE)
→ 事务提交后由 KdsEventListener.onOrderStatusChanged 捕获
→ 调用 TakeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(orderId)
→ 校验订单类型（外卖）与配送单状态（防重/幂等）
→ 调用 TakeoutZsqIntegrationService.dispatchToZsq(orderId, false) 向真省钱发起叫骑手
→ 更新 t_takeout_delivery 状态与履约记录
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| KDS 厨显工作台 | 出餐划菜并广播事件 | AFFECTED | YES | `KdsEventListener.java` |
| 外卖聚合配送模块 | 调度骑手与更新履约数据 | AFFECTED | YES | `ITakeoutZsqIntegrationService.java`, `TakeoutZsqIntegrationServiceImpl.java` |
| 堂食与自提订单 | 保持原出餐通知行为 | PRESERVED | NO | 单元测试验证 |
| 接口文档 | 补充 KDS 联动外卖流转说明 | AFFECTED | YES | `docs/API.md`, `docs/openapi.yaml` |

## Layer Coverage

| Layer | State | Owner / Impact |
|---|---|---|
| Controller / API | PRESERVED | 现存 KDS 划菜与外卖接口不变 |
| Domain / Service | MODIFIED | `ITakeoutZsqIntegrationService`, `TakeoutZsqIntegrationServiceImpl`, `KdsEventListener` |
| Persistence / DB | PRESERVED | `t_takeout_delivery`, `t_order` 字段完全复用 |
| Frontend / UI | PRESERVED | 无 UI 修改 |
| Documentation | MODIFIED | 同步更新 `docs/openapi.yaml`, `docs/API.md` |
