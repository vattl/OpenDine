# Layer Impact Matrix — WI-020

| Surface | Impact | Action |
|---|---|---|
| Admin merchant API | Compatible extension / safer delete | 生命周期、恢复、策略和版本字段。 |
| Cashier/mini program | Behavioral | 服务端自动路由；成功形状不破坏。 |
| Payment services | Structural | 统一 route + binding；删除调用点硬编码。 |
| Database | Migration | V024 新表/字段/索引与默认值。 |
| Credential store | Security | 新写入 fail closed；历史加密快照。 |
| Consumer repos | Handoff | 可选适配 retired/version/policy；旧 API 仍可调用。 |
