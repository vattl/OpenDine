# D014 支付配置模块重构方案（渠道化架构）



* 日期：2026-09-08

* 状态：**IMPLEMENTED（P1 内部就绪 + P2 新增键上线 + P3 口径同步完成；P4 legacy 清理待排期）**

* 风险等级：HIGH（涉及表结构、接口契约、前端依赖；需分阶段渐进）

* 类型：架构重构方案

## 0. 实施记录（2026-09-08）

- **P1**：迁移脚本 `docs/db_migration_payment_channel_qr_alipay.sql`（`t_payment_capability` +3 列 `cashier_wechat_qr_enabled`/`cashier_alipay_qr_enabled`/`mini_program_alipay_enabled`，按 `offline_collect_channels` 逗号串回填）；`db_diancan.sql` 建表同步；`PaymentCapabilityEntity` +3 字段。
- **P2**：`PaymentCapabilityService`——`ResolvedCapability` +3 状态；`resolve()` 解析（新列 NULL 时回退 `offline_collect_channels` 推导，兼容未迁移库）；对外新增键 `clients.cashier.wechat_qr`/`alipay_qr`、`clients.miniProgram.channels/effectiveChannels.alipay`；`upsert` 支持写入（`cashierWechatQrEnabled`/`cashierAlipayQrEnabled`/`miniProgramAlipayEnabled` 或 nested 键），收款码写入时**双写** `offline_collect_channels` 保持兼容；收款码/小程序支付宝**无商户就绪门控**（个人码+webhook 模式）。
- **P3**：openapi v1.2.229（changelog + GET/PUT 描述；v1.2.229 避免与外部并行提交 d8f04b1「精简支付能力响应」占用的 v1.2.228/D014 撞号）。
- **与外部 d8f04b1 合并说明**：外部并行提交（同工作区）在 D013 后删除了 7 个冗余字段（`canEnableWechatPay`/`canEnableOnlinePay`/`offlineCollect.tempQrcodeApi`/`configuredEnabled`/`configuredChannels`×2 端）并标注为「D014」。本方案**保留外部删除**（仅新增键），编号文档沿用本文件名 D014-payment-channel-rearchitecture.md；openapi 另修复外部 v1.2.228 changelog 条目缩进 bug（0 空格→4 空格）。
- **P4（待排期）**：legacy 总开关列/兼容代码清理（仅删实现不删键名契约）；`offline_collect_channels` 双写观察一个周期后降级为只读。

## 1. 需求理解（重述）

支付配置按**终端**拆分，每终端**每个渠道独立开关**：



| 终端               | 渠道清单                                       |
| ---------------- | ------------------------------------------ |
| 收银端 cashier      | 微信支付、支付宝支付、余额支付、组合支付、**微信收款码、支付宝收款码**（6 个） |
| 小程序端 miniProgram | 微信支付、**支付宝支付**、余额支付（3 个）                   |

核心约束：



1. 渠道开关**互相独立**（开微信不影响支付宝；开收款码不影响线上支付）

2. 收银端收款码拆为**微信码 / 支付宝码两个独立开关**（现状是 `offline_collect_channels` 一个开关 + 逗号串）

3. 小程序端**新增支付宝支付**（现状完全没有）

4. 现状 legacy 线上总开关（`online/wechat/alipay/balance/combined_enabled`）不再作为主模型

## 2. 现状 vs 需求差距矩阵



| 需求渠道         | 现状字段 / 实现                                         | 差距        | 改造动作      |
| ------------ | ------------------------------------------------- | --------- | --------- |
| 收银 - 微信支付    | `cashier_wechat_enabled`（JSAPI / 个人码，宽松 ready 门控） | 无         | 保留，归入渠道模型 |
| 收银 - 支付宝支付   | `cashier_alipay_enabled`（个人码 + webhook 确认）        | 无         | 保留，归入渠道模型 |
| 收银 - 余额支付    | `cashier_balance_enabled`                         | 无         | 保留        |
| 收银 - 组合支付    | `cashier_combined_enabled`（≥2 基础渠道）               | 无         | 保留        |
| 收银 - 微信收款码   | `offline_collect_channels` 含 `wechat`             | **开关未独立** | 拆为独立开关    |
| 收银 - 支付宝收款码  | `offline_collect_channels` 含 `alipay`             | **开关未独立** | 拆为独立开关    |
| 小程序 - 微信支付   | `mini_program_wechat_enabled`（严格 ready 门控）        | 无         | 保留        |
| 小程序 - 支付宝支付  | **不存在**                                           | **缺失**    | 新增渠道      |
| 小程序 - 余额支付   | `mini_program_balance_enabled`                    | 无         | 保留        |
| legacy 线上总开关 | `online/wechat/alipay/balance/combined_enabled`   | 冗余 / 口径混乱 | 兼容映射后弃用   |

