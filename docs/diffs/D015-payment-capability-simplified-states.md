# D015 支付能力响应简化 ——「开关 + 可用性」模型



* 日期：2026-09-08

* 状态：**IMPLEMENTED（channelStates 输出 + PUT 开启校验收紧 + openapi v1.2.230；用户已确认决策 A 硬校验）**

* 类型：接口契约优化（新增键兼容，无表结构变更）

* 关联：D013（就绪口径）、D014（渠道化：收款码独立开关 + 小程序支付宝）

## 0. 实施记录（2026-09-08）

- `PaymentCapabilityService`：
  - `ResolvedCapability` +2 字段（`combinedAvailable`、`miniProgramWechatAvailable`）；`resolve()` 计算（收银基础渠道 ≥2；小程序微信=严格就绪）
  - `clientCapabilities` 新增 `clients.cashier.channelStates`（6 渠道）/ `clients.miniProgram.channelStates`（3 渠道），每项 `{enabled, available, hint}`；`hint` 复用 `miniProgramWechatEnableHint`（缺字段文案）
  - `upsert`：新增收银组合开启校验（请求后基础渠道 <2 → 拒绝，可读信息）；`applyCashierSettings/applyMiniProgramSettings` 支持 `channelStates.*.enabled` 写入（`mergeChannelStates`，channelStates 优先于 channels/legacy）
- 行为变化（决策 A）：请求开启的渠道 `available=false`（组合不足 / 小程序微信商户不齐）→ **拒绝保存**；已保存渠道条件变化失效不自动回滚，仅 `available=false` + `hint`
- openapi v1.2.230：changelog + GET/PUT 描述 + PUT schema（cashier/miniProgram channelStates）
- 兼容：既有键全部保留（前端零失效）；`channelStates.enabled` 与现有 `channels.*` 同源

### 0.1 D016 实施记录（写入兼容收窄，同日）

用户确认"接口返回可用，移除写入兼容"，随后补充"**保留 wechatMerchantReady，channels 和 onlinePayEnabled**"——`PUT /admin/payment/capabilities` 写入模型收窄（保留项、移除项）：

- `upsert`：删除大部分旧平铺键处理（`wechatEnabled`/`alipayEnabled`/`balanceEnabled`/`combinedEnabled`/`offlineCollectEnabled`/`offlineCollectChannels`/`cashier*Enabled`/`miniProgram*Enabled` 等，请求携带即忽略）；**保留** `onlinePayEnabled`（历史总开关别名，写 `online_pay_enabled` + `mini_program_pay_enabled`）与 `clients.*.channels.*`（嵌套布尔）写入
- `applyClientSettings`：移除平铺键 apply；`applyCashierSettings/applyMiniProgramSettings` 从 `channelStates` 读取（优先）、`channels` 回退（helper `readState(channels, states, key, current)`，兼容值直接布尔或 `{enabled}`）
- 收款码双写保留（DB 一致性）：`channelStates.wechat_qr/alipay_qr` 或 `channels.wechat_qr/alipay_qr` 写入时同步重建 `offline_collect_channels`
- 删除旧兼容方法：`wantsEnableCashierWechat`/`wantsEnableMiniProgramWechat`/`requestedTerminalWechat`/`mergeChannelStates`/`readChannel`；校验改用 `requestedChannel(body, terminalKey, channelKey)`（channelStates 优先、channels 回退）
- GET 响应既有字段**全部保留**（含 `wechatMerchantReady`、`channels`、`onlinePayEnabled`，前端零失效）；openapi v1.2.232（PUT 描述/schema 同步；changelog 顶部）
- 提交：`a170c05`（D015）+ `4be3a40`（D016 初版）+ 收窄修订提交（Service + 文档；openapi 因含并行未提交的 v1.2.231 会员看板条目暂留工作区）

## 1. 需求理解（用户原话 + 确认项）

用户反馈当前 `GET /config/payment-capabilities` 返回过于复杂（三层状态 + 就绪 + 兼容组），目标：

> 前端设置开关，后端直接响应是否可用即可，不能用就不给开，不需要什么 "实际可用"。

已确认决策：



1. **总开关保留**：`clients.*.enabled`（终端总闸）继续保留。

2. **组合支付**：`combined` 至少 2 个基础渠道生效才可用（`available` 随基础渠道动态变化）。

3. **过渡方式**：**兼容之前的字段**—— 既有键名 / 结构全部保留，简化模型以**新增键** `channelStates` 提供；不做破坏性删除。

4. **nineFold 九折**：与开关无关，保留在响应中不动。

## 2. 核心变化

### 2.1 新增键 `clients.*.channelStates`（简化模型）

每个终端新增 `channelStates` 对象，每渠道一个 `{ enabled, available, hint }`：



```
{

&#x20; "code": 0,

&#x20; "shopId": 1,

&#x20; "clients": {

&#x20;   "cashier": {

&#x20;     "enabled": true,

&#x20;     "channelStates": {

&#x20;       "wechat":    { "enabled": true,  "available": true,  "hint": "" },

&#x20;       "alipay":    { "enabled": true,  "available": true,  "hint": "" },

&#x20;       "balance":   { "enabled": true,  "available": true,  "hint": "" },

&#x20;       "combined":  { "enabled": true,  "available": true,  "hint": "" },

&#x20;       "wechat\_qr": { "enabled": true,  "available": true,  "hint": "" },

&#x20;       "alipay\_qr": { "enabled": true,  "available": true,  "hint": "" }

&#x20;     }

&#x20;   },

&#x20;   "miniProgram": {

&#x20;     "enabled": true,

&#x20;     "channelStates": {

&#x20;       "wechat":  { "enabled": true,  "available": true,  "hint": "" },

&#x20;       "alipay":  { "enabled": false, "available": true,  "hint": "" },

&#x20;       "balance": { "enabled": true,  "available": true,  "hint": "" }

&#x20;     }

&#x20;   }

&#x20; }

}
```

