# Implementation Design — WI-020

## Root Fix / Owner

当前数据模型允许多行商户，但运行时只识别 `default/small_amount`，门店缺失时静默使用全局商户，配置更新/物理删除又没有交易版本绑定。根修复必须把“商户配置”提升为有生命周期、有版本、可路由且可被交易稳定引用的领域对象，而不是继续在调用点增加分支。

## Data Design

1. `t_payment_merchant_config` 增加 `status`（ACTIVE/RETIRED）与 `credential_version`。
2. 新增 `t_payment_merchant_config_history`，在凭据或身份字段更新前保存旧版本的加密快照。
3. 新增 `t_payment_merchant_policy`，按门店保存 `allow_global_fallback`，默认 0。
4. `t_order`、Native attempt、MICROPAY attempt 增加 `merchant_config_id/merchant_key/merchant_config_version` 绑定字段。

## Runtime Design

1. 当前支付解析先查本店 ACTIVE 商户；仅策略明确允许时查询全局 ACTIVE 模板。
2. `1/2` 只作为兼容输入，内部归一化为 `default/small_amount`；其他合法 key 原样保留。
3. 路由器按本店启用商户的 `routing_rule_json` 与 `sort_order` 选择；支持 `amount_and_dining`、`minPaidYuan`、`maxPaidYuan`、`diningTypes`、`targetMerchantKey`，无匹配使用 default。
4. 创建支付时固化配置 ID/key/version；后续操作优先按绑定解析当前行或历史快照。
5. 删除端点改写 `status=RETIRED, enabled=0`；恢复端点重新激活。历史快照和密钥文件不自动删除。

## Credential Safety

- 没有 `PAYMENT_CONFIG_MASTER_KEY` 时禁止新增/更改 APIv2/APIv3 密钥；仅 debug 配置可显式允许 `plain:`。
- 继续兼容读取既有 `plain:` 数据，便于迁移，但运营保存时必须重新加密。
- 清除仓库 SQL dump 中的真实样式数据，保留无秘密模板。

## Compatibility

- 原 CRUD 路径保留；DELETE 仍返回成功，但明确 `retired=true, physicallyDeleted=false`。
- 新增恢复与 merchant-policy API；旧客户端可忽略新增字段。
- 订单历史 `merchantId=1/2` 继续解析；新交易同时写入明确绑定字段。

## Verification Strategy

先写 RED 测试覆盖明文写入、物理删除、跨店回退、任意 merchantKey、路由和绑定版本，再按垂直切片实现；最后执行支付专项、全量测试、OpenAPI 解析、迁移检查、secret scan 和完整 JAR 打包。
