# API Consumer Handoff — WI-020

- 管理端删除成功后应显示“已退役”，不要显示“凭据已永久删除”；可通过 restore 重新启用。
- 商户列表可展示 `status/credentialVersion`；密钥字段仍只显示 `******/has*`。
- 门店是否允许总部商户回退由 merchant-policy 显式控制；默认关闭。
- 自定义 `merchantKey` 可用于路由规则；旧 `default/small_amount` 和 `1/2` 不失效。