语义：



* `enabled`：**保存的开关值**（= 现有 `channels.*` 布尔，同一数据源）

* `available`：**后端计算的可用性**——`false` 表示该渠道当前不具备开启条件（配置了也没法真实用）

* `hint`：`available=false` 时的原因文案（用户可读引导），可用时为空串

前端新逻辑：读 `enabled` 回显、读 `available` 决定开关是否可操作、`hint` 展示原因；**不再自行计算 effective**。

### 2.2 `available` 计算矩阵（每终端 × 每渠道）



| 终端          | 渠道                      | available 条件                                                                        |
| ----------- | ----------------------- | ----------------------------------------------------------------------------------- |
| cashier     | wechat                  | `true`（恒可用：D012 起收银微信可独立开启，可走收款码；真实 JSAPI 下单由 `WechatJsapiChannel.createPrepay` 兜底） |
| cashier     | alipay / balance        | `true`                                                                              |
| cashier     | wechat\_qr / alipay\_qr | `true`（个人码，无商户门槛）                                                                   |
| cashier     | combined                | ≥ 2 个基础渠道（wechat/alipay/balance）`enabled` 且 `available`                             |
| miniProgram | wechat                  | 严格就绪（default 商户启用 + 9 字段齐全）                                                         |
| miniProgram | alipay / balance        | `true`                                                                              |

`hint` 示例：小程序微信 `available=false` → `"请先配置微信支付商户：缺 AppID、商户号、…"`（复用 `PaymentMerchantReadiness.missingFields` 生成）；组合不足 → `"组合支付需至少 2 个基础渠道生效"`。

### 2.3 PUT 行为收紧（不能用就不给开）

`PUT /admin/payment/capabilities` 对**请求中尝试开启（本次置 true）的渠道**做硬校验：



* 该渠道 `available=false` → **拒绝保存**，返回错误（`code=4020` 系列 + 可读 `msg`），已保存开关值不变

* 关闭渠道、或请求中未涉及的渠道：不校验，照常保存

* 兼容期：旧键（`clients.*.channels.wechat` 等布尔）与新键（`channelStates.*.enabled`）都触发同一校验；二者同时提交以 `channelStates` 为最终值

已知行为变化：此前 "开了但实际无效"（如小程序微信未配商户也能存 true）不再允许；校验仅在**开启动作**生效，已保存的有效渠道因后续条件变化失效（如基础渠道关闭导致 combined 不可用）**不自动回滚**，仅 `available` 变 `false` + `hint` 提示。

## 3. 兼容策略



* **GET**：既有键全部原样返回（`enabled/effectiveEnabled/channels/effectiveChannels/wechatMerchantReady/wechatReadyHint/wechat_qr/alipay_qr`、顶层 `channels.*`/`onlinePayEnabled`/`globalOnlinePayEnabled`/ 就绪字段、`nineFold`）；仅新增 `clients.*.channelStates`。

* **PUT**：既有键全部继续接受（行为 = 现状 + 可用性硬校验）；新增 `channelStates` 写法。

* 旧前端（读布尔 `channels.*`/`effectiveChannels`）：零失效。

* 新前端（读 `channelStates`）：不再需要 effective 概念。

* 版本：openapi 升 `v1.2.230`（changelog 注明简化模型新增、PUT 校验收紧；落地时若外部已占用则顺延）。

## 4. 实现范围（代码级）



| 文件                                                    | 改动                                                                                                                                                                                          |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PaymentCapabilityService.java`                       | `ResolvedCapability` 增加各渠道 available/hint 计算（复用现有就绪数据）；`clientCapabilities` 增加 `channelStates` 输出（cashier 6 键 /miniProgram 3 键）；`upsert` 增加 `channelStates` 读取 + 开启校验（`available=false` 拒绝） |
| `PaymentMerchantReadiness.java`                       | 复用 `missingFields`/`ENABLE_MINI_PROGRAM_WECHAT_PAY_HINT` 生成 miniProgram.wechat 的 hint                                                                                                       |
| `CashierCheckoutService` / `PaymentChannelOpsService` | **不变**（运行时校验已存在；`available` 仅是前端预判，付款仍以服务端为准）                                                                                                                                               |
| `docs/openapi.yaml`                                   | v1.2.230：GET 响应描述 + PUT 描述 /requestBody schema（channelStates 新键 + 校验规则说明）                                                                                                                   |
| `docs/diffs/D015-*.md`                                | 本方案 → IMPLEMENTED 记录                                                                                                                                                                        |

无表结构变更（`available` 全部为运行时计算，数据源为现有 22 列 + 商户配置就绪）。

## 5. 风险与边界



1. **PUT 校验收紧**是行为变更：旧前端 "先开开关后补商户" 的操作顺序将失败 —— 需在 `hint`/ 错误 `msg` 中给出明确引导（提示先配商户）。若该操作流仍必需，可降级为 "允许保存 + available=false"（放弃硬校验）——**需用户确认**。

2. 组合支付循环约束：基础渠道不足时 `combined` 不可开；用户已确认该行为。

3. `channelStates` 与 `channels/effectiveChannels` 并存期间需保证口径一致（同一数据源推导，无二次计算漂移）。

4. 外部并行提交可能占用版本号（D014 曾撞号 v1.2.228）—— 落地时先查 changelog 最新版本。

## 6. 交付物（确认后）



1. `PaymentCapabilityService`：channelStates 输出 + PUT 校验（单提交）

2. openapi v1.2.230 同步 + 描述

3. D015 文档 IMPLEMENTED

4. 编译 + 提交 +（按需）构建 jar