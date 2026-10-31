# Impact Map — WI-074

## Audit Routing Inputs

Risk Level: HIGH
UI Impact: MINOR
Contract Impact: BOTH
Security Impact: YES
Data / Migration Impact: YES
Reliability / Performance Impact: YES

## Authoritative Owner

- `OrderInvoiceServiceImpl`: 发票生命周期与状态机、Token 安全生成与校验、金额与退款约束的主管服务。
- `PublicInvoiceController`: 顾客公开查询与抬头提交网关。
- `AdminOrderController`: 收银端发票二维码生成、状态查看与人工录入网关。
- `WechatJsapiChannel`: 微信 JSAPI 支付通道下单参数构造者。

## Change Propagation Path

```text
Customer / Cashier Request
→ Public / Admin Controller (Token 鉴权 / 参数类型校验)
→ OrderInvoiceServiceImpl (支付状态校验 / 累计开票金额计算 / Token 哈希比对 / 状态机流转)
→ t_order_invoice (Flyway V050 token_hash / token_expire_at)
→ invoice-apply.html (顾客端文案更正 / PII 掩码渲染 / 防抖控制)
→ WechatJsapiChannel (support_fapiao 参数透传)
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 收银端后台 | 生成开票二维码、查询发票、人工补录凭证 | AFFECTED | YES | `AdminOrderController` |
| 顾客端 H5 | 扫码查询发票、提交抬头、回显信息 | AFFECTED | YES | `PublicInvoiceController`, `invoice-apply.html` |
| 微信支付服务 | 统一下单接收 `support_fapiao` | AFFECTED | YES | `WechatJsapiChannel` |
| 数据库存储 | 持久化发票记录与 Token 哈希 | AFFECTED | YES | `V050__invoice_token_auth_and_audit.sql` |
| 审计与日志 | 记录操作与异常，脱敏敏感数据 | AFFECTED | YES | `OrderInvoiceServiceImpl` 日志格式化 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | AFFECTED | 修正 `invoice-apply.html` 虚假文案、增加提交防抖与 PII 掩码显示 |
| Interaction | AFFECTED | 提交开票防抖禁用、错误反馈与下载链接校验 |
| Frontend State | AFFECTED | 渲染已提交/已开具信息时执行掩码过滤 |
| API Client | AFFECTED | `WechatJsapiChannel` 增加 `support_fapiao` 参数 |
| Request Contract | AFFECTED | 公开查询与提交接口将 `token` 设为必填，金额使用精确类型 |
| Backend/Domain | AFFECTED | `OrderInvoiceServiceImpl` 核心状态机与累计可开票金额校验 |
| Persistence | AFFECTED | `t_order_invoice` 新增 `token_hash`、`token_expire_at`、`token_used_at` 字段 |
| Response Contract | AFFECTED | 公开接口返回脱敏数据，去除泄露字段 |
| Jobs/Events/Integrations | AFFECTED | 移除不可用服务商 API，降级为本地受控二维码 |
| Config/Security | AFFECTED | 拦截器放行策略不变，但在控制器层实施 Token 哈希鉴权 |
| Runtime/NFR | AFFECTED | 状态流转条件更新，幂等防重 |
| Tests | AFFECTED | 编写单元测试与集成测试覆盖安全与状态逻辑 |

Classifications: AFFECTED / VERIFIED_UNAFFECTED / NOT_APPLICABLE / UNKNOWN.

## Duplicate Logic / Patch Smells

- `invoice-apply.html` 在 `src/main/resources/static/` 与 `src/main/resources/static/invoice/apply.html` 存在重复静态页，需同步更正。
- 历史代码将 token 存入 `error_msg`，语义冲突。通过 V050 独立列拆分。

## Contract Delta Summary

- `GET /api/public/invoice/info`: 变更 `token` 为必须参数（`@RequestParam String token`）；若未传或无效返回 403 Forbidden；若无发票记录返回 404 Not Found（不再自动创建）。返回的税号、手机、邮箱进行掩码处理。
- `POST /api/public/invoice/submit-title`: 变更 `token` 为必须参数；若无效拒绝；禁止匿名覆盖其他订单发票。
- 微信 JSAPI 下单请求体增加选填字段 `support_fapiao`。

## UI Semantic Impact

顾客扫码进入发票申请页后，看到清晰真实的“老肥家餐饮 · 发票抬头登记服务”，提交后提示商家处理中，回显信息脱敏保护隐私。

## Risks

- 历史已打印未过期的旧开票二维码缺少 token 或 token 格式不一致时无法查询：通过平滑兼容校验机制（对新生成的强制走高熵 token，对存量旧记录给出友好提示“请收银员重新生成开票二维码”）。
