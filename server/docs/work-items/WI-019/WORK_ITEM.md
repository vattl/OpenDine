# WORK ITEM — WI-019

## Request

修复收银微信 Native 下单将微信明确拒绝与不确定异常全部折叠为 `50331` 的问题，使客户端获得可操作的安全返回，同时保留防重复收款保护。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

微信 HTTP 4xx 明确拒绝必须释放当前支付尝试并返回安全化拒绝原因；网络异常、微信 5xx、响应验签失败或无法判定是否已受理时继续保持 `UNKNOWN`。

### Must preserve

- 任何不确定结果不得释放活动占用或允许直接重新收款。
- 微信响应签名验证不得放宽。
- 日志和 API 响应不得包含 Authorization、签名、私钥、完整响应体或其他密钥材料。
- 已有订单金额、门店、商户和并发幂等规则不变。

### Acceptance criteria

- [x] 微信 4xx 错误分类为明确拒绝，本地尝试收敛为 `CLOSED/PAYERROR` 并释放 `active_key`。
- [x] 明确拒绝返回 `code=40231`、安全化提示及可选 `wechatCode/requestId`。
- [x] 网络异常、5xx 和响应验签失败仍返回 `50331` 且保持 `UNKNOWN`。
- [x] Native 创建失败写入可诊断、无敏感信息的结构化日志。
- [x] 专项测试、全量回归、API 文档和 runnable JAR 完成。

## Acceptance Decision

ACCEPTED（仓库内；尚未部署生产或执行真实商户交易）

## Business Invariants

- INV-PAY-001：未经微信权威确认不得标记支付成功。
- INV-PAY-002：只有可证明未受理的微信拒绝才能释放活动支付占用。
- INV-PAY-003：网络、5xx 或验签失败属于不确定结果，必须阻止重复收款。

## Implementation Ready

- Status: `YES`
- Blockers: NONE
