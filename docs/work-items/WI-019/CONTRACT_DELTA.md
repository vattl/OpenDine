# Contract Delta — WI-019

- `POST /cashier/payment/wechat/native/orders` 新增业务码 `40231`：微信明确拒绝下单，服务端已确认本次调用未成功并释放活动占用。
- `40231` 可携带 `wechatCode`、`requestId`；均为非敏感诊断字段。
- `50331` 收窄为无法确定微信是否受理的场景；客户端仍不得直接重复收款，必须先查单。
