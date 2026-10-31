# Implementation Design — WI-030

## Root Fix / Owner

把“支付交易创建时的门店与商户绑定”作为唯一权威身份，并让支付创建、回调、退款和补偿全部验证这一身份；不再把客户端字段、本地缓存或模糊订单号作为资金路由依据。

## Why this location

`WechatMerchantRoutingService` 是新交易商户选择的唯一入口；`WechatMerchantKeyStore` 是凭据解析边界；`PaymentRefundLedger` 是退款申请事实来源。将规则放在这些领域所有者中，可同时覆盖 JSAPI、Native、MICROPAY、退款及补偿任务。

## End-to-End Change

### Backend

1. 路由规则无匹配时固定回退 `default`，忽略订单/客户端旧 `merchantId`。
2. 当前商户解析改为按 `shop_id + channel + merchant_key` 精确查询数据库，缓存只用于非资金关键展示/兼容。
3. `resolveBound` 增加期望门店参数，允许本店配置或已固化的全局模板，拒绝其他门店配置。
4. 支付成功要求回调 `mchid/appid` 非空并与固化配置一致。
5. 回调密钥候选携带配置 ID、版本、门店、商户号；解密后保留命中候选身份。
6. 退款回调以 `out_refund_no` 查询既有申请，由申请决定门店和订单，并校验金额、交易号、商户号和配置绑定。

### Frontend

无代码改动。客户端可继续发送历史 `merchantId`，服务端忽略其资金路由含义。

### UI / Interaction

NOT_APPLICABLE。

### Data / Persistence

- 为 `t_order(order_no)` 增加唯一索引。
- 为当前/历史商户表的 `platform_pub_key_id` 增加回调查询索引。
- 为退款申请增加 `merchant_config_id`、`merchant_config_version`、`expected_transaction_id`、`expected_mch_id`，并从订单/商户表回填存量待处理记录。

### Interfaces / Contracts

无路径或字段结构变化。行为收紧同步记录到 `docs/openapi.yaml` 和 `docs/API.md`。

### Jobs / Events / Integrations

退款补偿仍从退款台账读取申请，再按订单固化配置查询微信。回调继续支持密钥历史版本，但查询从全表扫描改为序列号索引。

## Preserve / Compatibility

- 旧交易若已有 `merchant_config_id/version`，继续解析当前或历史快照。
- 已授权全局模板交易允许 `dbShopId=0`；其他跨店配置拒绝。
- 历史没有绑定字段的支付仍可走兼容解析，但必须通过回调商户号/AppID与订单金额校验。

## API Consumer Migration / Handoff

不要求同步升级。建议后续客户端停止展示或提交商户选择字段，但不是本次上线依赖。

## Failure / Boundary Behavior

- 默认商户不存在：支付创建返回现有“当前门店未配置可用微信支付商户”。
- 商户配置跨店或版本缺失：查单/退款/回调 fail closed。
- 未登记、金额或商户不符的退款回调：返回 FAIL 触发微信重试并记录安全日志，不修改订单或流水。
- 重复订单号：数据库迁移失败，禁止带歧义数据继续上线。

## Runtime / Performance / Reliability

- 新支付使用精确索引 DB 查询，避免多实例永久陈旧；不对历史已绑定凭据强制 ACTIVE，保证在途交易可完成。
- 回调使用 `platform_pub_key_id` 索引缩小候选集合，避免随全部商户历史线性扫描。
- DB 行锁和退款唯一键继续提供多实例幂等。

## Security / Permissions

- 客户端不能选择资金接收商户。
- 解密成功只证明某个配置持有正确 APIv3 key，还必须与订单/退款申请绑定身份一致。
- 任何跨店绑定、缺失商户身份或未知退款单均拒绝自动入账。

## UI Design Track

NOT_APPLICABLE。

## Vertical Slice Plan

1. RED/GREEN：权威商户路由与 DB 实时解析。
2. RED/GREEN：固化凭据门店校验和支付回调强校验。
3. RED/GREEN：退款申请元数据、严格回调定位与校验。
4. 数据迁移、索引及合同文档。
5. 专项/全量测试、安全复核、JAR 打包和验收门禁。

## Verification Strategy

- 单元测试覆盖路由忽略客户端值、跨店固化凭据、缺失/错误 mchid/appid。
- 退款测试覆盖未知单号、金额/交易号/商户号不匹配、重复回调和正确入账。
- 静态检查迁移中的唯一键、索引和回填语句。
- 运行支付专项测试、全量 Maven 测试、OpenAPI 解析及 `mvn clean package -DskipTests`。

## Rollback / Recovery

- Java 改动可按提交回退。
- 新索引和新增 nullable 字段均为向后兼容结构；若应用回滚，旧版本会忽略新增列。
- 唯一索引不建议回滚，它保护支付身份；上线前先执行重复订单号预检。
