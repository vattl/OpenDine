# Contract Delta — WI-020

- `DELETE /admin/payment/merchants/{id}`：从物理删除改为安全退役；成功返回 `retired=true`、`physicallyDeleted=false`。
- 新增 `POST /admin/payment/merchants/{id}/restore`：恢复退役商户。
- 新增 `GET/PUT /admin/payment/merchant-policy`：读取/设置当前目标门店的 `allowGlobalFallback`。
- 商户响应新增 `status`、`credentialVersion`、`runtimeSource` 等可选字段，不返回密钥明文。
- `merchantKey` 从仅文档化的 `default|small_amount` 扩展为合法自定义 key；继续兼容 `1|2`。
