# Layer Impact Matrix — WI-018

| Surface | Impact | Action |
|---|---|---|
| Cashier API | Behavioral hardening | 仅返回已验签微信结果。 |
| Native API client | Code | 所有同步响应统一验签。 |
| Merchant key store | Existing owner | 继续提供同一 DB 私钥、序列号和平台公钥。 |
| Database | None | 无字段或迁移。 |
| JSAPI/MICROPAY | None | 不修改既有客户端。 |
