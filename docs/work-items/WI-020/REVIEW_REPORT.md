# Independent Review — WI-020

Review Decision: PASS
Critical Open: 0
High Open: 0

## Method

在实现完成后执行与编码步骤分离的第二遍审查，按正确性、安全性、兼容性、可维护性和交付完整性五个维度核对差异、测试与契约；本次未委派其他代理，因此不宣称外部人员审查。

## Findings closed

- 修正商户继承策略接口的执行顺序：先保存策略，再刷新配置。
- 保持旧 `merchantId=1/2` 到 `default/small_amount` 的映射，同时不再压缩任意 merchantKey。
- 确认退役不是物理删除，历史凭据和私钥文件引用可继续服务在途交易。
- 确认管理端写接口、权限 SQL、OpenAPI 和 API 文档同步。
- 确认未把支付不确定状态误判为成功，未放宽金额或跨门店控制。

## Residual risks

- 真实微信证书、APIv2/APIv3 密钥及回调域名只能在部署环境做联调。
- V024 必须在应用版本上线前执行并做好数据库备份。
