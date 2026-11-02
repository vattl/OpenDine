# Contract Delta — WI-063

## Affected endpoints
`POST /cashier/order/refund`、`refundDish`、`updatePrice`、`discount`、`unCheckout` 与 `POST /admin/order/refund`。

## Additive failure fields
授权未放行时响应保留 `code/msg`，并增加 `outcome`、`reasonCode`；需要审批时增加 `approval`（含精确审批权限）。成功响应不变。

## Request compatibility
继续支持 `approvalToken|approval_token` 与 `authorization: {account,password}`。新客户端应优先调用 `/cashier/access/authorize`，使用 `bindingVersion=2` 并把返回 token 带入动作接口。
