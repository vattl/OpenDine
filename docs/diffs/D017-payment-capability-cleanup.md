# D017 支付能力：C 端响应精简 + PUT 写入无兼容

* 日期：2026-09-08
* 状态：**IMPLEMENTED**
* 类型：接口契约变更（GET 精简 + PUT 收口）
* 关联：D013（就绪口径）、D014（渠道化）、D015（channelStates）、D016（写入兼容收窄后被本版取代）

## 0. 决策（用户原话）

> 搞错了，写入配置能力使用最新的，不需要兼容写入；/config/payment-capabilities 获取配置才需要简化返回内容，移除兼容返回，只保留 wechatMerchantReady，channels 和 onlinePayEnabled。

即：
1. **PUT /admin/payment/capabilities**：用最新模型（channelStates），**无任何兼容写入**（取代 D016 初版与收窄版，二者均作废）。
2. **GET /config/payment-capabilities（C 端）**：精简返回、移除兼容返回，**兼容字段仅保留 `wechatMerchantReady`、`channels`、`onlinePayEnabled`**。
3. **GET /admin/payment/capabilities（B 端）**：保留全量字段。

## 1. 实施

### 1.1 C 端 `toPublicMap` 精简

顶层保留：`shopId`、`wechatMerchantReady`（宽松）、`onlinePayEnabled`（= miniProgram.enabled）、`disabledMessage`、`channels`（legacy 结构）、`clients`、`nineFold`。

**不再返回**：
- 顶层：`miniProgramWechatMerchantReady`、`miniProgramWechatMissingFields`、`canEnableMiniProgramWechatPay`、`canEnableCashierWechatPay`、`wechatPayEnableHint`、`globalOnlinePayEnabled`
- `clients.cashier`：`effectiveEnabled`、`effectiveChannels`、`wechatReadyHint`、`wechat_qr`、`alipay_qr`（→ `channelStates.wechat_qr/alipay_qr` 承载）
- `clients.miniProgram`：`effectiveEnabled`、`effectiveChannels`、`wechatMissingFields`

可用性判断统一：`clients.*.channelStates.<渠道>.available`（+ `hint` 原因）。

### 1.2 B 端 `toAdminMap` 保留全量

在精简版 `toPublicMap` 基础上补回：`miniProgramWechatMerchantReady`、`miniProgramWechatMissingFields`、`canEnableMiniProgramWechatPay`、`canEnableCashierWechatPay`、`wechatPayEnableHint`、`globalOnlinePayEnabled`，且 `clients` 用 `clientCapabilities(cap, true)` 全量版覆盖（补 `effectiveEnabled/effectiveChannels/wechatReadyHint/wechat_qr/alipay_qr/wechatMissingFields`）。

### 1.3 PUT 写入无兼容（取代 D016）

`upsert`：body 仅接受 `clients.*.enabled`、`clients.*.channelStates.<渠道>.enabled`、`disabledMessage`；全部旧平铺键（含 `onlinePayEnabled`）与 `clients.*.channels.*` 不再处理。`readState`/`requestedChannel` 只读 `channelStates`。收款码双写 `offline_collect_channels` 保留（DB 一致）。

### 1.4 openapi v1.2.233

- changelog 顶部 + version
- GET /config 描述：clients 两段（channelStates 为可用性来源）、effective 段替换为 D017 说明、尾注列出不再返回字段
- PUT 描述：D012 行收口 channelStates、D015 行去并存、D016/D017 行改为"写入无兼容"
- PUT schema：删除 `onlinePayEnabled`；两处 `channels` 标注只读；保留 `clients.*.enabled` + `channelStates` + `disabledMessage`

## 2. 校验

- 编译 exit 0；`clientCapabilities(r, admin)` 双分支核查通过；`toAdminMap` 补字段齐全
- GET /config 响应无独立 schema（仅描述），描述已同步

## 3. 风险与说明

- **C 端前端**：若仍读取 `effectiveEnabled/effectiveChannels` 等已移除字段会取到 undefined——需切换 `channelStates.<渠道>.available`；顶层 `wechatMerchantReady/channels/onlinePayEnabled` 保留不受影响
- **B 端前端**：字段无变化
- 提交：Service + openapi + 本文档；openapi 与并行未提交的 v1.2.231 会员看板条目同文件（暂留工作区，待该线完成后一并提交）
