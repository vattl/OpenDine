# 微信支付普通商户收银端发票模块审计报告 — WI-073

Audit Date: 2026-10-28

Product Verdict: BLOCKED

Scope: 普通微信支付商户、收银端发票申请、顾客抬头采集、真实开票交付、退款冲红和安全闭环。

Production Code Modified: NO

Real WeChat API Called: NO

## Executive conclusion

当前实现具备“生成本地二维码、采集发票抬头、后台人工录入发票号码、查询本地状态”的雏形，但不具备可证明的真实电子发票开具与交付闭环，且存在公开接口越权风险。不得以现状向商户或顾客宣称已经完成微信电子发票接入，也不应上线公开开票入口。

普通商户可在支付下单时通过 `support_fapiao=true` 开启支付成功消息和支付详情页的开票入口；完整的微信电子发票抬头、开具、插卡、冲红、查询和下载 API 位于合作伙伴/普通服务商产品域。当前代码混用了两种模式。

## Official capability boundary

| Check | Result | Evidence |
|---|---|---|
| 普通商户支付后发票入口 | PASS（能力存在，项目未接入） | [普通商户 JSAPI 开发指引](https://pay.weixin.qq.com/doc/v3/merchant/4012791870.md) 要求下单时传 `support_fapiao=true`，下单后不能补传。 |
| 普通商户官方文档能力面 | PASS | 用户提供的[普通商户官方索引](https://pay.weixin.qq.com/doc/v3/merchant/llms.txt)列出普通商户产品/API；当前索引不含完整电子发票 API 产品段。此项为基于官方索引的能力边界推断。 |
| 获取用户抬头填写链接 | ISSUE | [官方接口文档](https://pay.weixin.qq.com/doc/v3/partner/4015770776.md)明确“支持商户：普通服务商”，并要求 `sub_mchid`、`openid`、`total_amount` 等参数。 |
| 完整开具/插卡/冲红 | ISSUE | [合作伙伴电子发票开发指引](https://pay.weixin.qq.com/doc/v3/partner/4015792556.md)要求服务商授权、配置、开具、通知、插卡、查询/下载及冲红闭环。 |

## Findings

### F-01 — CRITICAL — 公开开票接口的 token 未校验，可读取和篡改发票信息

Status: OPEN

Evidence:

- `PublicInvoiceController` 将 `token` 作为可选参数传入服务：`src/main/java/com/lanf/controller/PublicInvoiceController.java:26-49`。
- `getInvoiceInfoForPublic` 只按 `order_no`/可选 `apply_id` 查询，未比较 token，却返回抬头、税号、邮箱、手机号和文件地址：`src/main/java/com/lanf/service/impl/OrderInvoiceServiceImpl.java:239-309`。
- `submitInvoiceTitleFromCustomer` 同样不校验 token，可覆盖抬头及联系方式：`src/main/java/com/lanf/service/impl/OrderInvoiceServiceImpl.java:313-426`。
- 订单号存在时，匿名查询还会自动创建发票记录：`src/main/java/com/lanf/service/impl/OrderInvoiceServiceImpl.java:253-286`。
- 三组公开别名均被鉴权拦截器放行：`src/main/java/com/lanf/config/WebAppConfigurer.java:90-94`。
- 现有测试甚至把无 token 自动初始化当作成功路径：`src/test/java/com/lanf/service/OrderInvoiceServiceTest.java:239-256`。

Impact: 知道或猜到订单号的人可匿名查看发票个人/企业信息、创建申请并修改抬头；属于隐私泄露和业务完整性破坏。

Required direction: 使用独立、不可逆摘要存储的高熵 token；token 必填、恒定时间比较、绑定 `order_no + apply_id + shop_id`、短期过期、单用途/可撤销；公开接口限流并禁止“查不到即创建”；返回数据最小化；补充越权、错误 token、过期 token、重放测试。

### F-02 — HIGH — 微信抬头链接 API 身份、参数和响应契约均不匹配

Status: OPEN

Evidence:

- 代码调用 `/v3/new-tax-control-fapiao/user-title/title-url`：`OrderInvoiceServiceImpl.java:33-34,79-110`。
- 官方接口仅支持普通服务商，必填 `openid`，响应为 `miniprogram_appid/miniprogram_path/miniprogram_user_name`：[官方接口文档](https://pay.weixin.qq.com/doc/v3/partner/4015770776.md)。
- 当前请求未传 `openid`，用普通商户解析结果的 `mchId` 同时作为签名商户和 `sub_mchid`，并尝试读取文档不存在的 `title_url`：`OrderInvoiceServiceImpl.java:81-108`。
- 代码只取 `miniprogram_path`，没有同时返回跳转必需的 `miniprogram_appid`：`OrderInvoiceServiceImpl.java:101-108`。
- 官方链接有效期为 30 分钟，代码对外声明 1440 分钟：`OrderInvoiceServiceImpl.java:166` 与[官方接口文档](https://pay.weixin.qq.com/doc/v3/partner/4015770776.md)冲突。

Impact: 普通商户真实环境会返回无权限/参数错误；即使服务商模式开通，响应解析和跳转契约仍不完整。

Required direction: 先确定产品模式。普通商户模式不得直接调用该接口；若选择服务商模式，需保存服务商商户号/证书、子商户授权状态和用户 OpenID，严格按官方字段构造与解析，并接通抬头完成通知和查询。

### F-03 — HIGH — 系统没有真实开票能力，却可人工把状态标记为 SUCCESS

Status: OPEN

Evidence:

- 微信失败时降级到本地抬头页面，并宣称可开具增值税电子发票：`OrderInvoiceServiceImpl.java:122-129`。
- `issueInvoice` 仅接受客户端提交的发票号码/代码/文件 URL，直接更新 `SUCCESS`，未调用税控/第三方平台、未验证凭证或文件：`OrderInvoiceServiceImpl.java:429-465`。
- 微信发票通知处理仅记录长度并返回成功，没有验签、解密、幂等或状态更新：`OrderInvoiceServiceImpl.java:468-473`。
- 仓库没有暴露该通知的 Controller 路由，也没有开具、查询、下载、上传/插卡 API 调用。
- OpenAPI 将该人工登记操作描述为“开票成功”：`docs/openapi.yaml:6947-6974`。

Impact: 本地 `SUCCESS` 不等于税务意义上的真实发票已开具，可能产生虚假成功、错误交付和财税对账风险。

Required direction: 对接合规税控/第三方开票平台，或通过已授权微信服务商模式开具；以平台受信结果驱动状态；验证回调签名、资源解密和幂等；人工补录必须是受控异常流程并附审核凭证，不能冒充自动开票。

### F-04 — HIGH — 微信支付下单未开启普通商户发票入口

Status: OPEN

Evidence:

- `WechatJsapiChannel` 构造 JSAPI 下单请求时只包含 appid、mchid、description、out_trade_no、time_expire、notify_url、amount、payer，没有 `support_fapiao`：`src/main/java/com/lanf/payment/channel/wechat/WechatJsapiChannel.java:117-138`。
- `WechatNativeApiClient` 和 `OrderController` 的其他下单路径也未检索到 `support_fapiao`。
- 全仓库生产代码检索无 `support_fapiao`/`supportFapiao`。
- [普通商户 JSAPI 开发指引](https://pay.weixin.qq.com/doc/v3/merchant/4012791870.md)明确该字段必须在下单时传入且无法补传。

Impact: 即使商户已开通能力，用户也不会在支付成功消息/详情页看到官方开票入口。

Required direction: 在所有适用的微信支付下单通道统一、可配置地设置 `support_fapiao=true`，并验证商户已开通发票能力；非适用支付类型明确 N/A。

### F-05 — HIGH — 未验证支付状态，任意状态可生成申请或标记开票成功

Status: OPEN

Evidence:

- 管理端生成二维码只验证订单存在和门店范围，未检查 `transac_status/pay_time`：`AdminOrderController.java:1448-1488`。
- 公开查询/提交会针对任何可解析订单自动初始化：`OrderInvoiceServiceImpl.java:253-286,371-420`。
- 人工登记只检查订单和发票号码存在，不检查支付/退款状态或允许的状态迁移：`AdminOrderController.java:1521-1548`、`OrderInvoiceServiceImpl.java:429-465`。

Impact: 未支付、取消、退款订单可能开票；PENDING_SCAN 可直接跳到 SUCCESS；失败/冲红状态也可能被覆盖。

Required direction: 建立严格状态机和服务端不变量：仅支付成功、可开票余额大于零才创建；状态迁移采用条件更新/乐观锁；禁止非法跳转；操作全量审计。

### F-06 — HIGH — 重复/累计超额开票和退款冲红未闭环

Status: OPEN

Evidence:

- 生成申请只复用 `PENDING_SCAN` 记录；已有 TITLE_SUBMITTED/SUCCESS 后可再建新申请：`OrderInvoiceServiceImpl.java:146-156`。
- 数据表仅对 `fapiao_apply_id` 唯一，`order_no` 只有普通索引：`src/main/resources/db/migration/V049__api_permission_granularity_and_audit.sql:24-27`。
- 金额校验只看当前订单净收入，未扣除该订单已有未冲红发票累计金额：`OrderInvoiceServiceImpl.java:57-68`。
- 虽定义 `REVERSED` 状态，但未发现冲红入口、服务或退款事件联动：`src/main/java/com/lanf/entity/OrderInvoice.java:24-35`。
- 微信官方 FAQ 明确支付后先部分退款会失去账单开票入口：[服务商电子发票常见问题](https://pay.weixin.qq.com/doc/v3/partner/4016960715.md)。

Impact: 同一订单可能累计开票超过实付；已开票后退款不会冲红；财务、支付和发票状态长期不一致。

Required direction: 维护订单级可开票余额和累计有效发票金额；以数据库约束/锁保证并发一致；退款申请前检查发票状态，成功退款触发自动冲红或受控人工待办；全额/部分退款均有明确状态和补偿任务。

### F-07 — HIGH — 敏感发票数据被明文写入日志

Status: OPEN

Evidence: 提交抬头后直接记录抬头、税号、邮箱和手机号：`OrderInvoiceServiceImpl.java:423-424`。

Impact: 日志系统、运维人员和日志导出路径可获得完整个人/企业敏感信息，扩大泄露面。

Required direction: 只记录申请 ID、订单脱敏标识和状态；税号、手机、邮箱按数据分类脱敏/加密；限制日志访问与保留周期。

### F-08 — MEDIUM — 金额和税率输入使用浮点数，税率由收银端自由传入

Status: OPEN

Evidence:

- Controller 用 `Double.parseDouble` 解析金额，服务使用 `double` 比较再转 `BigDecimal`：`AdminOrderController.java:1467-1481`、`OrderInvoiceServiceImpl.java:57-69`。
- 税率可由请求直接指定，缺少商品税目/商户配置校验：同上。

Impact: 可能发生边界舍入误差和错误税率，无法满足严格财税口径。

Required direction: 接口金额使用整数分或字符串 decimal，内部统一 `BigDecimal`；税率和税目由服务端商品/税务配置决定，不信任客户端。

### F-09 — MEDIUM — 访问 token 与错误信息复用同一字段，且无有效期模型

Status: OPEN

Evidence: token 存入 `error_msg`：`OrderInvoiceServiceImpl.java:125-142`；状态查询又把 `error_msg` 返回为失败原因：`OrderInvoiceServiceImpl.java:211-212`；表结构没有 token 哈希、过期、使用时间字段：`V049__api_permission_granularity_and_audit.sql:4-27`。

Impact: 安全凭据和业务错误语义混杂，容易在后台响应/日志中泄露，也无法过期或撤销。

Required direction: 拆分 `access_token_hash`、`expires_at`、`used_at`、`failure_code/message`，永不回传原 token。

### F-10 — HIGH — 微信 APIv3 接口应答未校验签名直接消费数据

Status: OPEN

Evidence:

- 在获取微信发票抬头链接时：`src/main/java/com/lanf/service/impl/OrderInvoiceServiceImpl.java:94-109`。
- 代码使用 `restTemplate.exchange(...)` 接收 `ResponseEntity<String> response` 后，在 `response.getStatusCode().is2xxSuccessful()` 时直接使用 `objectMapper.readValue(response.getBody(), Map.class)` 解析数据并提取 `title_url` / `miniprogram_path`。
- 全过程完全未读取或验证 `Wechatpay-Signature`、`Wechatpay-Timestamp`、`Wechatpay-Nonce`、`Wechatpay-Serial` 应答头。
- 微信支付官方技术规范明确规定：所有 APIv3 接口应答与异步回调均必须使用微信支付公钥或平台证书验证签名后方可使用数据，见官方指引 [4012365870-服务端如何验证签名](https://pay.weixin.qq.com/doc/v3/merchant/4012365870.md) 与 [4013053249-如何使用微信支付公钥验签](https://pay.weixin.qq.com/doc/v3/merchant/4013053249.md)。

Impact: 破坏零信任边界，若发生上游链路中间人篡改或异常响应，未经验签的跳转路径可能导致小程序劫持或恶意链接注入。

Required direction: 所有微信 APIv3 HTTP 请求应答必须通过统一样式抽取的验签拦截器/公共工具类，严格使用微信支付公钥对 `Wechatpay-Timestamp + "\n" + Wechatpay-Nonce + "\n" + responseBody + "\n"` 进行 SHA256withRSA 签名校验，验签失败直接阻断抛出异常，严禁盲信 HTTP 2xx 响应体。

### F-11 — HIGH — 顾客端发票 H5 页面存在虚假完成文案、敏感数据裸露与不可信下载链接风险

Status: OPEN

Evidence:

- 仓库生产资源 `src/main/resources/static/invoice-apply.html`（及构建副本 `target/classes/static/invoice-apply.html`）：
- **虚假完成宣传**：Line 265-266 标题硬编码“国家税务总局全国统一规范电子发票开具服务”，Line 334 提示“财务系统正在自动处理开具增值税电子发票，开具成功后将发送至您的预留邮箱/手机短信”，Line 555-556 宣称“发票开具成功...发票已生成，请在下方点击直接下载查看”。但后端仅有人工录入状态，没有任何自动税控与交付系统，属于严重的虚假宣传。
- **隐私泄露**：Line 564-585 在未认证情况下直接将后端返回的 `data.buyerTitle`、`data.buyerTaxNo`、`data.buyerEmail`、`data.buyerPhone` 完整展示在 DOM 中。结合 F-01 匿名越权漏洞，攻击者可枚举订单号直接在前端页面抓取企业与个人隐私。
- **不可信下载链接注入**：Line 590-592 直接将未校验协议与域名的 `data.fapiaoFileUrl` 注入 `<a id="btnDownload" href="...">`，容器包含 `downloadBox`。人工录入恶意链接即可伪造成发票下载进行钓鱼或跨站攻击。

Impact: 对顾客产生虚假合规误导，且公开暴露纳税人识别号、手机号、邮箱及开放任意跳转风险。

Required direction: 移除虚假税务机关与自动交付宣传；在真实税控系统完成前明确标注“发票信息登记中”；公开页面必须依赖强认证鉴权 token，且对渲染的税号、手机、邮箱进行脱敏掩码；对下载链接实施服务端域名白名单或安全反向代理验证。

## 微信支付开发技能三部分质量审查

依据 `wechatpay-payment-integration` 技能规范要求，审查整合以下三部分：

### 一、通用质量检查清单

| 检查领域 | 检查项 | 判定 | 审计证据与现状分析 |
|---|---|---|---|
| **编码风格** | 签名、验签、加解密抽成公共方法 | ISSUE | `WechatJsapiChannel` 中实现了部分签名方法，但 `OrderInvoiceServiceImpl.java:94-109` 的发票接口直接手拼 headers 且应答未验签，回调未实现路由，缺乏统一公共验签组件。 |
| **安全** | 调用微信支付接口要签名 | PASS | `WechatJsapiChannel` 和 `OrderInvoiceServiceImpl:91` 使用商户私钥计算签名并写入 Authorization。 |
| **安全** | 应答和回调都要验签 | ISSUE | `OrderInvoiceServiceImpl.java:94-109` 应答未验签；发票回调方法仅占位 `OrderInvoiceServiceImpl.java:468-473`，无验签无路由。见 F-10。 |
| **安全** | 回调与查单结果必须与本地订单核对一致 | ISSUE | 发票无回调与查单核对逻辑；状态变更直接来自客户端人工提交 `AdminOrderController.java:1521`。 |
| **安全** | 签名探测流量不得跳过验签或直接当成功 | ISSUE | 发票通知完全未实现针对 `WECHATPAY/SIGNTEST/` 探测流量的处理机制。 |
| **安全** | 密钥只留服务端，不得泄露到任何外部可获取的位置 | PASS | 商户证书与私钥由 `WechatMerchantKeyStore` 从本地安全路径加载，未硬编码或前端暴露。 |
| **安全** | 敏感字段加解密按接口文档逐字段执行 | N/A | 本次涉及的发票抬头获取接口不要求对报文字段进行国密/RSA加密，但存在明文日志问题。 |
| **安全** | 资金 / 关键字段一律以后端为准，严禁相信前端传值 | ISSUE | 人工开票允许前端直接传入税率与发票金额 `AdminOrderController:1467-1481`。 |
| **安全** | 金额全程使用整数分，不经过浮点 | ISSUE | Controller 使用 `Double.parseDouble`，Service 中使用 `double` 比较：`OrderInvoiceServiceImpl.java:57-69`。见 F-08。 |
| **安全** | 前端返回成功不能当作支付成功 | ISSUE | 发票状态由人工点击接口直接置为 SUCCESS，未以真实开票结果为准。见 F-03。 |
| **安全** | 不得忽略服务端证书校验错误 | PASS | 使用 Spring RestTemplate 默认信任库，未发现 trust-all 忽略证书校验代码。 |
| **安全** | 签名、验签、加解密须有 echo 实测证据 | UNVERIFIED | 项目未接入 APIv3 `POST /v3/security/echo` 本地验证测试套件。 |
| **幂等** | 重试必须使用原单号且原参数 | ISSUE | 发票重新生成或失败重试未严格复用原申请单号，多次调用生成不同 applyId。 |
| **幂等** | 同一笔业务只能处理一次 | ISSUE | `order_no` 无唯一索引约束，可重复为已开票订单发起申请并累计超额开票。见 F-06。 |
| **幂等** | 防止重复下单（前端与服务端都要做） | ISSUE | 收银端生成发票申请与提交抬头无服务端分布式锁或数据库条件防重。 |
| **接入链路稳定性** | 对外调用必须设超时，重试必须有界 | PASS | 依赖全局 RestTemplate 配置的连接/读取超时。 |
| **接入链路稳定性** | 异步通知缺失时主动查单 | ISSUE | 无定时对账或发票状态主动向微信/税控平台轮询查询机制。 |
| **接入链路稳定性** | 配置主备域名，异常时自动切换并在恢复后回切 | ISSUE | 发票接口硬编码 `https://api.mch.weixin.qq.com`，无备用域名自动切换。 |
| **API规范** | 字段名与取值以该接口文档为准 | ISSUE | 将服务商抬头接口的 `miniprogram_path` 当作 `title_url` 提取，且未带 `openid`。见 F-02。 |
| **API规范** | 应答解析兼容性 | PASS | 使用 Jackson ObjectMapper 反序列化为 Map，对未知字段兼容。 |
| **API规范** | 按 HTTP 状态码和 code 处理，禁止按 message 做逻辑判断 | ISSUE | 错误信息直接落库为 `error_msg` 并透传给前端，无标准错误码状态机。 |
| **打印日志** | 成功和失败都记录 Request-ID，且不记录敏感明文 | ISSUE | 未记录微信应答的 `Request-ID`，且日志明文打印用户姓名、税号、手机和邮箱。见 F-07。 |

### 二、电子发票单业务注意事项

1. **普通商户能力边界**：普通商户仅支持在统一下单请求时传入 `support_fapiao=true`，由微信客户端在支付成功后展示官方开票入口。当前代码完全未传入该参数。
2. **普通服务商能力混淆**：代码中调用的 `/v3/new-tax-control-fapiao/user-title/title-url` 为微信支付普通服务商电子发票能力，要求服务商授权、`sub_mchid`、用户 `openid` 并接通插卡闭环，普通商户无法直接调用。
3. **闭环完整性要求**：电子发票业务必须覆盖“抬头采集 -> 发票开具 -> 电子发票插卡 -> 状态通知 -> 发票下载/冲红”。当前项目只截取了伪造的抬头与人工开具，全链路处于割裂状态。

### 三、流程规则核对

依据 `.agents/skills/wechatpay-payment-integration/references/流程规则与测试用例` 逐条核对：

| 规则文件夹 | 适用性判定 | 规则核对结论 | 规则与测试依据 |
|---|---|---|---|
| **通用-付款按钮防抖避免连续调起两次支付** | 适用 | 不通过 | `invoice-apply.html:327` 点击后未立即禁用提交按钮；后端 `PublicInvoiceController` 与 `OrderInvoiceServiceImpl` 未对发票抬头提交做分布式锁防重处理。 |
| **通用-没收到回调或回调出错须查单** | 适用 | 不通过 | 项目未实现发票异步回调 Controller 映射；无任何后台主动轮询发票开具状态的补偿机制，完全依赖客户端或人工刷新。 |
| **付款码支付-状态不明须查单并撤销** | 不适用 | 不适用 | 本 Work Item 审计的为收银端扫码与 JSAPI 支付后的发票开具流程，项目未接入被扫付款码发票反查，不适用。 |
| **退款-非成功须查单并原单重试** | 适用 | 不通过 | 订单退款链路 `AdminOrderController` 与退款处理完全未联动发票状态机；已开票订单发生退款时不会触发冲红，退款重试未保证发票状态一致性。 |

## Quality checklist 汇总

| Area | Result | Summary |
|---|---|---|
| 产品身份与权限 | ISSUE | 混用普通商户和普通服务商能力 |
| 支付下单开票标记 | ISSUE | 未传 `support_fapiao` |
| 抬头采集 | ISSUE | 官方请求契约错误；本地 token 不校验 |
| 真实开票 | ISSUE | 无税控/第三方/微信开具调用 |
| 回调验签与幂等 | ISSUE | 仅占位方法，无路由和验签 |
| 查询与下载 | ISSUE | 仅返回人工 URL，无受信查询/下载 |
| 状态机 | ISSUE | 可非法跳转，无条件更新 |
| 退款与冲红 | ISSUE | 无闭环 |
| 重复/并发/累计金额 | ISSUE | 无订单级约束 |
| 门店隔离 | PASS（管理端）/ISSUE（公开端） | 管理端检查当前门店；公开端仅凭全局订单号且不校验 token |
| 隐私与日志 | ISSUE | PII 明文日志、匿名读取风险 |
| API 文档一致性 | ISSUE | 文档把人工登记描述为开票成功，token 标为可选 |
| APIv3 应答验签 | ISSUE | 微信发票接口 HTTP 2xx 响应未验签即使用 (F-10) |
| 顾客端 H5 界面 | ISSUE | 存在虚假税务对接宣称、PII 数据泄露及下载链接风险 (F-11) |
| 自动化测试存在性 | PASS | 存在服务/Controller 单测 |
| 自动化测试执行 | PASS | 本地无外部网络调用的 Python 审计验证套件已全部通过 |
| 真实商户联调 | UNVERIFIED | 本次未获真实商户授权且审计范围严格禁止真实 API 调用 |

## Recommended remediation sequence

1. 立即关闭或保护公开发票查询/提交路由，修复 token 强校验和 PII 日志问题，清除顾客端 H5 的虚假合规文案与敏感信息泄露风险。
2. 决策产品模式：普通商户 + 自建/第三方税控，或授权普通服务商微信电子发票；删除另一模式的误导性调用/文案。
3. 接入真实开票平台，建立受信状态机、回调验签、应答验签、幂等、查询下载和失败补偿。
4. 统一所有微信支付下单路径的 `support_fapiao` 配置（仅在已开通且业务适用时）。
5. 建立订单级累计可开票金额、重复开票约束和退款/冲红联动。
6. 补充安全、状态、并发、退款、回调和端到端测试；在沙箱/测试商户完成联调后再开放入口。

## Release decision

发票模块上线：BLOCKED。

允许继续使用的范围：仅可在内部受控环境将其视为“发票抬头采集/人工登记原型”，且必须先关闭匿名越权风险；不得对外宣称微信电子发票已接通或自动开票可用。
