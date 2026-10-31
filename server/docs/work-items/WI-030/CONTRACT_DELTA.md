# Contract Delta — WI-030

## Compatibility

BACKWARD_COMPATIBLE_VALIDATION_TIGHTENING

## Request behavior

- 订单请求中的历史 `merchantId` 字段继续被接受，但不再决定新支付的收款商户。
- 微信退款回调必须关联本系统已登记的 `out_refund_no`；未知或绑定不一致的通知返回 FAIL。

## Response behavior

现有成功响应字段、错误包装和路径均不变。

## Consumer action

NONE。消费者可在后续版本停止提交 `merchantId`，但不影响本次部署。
