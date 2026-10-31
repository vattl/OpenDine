# Acceptance Report — WI-025

Decision: ACCEPTED

## Acceptance Evidence

- 余额支付、微信成功回调、收银结账与后台成功结账均在同一事务内先写/核验权威流水，再更新订单投影。
- 现金、余额本金、赠送金及微信退款均写负向且关联原支付的 REFUND；失败会回滚订单、钱包和退款请求状态。
- REVERSAL 不超过原支付未冲正余额；全额冲正后新结算代次可创建新的 PAYMENT。
- 支付后履约、班次查询和日结预览不再补造流水。
- 日结存在订单—流水缺失、金额或渠道差异时返回 `ORDER_LEDGER_MISMATCH`，不签发预检令牌。
- 对账按支付营业日取数并排除挂账；内部/渠道未匹配、金额差异或开放案件均不会显示已对平。
- API 文档、专项 151 项、全量 1361 项测试、OpenAPI 解析、格式/敏感信息检查和可运行 JAR 构建均通过。

## Scope Boundary

接受范围是服务端代码与本地构建产物；尚未部署，未在生产数据上清理历史账本差异，也未完成真实渠道账单 E2E。

## Release State

ACCEPTED only；不是 INTEGRATED / RELEASED。