## 3. 目标架构

### 3.1 渠道统一模型



```
terminal ∈ { cashier, miniProgram }

channel  ∈ { wechat\_pay, alipay\_pay, balance\_pay, combined\_pay, wechat\_qr, alipay\_qr }
```

每个渠道统一状态（对外、对内一致）：

`{ enabled(配置开关), effective(实际可用), ready(就绪), readyHint, missingFields }`

### 3.2 数据模型（推荐：平铺列扩展）

`t_payment_capability` 新增 3 列：



| 新列                            | 语义              | 来源                             |
| ----------------------------- | --------------- | ------------------------------ |
| `cashier_wechat_qr_enabled`   | 收银 - 微信收款码独立开关  | 拆分自 `offline_collect_channels` |
| `cashier_alipay_qr_enabled`   | 收银 - 支付宝收款码独立开关 | 拆分自 `offline_collect_channels` |
| `mini_program_alipay_enabled` | 小程序 - 支付宝支付开关   | 新增                             |



* `offline_collect_enabled`/`offline_collect_channels` 保留为**兼容只读**（迁移脚本把旧值拆入新列后，新代码不再写）

* legacy 总开关列保留映射，不物理删（迁移窗口后由 DBA 清理）

* 理由：与 MyBatis-Plus 实体直映、缓存（`PaymentConfigCache`）与解析（`ResolvedCapability`）改动最小；可渐进上线

> 备选：二维渠道表 
>
> `t_payment_channel_switch(shop_id, terminal, channel, enabled)`
>
> —— 更规范但 service / 缓存 / API 全量重写，风险高，不推荐本次采用。

### 3.3 门控规则（统一 per 渠道）



| 渠道                        | 就绪条件                                               | effective 公式         |
| ------------------------- | -------------------------------------------------- | -------------------- |
| `wechat_pay`              | 收银 = 宽松（default 商户行存在）；小程序 = 严格（+8 字段齐全）           | `enabled && ready`   |
| `alipay_pay`              | 无（个人码 + webhook 共享密钥）                              | `enabled`            |
| `balance_pay`             | 无（储值余额）                                            | `enabled`            |
| `combined_pay`            | ≥2 个基础支付渠道（wechat/alipay/balance 中 effective 数 ≥2） | `enabled && count≥2` |
| `wechat_qr` / `alipay_qr` | 无（个人码）                                             | `enabled`            |

终端总开关语义：保留 `cashier_pay_enabled`/`mini_program_pay_enabled` 作为**终端级总闸**（任一渠道 effective 需先过总闸）——"渠道独立开关" 指渠道间互不联动，总闸作为整端快捷控制保留（见决策点 D4）。

### 3.4 对外 API（字段兼容原则：沿用现有键名，只增不改）

**硬约束（本次修订）**：现有键名 / 键类型 / 位置一概不变；新能力一律以**新增键**表达；内部渠道枚举仅内部使用，序列化时映射回现有短键。前端现有读取不失效。

现有结构全部保留（`clients.*.channels/effectiveChannels` 两层、`wechatMerchantReady/wechatReadyHint/wechatMissingFields`、顶层 `channels.*`、`offlineCollect` 节点；`configuredChannels/configuredEnabled` 兼容别名已由外部提交 d8f04b1 随精简响应移除，不在本方案恢复）。仅新增：



```
{

&#x20; "clients": {

&#x20;   "cashier": {

&#x20;     "enabled": true, "effectiveEnabled": true, "configuredEnabled": true,          // 不变

&#x20;     "configuredChannels": { "wechat": true, "alipay": true, "balance": true, "combined": true },  // 不变

&#x20;     "channels":            { "wechat": true, "alipay": true, "balance": true, "combined": true },  // 不变

&#x20;     "effectiveChannels":   { "wechat": true, "alipay": true, "balance": true, "combined": true },  // 不变

&#x20;     "wechatMerchantReady": false, "wechatReadyHint": "",                          // 不变（D013）

&#x20;     "wechat\_qr": true, "alipay\_qr": true                                          // 新增：收款码独立开关

&#x20;   },

&#x20;   "miniProgram": {

&#x20;     "enabled": true, "effectiveEnabled": true, "configuredEnabled": true,          // 不变

&#x20;     "configuredChannels": { "wechat": true, "balance": true },                    // 不变

&#x20;     "channels":            { "wechat": true, "balance": true },                   // 不变

&#x20;     "effectiveChannels":   { "wechat": true, "balance": true },                   // 不变

&#x20;     "wechatMerchantReady": false, "wechatMissingFields": \[ ... ],                 // 不变

&#x20;     "alipay": true                                                                // 新增：小程序支付宝开关

&#x20;   }

&#x20; },

&#x20; "channels": {

&#x20;   "wechat": { "enabled": true }, "alipay": { "enabled": true },                   // 不变（legacy）

&#x20;   "balance": { "enabled": true }, "combined": { "enabled": true },                // 不变（legacy）

&#x20;   "offlineCollect": { "enabled": true, "modes": \["wechat"], "tempQrcodeApi": "/pay/offline-collect/temp-qrcode" }  // 不变

&#x20; }

}
```

