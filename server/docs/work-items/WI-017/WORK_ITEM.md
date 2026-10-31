# WORK ITEM — WI-017

## Request

修复收银微信 Native 支付创建接口在同一订单并发请求时返回 `40931`，导致收银端把正常的幂等竞争显示为失败的问题。

## Type

BUG

## State

ACCEPTED

## Acceptance Decision

ACCEPTED（仓库内；尚未部署生产）

## Requirement Contract

### Goal

同一订单的并发 Native 创建请求只允许一个请求调用微信下单；其他请求在短暂等待后复用胜出请求生成的二维码。

### Must preserve

- 同一门店订单最多一个活动支付尝试。
- 竞争失败的请求不得再次调用微信下单。
- `UNKNOWN` 或长时间停留在 `CREATING` 的结果仍需返回安全提示，不得假定失败或成功。
- 金额、门店、商户及订单归属继续由服务端确定。

### Acceptance criteria

- [x] 并发插入冲突后，胜出记录在等待窗口内进入可复用状态时返回同一二维码。
- [x] 等待窗口内未产生可复用二维码时仍返回 `40931`。
- [x] 并发请求不会产生第二次微信下单调用。
- [x] OpenAPI、API 文档、消费者 handoff、测试和 runnable JAR 同步完成。

## Business Invariants

- INV-PAY-001：未经微信权威确认不得标记支付成功。
- INV-PAY-002：同一订单并发创建不得产生多个活动微信支付单。
- INV-PAY-003：网络或处理中状态不得被误判为失败并重新下单。

## Tasks / Vertical Slices

- [x] T01 回归测试复现并发竞争失败。
- [x] T02 有界等待并复用胜出二维码。
- [x] T03 契约文档、回归、打包和验收。

## Implementation Ready

- Status: `YES`
- Blockers: NONE
