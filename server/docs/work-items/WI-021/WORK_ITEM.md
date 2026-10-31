# WORK ITEM — WI-021

## Request

修复 Native 微信支付成功关单后，同一业务订单再次下单无法创建新二维码的问题。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

Native 未支付交易成功关单后必须在数据库中释放活动唯一键，同一门店同一订单可立即创建新的支付尝试；并发防重和未知状态保护保持不变。

### Current behavior

服务将实体 `active_key` 设为 null 后调用 MyBatis-Plus `updateById`，默认字段策略忽略 null，导致数据库仍保留旧活动键，下一次插入命中唯一索引并返回 40931。

### Target behavior

所有 Native 终态路径（关单、查单收敛、支付成功、明确拒绝、通知成功）均可将 `active_key` 持久化为 SQL NULL；只有 ACTIVE/CREATING/UNKNOWN 占用活动键。

### Must preserve

- UNKNOWN/CREATING 仍禁止重复下单。
- 同一订单仍最多存在一条活动尝试。
- 支付成功订单仍禁止重新创建或关单。
- 不改变请求/响应结构和鉴权规则。

### Acceptance criteria

- [x] Native attempt 的 null 活动键会被 MyBatis-Plus update SQL 包含并写为 NULL。
- [x] 关单后旧 attempt 释放活动键，同订单可创建新 attempt。
- [x] UNKNOWN/CREATING 并发保护测试继续通过。
- [x] Native 专项与全量测试通过，JAR 构建成功。

## Business Invariants

- INV-NATIVE-001：同一门店同一订单同时最多一个未决 Native 尝试。
- INV-NATIVE-002：微信状态不确定时不得重新出码，避免重复收款。
- INV-NATIVE-003：明确终态必须释放本地活动键，不得阻塞合法重试。

## Acceptance Decision

ACCEPTED

仓库修复及自动化验证完成；尚未部署生产，不表示 RELEASED。

## Implementation Ready

- Status: `YES`
- Blockers: NONE
