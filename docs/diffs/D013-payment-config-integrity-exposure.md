# D013 支付配置模块完整性/逻辑性修复（口径暴露与文档化）

- 日期：2026-09-08
- 状态：IMPLEMENTED（2026-09-08 提交后更新；`compile` 通过）
- 风险等级：LOW（新增只读字段 + 文档化；不改任何既有字段值、不动支付门控）
- 关联：`/change` 审计支付配置模块完整性与逻辑性后开始修复（L3 收银微信就绪原因、G2 收银微信可开启查询、L4/L2/L7 口径文档化）

## 1. 审计结论回顾（决定修复范围）

完整性与逻辑性审计（见会话内审计计划与结果）发现 8 项逻辑问题 + 2 项完整性缺口。逐项复核后**修正与收敛**：

| 项 | 结论 | 处理 |
|---|---|---|
| I1/I2 支付宝就绪缺失/零校验 | **设计如此**：支付宝线上收款=个人码 + webhook 共享密钥（`payment.personal-collect.webhook-secret`，HMAC-SHA256 验签，`PersonalAlipayWebhookController`），**不依赖 `t_payment_merchant_config`**（alipay 证书字段为预留）。加商户校验/就绪暴露会误伤个人码模式 | 不加代码；文档化 |
| L3 收银微信 effective 与原因不可见 | 收银微信 `effective=false` 时前端无就绪原因（G1） | **加字段** |
| G2 缺 canEnableCashierWechatPay | D012 后收银微信可独立开启，无查询字段 | **加字段** |
| L4 legacy channels 口径不对称 | openapi v1.2.175 承诺 channels 保持兼容，不改值 | 文档化口径 |
| L2 ready 双口径同名不同义 | 宽松=default 行存在；严格=字段齐全 | 文档化 |
| L7 merchant 列表 vs capabilities ready 口径 | per-row（isEnabled+missing）vs merged default，可能矛盾 | 文档化差异 |
| L1/L5/L6/L8 | 默认值/恒 true/双写/重复计算 | 不处理（无行为影响，避免不必要改动） |

## 2. FIX（逐文件 Diff）

### 2.1 `PaymentCapabilityService.java`（+3 只读字段）

`toPublicMap`：新增

```java
out.put("canEnableCashierWechatPay", r.wechatMerchantReady);
```

`clientCapabilities` 的 cashier 块：新增

```java
cashier.put("wechatMerchantReady", r.wechatMerchantReady);
cashier.put("wechatReadyHint",
        r.wechatMerchantReady ? "" : PaymentMerchantReadiness.ENABLE_WECHAT_PAY_HINT);
```

语义：
- `clients.cashier.wechatMerchantReady`：宽松就绪（default 微信商户行存在）。`effectiveChannels.wechat=false` 且此值为 false 时，前端可明确展示"需先配置 default 微信商户"。
- `clients.cashier.wechatReadyHint`：未就绪时的引导文案（复用 `ENABLE_WECHAT_PAY_HINT`）；就绪时为空串。
- `canEnableCashierWechatPay`：顶层，= 宽松 ready（收银微信能否开启）。与 `canEnableMiniProgramWechatPay`（严格）口径区分。

### 2.2 `docs/openapi.yaml`

- `GET /config/payment-capabilities`、`GET/PUT /admin/payment/capabilities` 描述补充：
  - `clients.cashier.wechatMerchantReady` / `wechatReadyHint`（就绪原因，L3/G1）
  - `canEnableCashierWechatPay`（宽松口径；`canEnableMiniProgramWechatPay` 为严格口径）
  - `channels` 旧兼容组口径：`wechat`=小程序微信口径、`alipay`=收银口径、`combined`=收银组合口径、`offlineCollect`=线下收款码；**与 `clients.*` 并存不删除**（v1.2.175 兼容契约）
  - ready 双口径：`wechatMerchantReady`（宽松：default 商户行存在）/`miniProgramWechatMerchantReady`（严格：字段齐全）
  - 支付宝线上收款=个人码 + webhook 共享密钥验签，**不依赖支付商户配置**；`t_payment_merchant_config` 的 alipay 证书字段为预留
- changelog 追加 v1.2.225。

### 2.3 `docs/diffs/D013-*.md`

本文件（IMPLEMENTED）。

## 3. REGRESSION（回归验证）

1. 单测：新增字段均为只读（不改解析/门控），`PaymentCapabilityServiceClientTest` 等现有断言不受影响。
2. 手工：shop5（未配 default 商户）调 `GET /config/payment-capabilities`：
   - `clients.cashier.wechatMerchantReady=false`、`wechatReadyHint`=引导文案、`canEnableCashierWechatPay=false`
   - `effectiveChannels.wechat=false` 与 `wechatReadyHint` 一致（原因可见）
3. 支付回归：不触碰 `resolve()` 门控与支付发起链路，无行为变化。

## 4. 交付说明

- 覆盖：收银微信就绪原因暴露（L3/G1）、收银微信可开启查询（G2）、支付宝个人码模式与 ready 双口径/channels 口径文档化（I1/I2/L2/L4/L7）。
- 未覆盖：支付宝商户就绪校验（判定为设计如此，不引入）；L1/L5/L6/L8（无行为影响，不处理）。
- 无破坏：全部为新增只读字段与文档，既有字段值、支付门控、接口契约（channels 兼容）均不变。