说明：



* **收银收款码独立开关**：新增 `clients.cashier.wechat_qr` / `clients.cashier.alipay_qr`（布尔，DB 对应 `cashier_wechat_qr_enabled`/`cashier_alipay_qr_enabled`）；顶层 `channels.offlineCollect` 结构与位置**不动**，`modes` 数组继续承载配置回显，新增键与之保持映射一致

* **小程序支付宝**：新增 `clients.miniProgram.channels.alipay`（布尔，DB 对应 `mini_program_alipay_enabled`）；`wechat/balance` 及现有结构不动

* `channels/effectiveChannels` 两层 **不改为对象结构**（现状布尔值继续布尔）；新渠道同步加入两层（仅新增键）

* legacy 顶层 `channels.*` 保留至 P4，期间与 `clients.*` 口径映射关系文档化（同 D013 已做）

### 3.5 内部重构



* `PaymentChannelCatalog`：渠道枚举扩展（`WECHAT_PAY/ALIPAY_PAY/BALANCE_PAY/COMBINED_PAY/WECHAT_QR/ALIPAY_QR`）

* `ResolvedCapability`：按 terminal×channel 统一字段（替代现有 cashierWechatEnabledConfigured 等散字段）

* `PaymentCapabilityService`：`resolve()` 输出统一渠道状态；`upsert()` 按渠道开关独立写，校验规则表驱动

* 支付发起校验（`CashierCheckoutService.validateCombinedCapabilities` / `PaymentChannelOpsService`）改读新渠道模型

## 4. 迁移与分阶段



| 阶段           | 内容                                                                                                                                   | 兼容性           |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------ | ------------- |
| **P1 内部就绪**  | DB +3 列（迁移脚本）；实体 / 解析 / 缓存扩展；内部渠道枚举与状态计算；**对外输出不变**                                                                                  | 无破坏           |
| **P2 新增键上线** | 对外新增键（`clients.cashier.wechat_qr/alipay_qr`、`clients.miniProgram.channels.alipay`）；upsert 新渠道独立写；`offline_collect_channels` 迁移脚本回填新列 | 前端现有读取零失效     |
| **P3 口径校验**  | openapi 同步新键与口径说明；前端按需消费新键；两层 /legacy 字段保持                                                                                           | 无结构切换，前端无强制改动 |
| **P4 清理**    | legacy 总开关列 / 兼容代码下线（仅清理，不改键名）；openapi 移除 deprecated 标记                                                                              | 数据迁移回填完成      |

## 5. 风险



1. **前端契约**：本次修订后**所有现有键名 / 类型 / 位置不变**，前端现有读取零失效；新能力为纯新增键，前端按需消费，无需强制联调

2. **支付宝小程序支付**：现状无支付宝商户 SDK（个人码 + webhook）。小程序端支付宝支付若沿用个人码模式，产品语义需确认（用户在小程序里扫码 / 跳转个人码？）；若需真实支付宝小程序支付需**引入 alipay SDK + 商户配置**，工作量显著（见决策点 D3）

3. **迁移一致性**：`offline_collect_channels` 拆分需在发版窗口执行，避免双写期间读旧值

4. **缓存**：新列进入 `PaymentConfigCache`，改列后需 `clearAll` 或按版本失效

## 6. 决策点（需确认）



* **D1 数据模型**：平铺列扩展（推荐）vs 二维渠道表

* **D2 收银 UI 语义**：收银端 "微信支付" 与 "微信收款码" 是否为两个独立入口（现收银台收款即个人码；JSAPI 微信支付主要用于顾客自助 / 线上）

* **D3 小程序支付宝支付实现**：A) 沿用个人码 + webhook（快，但小程序内体验 = 跳个人码）；B) 引入支付宝商户 SDK（真实小程序支付，需商户资质与证书，工作量大）

* **D4 终端总开关**：保留 `cashier_pay_enabled/mini_program_pay_enabled` 作为总闸（推荐）vs 纯渠道开关无总闸

* **D5 兼容期**：键名沿用后无前端强制失效，兼容压力低；legacy 字段保留至 P4（清理仅删实现不删键名契约，如有旧前端仍在读则无限期保留映射）

## 7. 交付物（确认后）

确认本方案后按 P1→P4 落地，产出：迁移脚本、实体 / Service/Controller 改动、openapi 同步、D014 实施文档；每阶段独立提交可回滚。