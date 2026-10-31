# WORK ITEM — WI-025

## Request

依据订单与资金流水审计，修复所有结算入口、退款、冲正、日结和对账之间的一致性，确保财务可追溯、可阻断、可核对。

## Type

REPAIR

## State

ACCEPTED

## Requirement Contract

### Goal

`t_payment_ledger` 是已收资金的唯一权威事实；`t_order` 只保存业务状态及资金事实投影。任何支付、退款和冲正必须在同一事务中先写入或精确核验不可变流水，再更新订单投影；读取、班次统计和日结不得反向补造高可信流水。

### Target behavior

- 余额支付、微信回调、收银结账和后台结账全部执行流水优先，并持有订单行锁。
- 微信、现金和余额退款写入关联原 PAYMENT 的 REFUND 流水，失败时订单和钱包变更整体回滚。
- 反结账只冲正尚未冲正的有效 PAYMENT；全额冲正后允许新结算代次重新收款。
- 支付成功处理器只负责事务提交后的履约，不再补造资金流水。
- 班次查询、日结预览和对账查询保持只读。
- 日结前逐单比较订单渠道余额与 PAYMENT/REFUND/REVERSAL 净额；任何差异阻断日结。
- 对账按支付营业日统计，并显式排除挂账订单；未匹配内部流水必须进入综合差异状态。

### Must preserve

- 多门店隔离、微信商户路由、JSAPI 尝试互斥和回调精确金额校验不降级。
- API 路径和请求/成功响应主体保持兼容。
- 挂账销售不伪造支付流水；真实回款继续进入应收流水。
- 已存在的历史补录能力保留为显式迁移工具，但不得在业务读取路径自动执行。

### Acceptance criteria

- [x] 所有已识别支付成功入口都先写权威流水再更新订单。
- [x] 所有已识别退款入口都写 REFUND 流水且与订单/钱包更新原子一致。
- [x] 冲正后可按新请求重新结账，重复冲正不会生成超额负流水。
- [x] 支付成功处理、班次查询和日结预览不再自动补造流水。
- [x] 日结在订单与流水缺失、渠道或金额不一致时阻断。
- [x] 对账使用统一营业日口径，挂账与真实收款分离，内部未匹配会判为差异。
- [x] RED/GREEN 专项测试、全量测试、OpenAPI 校验和可运行 JAR 构建通过。

## Business Invariants

- INV-FIN-001：每笔 PAYMENT/REFUND/REVERSAL 先于对应订单资金投影写入，并处于同一数据库事务。
- INV-FIN-002：同一退款幂等号的订单、渠道、金额、原流水和第三方退款号必须完全一致。
- INV-FIN-003：REVERSAL 只冲正原 PAYMENT 的未冲正余额，累计不得超过原金额。
- INV-FIN-004：成功非挂账订单的渠道余额必须等于成功流水按渠道净额。
- INV-FIN-005：任何读模型不得创建 NATIVE/TRUST_HIGH 权威资金事实。
- INV-FIN-006：存在资金差异时不得签发日结预检令牌或完成日结。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-025/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-025/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

ACCEPTED

## Acceptance Decision

`ACCEPTANCE_REPORT.md`：ACCEPTED（服务端能力；未部署）。
