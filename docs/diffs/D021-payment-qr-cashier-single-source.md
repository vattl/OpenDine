# D021 收款码开关统一归收银端 cashier（废弃 offline_collect_channels 双写）

* 日期：2026-09-08
* 状态：**IMPLEMENTED**
* 类型：支付配置契约收敛（单一来源）
* 关联：D014（收款码独立开关+双写）、D020 修复（总闸联动）、D017（写入无兼容）

## 0. 决策（用户原话）

> 不要 offline_collect_channels，收款码开关统一归收银端 cashier。

收款码开关（`wechat_qr` / `alipay_qr`）**唯一来源 = 收银端 cashier 独立列**（`cashier_wechat_qr_enabled` / `cashier_alipay_qr_enabled`），废弃 `offline_collect_channels` / `offline_collect_enabled` 两列的双写、回退与读取机制（列保留不删，逻辑弃用）。

## 1. 变更

### 1.1 读取（PaymentCapabilityService.resolve）
- `cashierWechatQrEnabled` / `cashierAlipayQrEnabled`：**只用列**，移除 `offlineCollectChannels.contains(...)` 回退（列 null 视为 false）
- legacy `offlineCollectEnabled` / `offlineCollectChannels` 改为**派生**：`enabled`=任一收款码开启；`modes`=开启的收款码集合（不再读 `offline_collect_enabled`/`offline_collect_channels` 列）
- `resolveChannels` 方法删除（唯一引用消失）；`parseChannelList`/`serializeChannels` 保留

### 1.2 写入（applyCashierSettings）
- `qrTouched` 块只写 `cashier_wechat_qr_enabled` / `cashier_alipay_qr_enabled`；**不再双写** `offline_collect_channels`，也**不再联动** `offline_collect_enabled`（D020 修复的总闸联动由派生取代，两列完全弃写）

### 1.3 可用性（offlineWechatEnabled / offlineAlipayEnabled）
- 直接返回 `r.cashierWechatQrEnabled` / `r.cashierAlipayQrEnabled`
- 运行时判定早已归 cashier（PaymentCapabilityMatcher 自 v1.2.178 起用收银端渠道判定出码/结账，与本变更一致）

### 1.4 测试（PaymentCapabilityServiceClientTest）
- 同步 8 个过时测试：upsert 旧格式（`clients.*.channels.*` / 平铺键）→ channelStates 格式；C 端 `effectiveEnabled/effectiveChannels` 断言 → channelStates.available / 移除（D017 精简）
- **注**：这些失败是 D015–D017 演进后未同步的遗留，非 D021 引入

### 1.5 openapi
- PUT 描述：D014 行去掉"同步回写 offline_collect_channels"；新增 D021 行（单一来源 + 派生展示 + 列弃用）

## 2. 行为对照

| 场景 | D021 前 | D021 后 |
|---|---|---|
| 请求 `wechat_qr.enabled=true` | 写 qr 列 + 双写 channels 列 + 联动总闸列 | 只写 qr 列；响应 `offlineCollect.enabled/modes` 派生为 true/[wechat] |
| 历史门店 `offline_collect_enabled=0` | 响应 `offlineCollect.enabled=false`（bug） | 派生自收款码，不受旧列影响 |
| 读取 `cashier_wechat_qr_enabled` 列 null | 回退 offline_collect_channels | false（列即权威） |

## 3. 校验

- `mvnw test -Dtest=PaymentCapabilityServiceClientTest`：**13/13 通过**（含更新后的 8 个）
- openapi 2/2 更新

## 4. 风险与说明

- 列 `offline_collect_channels` / `offline_collect_enabled` 保留不删（避免破坏性迁移）；如需清理可 DROP，但需确认无其他系统读取
- 存量门店若 qr 列被 D014 迁移回填过（FIND_IN_SET），语义与旧配置一致；未回填的 null 视为关闭
- openapi 改动与工作区并行线（v1.2.234 D018 等）共存，未提交
