# Implementation Design — WI-016

## Root Fix / Owner

在支付域新增独立 MICROPAY 尝试与微信 V2 客户端。付款码只存在于单次方法调用内；持久化稳定的 `out_trade_no` 和状态，支持查询/撤销收敛。成功响应转换为共享支付成功服务所需的规范载荷，不复制订单结算逻辑。

## Contract

- 创建：请求 `orderNo/authCode/terminalId?`；响应状态可能为 `SUCCESS` 或 `USERPAYING`。
- 查询：返回微信权威交易状态和本地状态；成功时已经完成本地入账。
- 撤销：必须在创建满 15 秒且查询未成功后执行，成功后释放活动键。
- 配置：APIv2 密钥采用现有凭据加密器；P12 只接受服务器路径引用并使用商户号作为默认口令。

## Failure / Security Design

- 硬化 XML 解析器禁止 DTD、外部实体和外部 schema。
- 响应先检查通信状态并验证 HMAC-SHA256 签名，再读取业务结果。
- 超时、系统错误、银行错误和支付中统一保持可查询的 `UNKNOWN/USERPAYING`。
- 明确失败释放活动键；成功和撤销为终态；不保存 `auth_code`。
- 撤销使用带 P12 客户端证书的独立 HTTP client。

## Migration / Compatibility

新增迁移，不修改历史迁移；配置字段和 API 为向后兼容新增，未配置 V2 凭据时仅付款码能力不可用。

## Verification Strategy

- 单元测试覆盖签名规范化、响应验签、XXE 拒绝、敏感数据不持久化、成功/支付中/明确失败、查询补偿、撤销前查单。
- 回归既有 Native/JSAPI 成功处理与商户配置。
- 校验 OpenAPI，执行完整测试及 `mvnw clean package -DskipTests`。
