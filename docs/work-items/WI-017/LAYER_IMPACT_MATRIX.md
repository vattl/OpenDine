# Layer Impact Matrix — WI-017

| Surface | Impact | Action |
|---|---|---|
| Cashier consumer | Behavioral | 并发请求可能直接获得复用二维码；仍应禁用重复点击。 |
| Native create API | Behavioral | 冲突分支增加有界等待。 |
| Native payment service | Code | 观察并复用胜出支付尝试。 |
| Database | None | 保留唯一活动键。 |
| WeChat API | Guarded | 冲突请求不得调用。 |
| Payment callbacks/query/close | None | 不修改。 |
