# D012 收银端微信支付开关去除 default 商户就绪拦截

- 日期：2026-09-08
- 状态：IMPLEMENTED（2026-09-08 提交后更新；`compile` 通过）
- 风险等级：LOW（删除一处开关前置校验，支付链路兜底保留）
- 关联：`/change` 审计支付配置相关接口，收银端的微信不需要拦截（截图：支付配置操作失败，要求先新增并启用微信支付商户 default）

## 1. SYMPTOM（现象）

运营/小程序端配置界面（PUT `/admin/payment/capabilities`）开启**收银端微信**支付开关时，弹窗报错：

> 支付配置操作失败：请先在支付商户配置中新增并启用微信支付商户（default），方可开启微信支付

即：收银端微信开关被「支付商户配置中存在启用的 default 微信商户」这一前置条件拦截。

## 2. REPRODUCTION（复现路径）

1. 门店未在支付商户配置中新增/启用 `default` 微信商户（`t_payment_merchant_config` 无 channel=wechat、merchant_key=default 的启用行）。
2. 调 `PUT /admin/payment/capabilities`，body 含 `cashierWechatEnabled: true`（或嵌套 `cashier: { wechat: true }`）。
3. `PaymentCapabilityService.upsert` 命中 `wantsEnableCashierWechat && !hasWechatPayReady(sid)` → 抛 `IllegalArgumentException(ENABLE_WECHAT_PAY_HINT)` → 前端弹窗。

## 3. ROOT CAUSE（根因）

`PaymentCapabilityService.upsert`（353-356 行）把**收银端微信开关**与**线上/小程序微信支付商户（default）就绪**强绑定：

```java
if (body != null && wantsEnableCashierWechat(body)
        && !merchantConfigService.hasWechatPayReady(sid)) {
    throw new IllegalArgumentException(PaymentMerchantReadiness.ENABLE_WECHAT_PAY_HINT);
}
```

其中 `hasWechatPayReady(shopId)` = `findMergedRow(shopId, WECHAT, "default") != null`（default 商户行存在）。

业务上不成立：收银端微信可走**线下收款**（`offline_collect` 渠道 wechat/alipay，个人收款码，不依赖服务器统一下单）等场景；`default` 商户是**线上/小程序统一下单**使用的。开启收银微信开关不应被 default 商户卡死。

## 4. TARGET（目标口径）

- **收银端微信开关**：可独立开启，**不校验** default 商户就绪（删除 353-356 校验）。
- **小程序端微信开关**：保留严格校验（344-352，`ENABLE_MINI_PROGRAM_WECHAT_PAY_HINT`，要求 default 商户字段齐全）。
- **支付发起兜底保留**：`WechatJsapiChannel.createPrepay`（81 行）在真实发起线上微信支付时仍校验商户配置（`ENABLE_WECHAT_PAY_HINT`）——收银端若走线上微信（组合支付 ONLINE_WECHAT），无商户配置时支付失败提示明确；线下收款不受影响。**这是支付硬约束，不是配置开关拦截**。

## 5. FIX（逐文件 Diff）

### 5.1 `PaymentCapabilityService.java`

删除 `upsert` 中收银微信校验块（353-356 行），替换为注释：

```java
// 收银端微信开关可独立开启，不要求 default 线上商户就绪（可走线下收款 offline_collect）；
// 线上微信支付发起时由 WechatJsapiChannel.createPrepay 兜底校验商户配置（D012）。
```

小程序端校验块（344-352）保持不变。

### 5.2 `PaymentMerchantReadiness.java`

`ENABLE_WECHAT_PAY_HINT` 的 javadoc 更新：该提示现仅用于**线上微信支付发起**兜底（createPrepay），不再用于收银端开关校验。

### 5.3 `docs/openapi.yaml`

`PUT /admin/payment/capabilities` 描述追加：开启收银端微信（`cashierWechatEnabled`）不再要求支付商户 default 就绪（D012）；小程序端微信（`miniProgramWechatEnabled`/`wechatEnabled`）仍要求 default 商户字段齐全。changelog 追加 v1.2.224。

## 6. REGRESSION（回归验证）

1. 单测：`PaymentCapabilityServiceClientTest` 等现有测试不受影响（校验删除不触及 toPublicMap 逻辑）；如有 upsert 校验测试需同步（当前未见）。
2. 手工：未配 default 商户 → `PUT /capabilities` 开 `cashierWechatEnabled=true` 成功、落库生效；`miniProgramWechatEnabled=true` 仍返回小程序完整提示。
3. 支付回归：已配 default 商户的门店，收银线上微信（组合支付）与小程序微信支付不受影响；未配商户发起线上微信支付时 createPrepay 仍返回明确错误。

## 7. 交付说明

- 覆盖：收银端微信开关校验删除；小程序端校验保留；线上支付发起兜底保留。
- 未覆盖：线下收款渠道（offline_collect）本身的行为（不受本次改动影响）；支付商户配置 CRUD。
- 行为差异集中在：未配 default 商户时收银微信开关可开启；真实线上微信支付仍受商户配置约束。
