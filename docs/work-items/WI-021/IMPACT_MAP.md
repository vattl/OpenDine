# Impact Map — WI-021

## Authoritative Owner

`WechatNativePaymentAttemptEntity.active_key` 的 ORM 更新策略，以及 `WechatNativePaymentService` 的 Native 状态机。

## Layer Coverage

| Layer | Impact | Evidence |
|---|---|---|
| API | BEHAVIORAL | 路径和报文不变；修复 close 后再次 create 的既有契约 |
| Service | REVIEWED | close/query/create 终态均通过 `updateById` 清理 active_key |
| Persistence | DIRECT | nullable unique active_key 必须允许显式写 NULL |
| Callback | REVIEWED | 通知成功也依赖同一实体更新策略释放活动键 |
| Tests | DIRECT | ORM 元数据/服务回归及全量 Maven |
| UI | NONE | 无界面变更 |

## Consumers

- 收银端 Native create/query/close 客户端：无需适配。
- 微信支付通知：获得一致的活动键释放语义。

## Unknowns

NONE
