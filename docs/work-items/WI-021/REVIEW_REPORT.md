# Independent Review — WI-021

Review Decision: PASS
Critical Open: 0
High Open: 0

## Independent second pass

本次未委派其他代理；实现后以独立第二遍检查持久化语义、状态机边界、历史数据和 API 契约。

## Findings

- 根因修复位于共享实体字段，覆盖 close/query/notify/create rejection 的全部 Native 终态更新。
- 所有 `WechatNativePaymentAttemptMapper.updateById` 调用均使用从数据库读取或完整创建的实体，不存在仅带 ID 的局部实体因 IGNORED 策略误清活动键。
- 历史 CLOSED 残留记录无需数据迁移，可在下一次 create 时自愈。
- 自愈只清活动键并保留原 status/trade_state 诊断信息。
- 没有放宽 UNKNOWN/CREATING 防重复收款规则。
