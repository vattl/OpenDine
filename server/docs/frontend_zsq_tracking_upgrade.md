# 真省钱配送追踪前端改造说明

## 1. 改造范围

以下两个接口返回结构一致，本次均新增 `tracking.effectiveState`：

- 运营后台：`GET /admin/takeout/delivery/tracking?orderId={orderId}`
- 小程序：`GET /order/takeout/order/tracking?openid={openid}&order_no={orderNo}`

本次修复的核心是：一个真省钱订单可能先取消某个配送批次，再沿用同一订单重新叫骑手；同时 `deliveryTimeline` 会包含多个运力渠道，其中某个渠道取消并不表示整单取消。最终配送状态必须由后端按“当前配送批次”统一解析，前端不再解析原始轨迹判断状态。

## 2. 最终状态读取规则

前端按以下优先级读取：

```ts
const tracking = response.tracking
const phase = tracking?.effectiveState?.phase ?? tracking?.phase ?? 'UNKNOWN'
const statusText = tracking?.effectiveState?.statusDesc
  ?? tracking?.deliverySendStatusDesc
  ?? '状态同步中'
```

`effectiveState.phase` 映射：

| phase | 展示文案 | 页面行为 |
| --- | --- | --- |
| `WAITING_RIDER` | 等待骑手接单 | 展示等待态，不显示虚构骑手位置 |
| `TO_SHOP` | 骑手取货中 | 有有效骑手坐标时展示骑手到商家路线 |
| `TO_USER` | 配送中 | 有有效骑手坐标时展示骑手到用户路线 |
| `DELIVERED` | 已送达 | 停止高频轮询，可保留历史轨迹入口 |
| `CANCELLED` | 配送已取消 | 展示当前批次取消原因，并允许商家重新叫骑手 |
| `ORDER_MISSING` | 配送订单不存在 | 运营端提示重新发配送；小程序提示联系商家 |
| `UNKNOWN` | 状态同步中 | 保持低频刷新，不自行猜测状态 |

## 3. 禁止继续使用的判断方式

前端必须删除下列逻辑：

- 用 `deliveryTimeline[0]` 判断整单状态；
- 在 `deliveryTimeline` 中取全局最大 `sortNum` 判断整单状态；
- 只要任意渠道出现 `sendStatus=60` 就显示“配送取消”；
- 在全部 `orderLogs` 中发现“取消原因”或“异常单”就覆盖当前状态；
- 用本地缓存的 `dispatchStatus=cancelled` 永久压过接口最新状态。

`deliveryTimeline` 和 `orderLogs` 现在只用于“历史记录/问题排查”展示。它们会保留旧配送批次和未选中运力渠道的取消记录，这是正常数据。

## 4. TypeScript 数据结构

```ts
type ZsqPhase =
  | 'WAITING_RIDER'
  | 'TO_SHOP'
  | 'TO_USER'
  | 'DELIVERED'
  | 'CANCELLED'
  | 'ORDER_MISSING'
  | 'UNKNOWN'

interface ZsqEffectiveState {
  sendStatus: number | null
  statusDesc: string | null
  phase: ZsqPhase
  source: 'ORDER_LOG' | 'ORDER_DETAIL'
  effectiveLogId: number | null
  parentOrderNo: string | null
  thirdPartyOrderNo: string | null
  updatedAt: string | null
}

interface ZsqTracking {
  effectiveState?: ZsqEffectiveState
  phase?: ZsqPhase // 兼容旧字段
  coordinateType: 'gcj02'
  rider?: {
    name?: string | null
    phone?: string | null
    lat?: number | null
    lng?: number | null
    locationLogId?: number | null
    locationUpdatedAt?: string | null
  }
  trajectoryState?: {
    callbackStatus?: string | null
    orderStatus?: string | null
    previousOrderStatus?: string | null
    deliveryStatus?: string | null
    cancelReason?: string | null
  }
  deliveryTimeline?: Record<string, unknown>[]
  orderLogs?: Record<string, unknown>[]
}
```

## 5. 骑手定位与取消原因

只有满足以下条件才在地图展示骑手点位：

```ts
const active = ['TO_SHOP', 'TO_USER'].includes(phase)
const rider = tracking?.rider
const hasRiderLocation = active
  && Number.isFinite(rider?.lat)
  && Number.isFinite(rider?.lng)
```

- 接口业务坐标统一为 `coordinateType=gcj02`，直接用于腾讯/微信地图；前端不得再次做百度或高德坐标转换。
- `WAITING_RIDER` 时即便缓存里有旧骑手点位，也必须隐藏。
- 取消原因只在 `effectiveState.phase === 'CANCELLED'` 时展示：

```ts
const cancelReason = phase === 'CANCELLED'
  ? tracking?.trajectoryState?.cancelReason
  : null
```

## 6. 订单不存在与重新发配送

运营接口识别到真省钱订单已删除/不存在时返回：

```json
{
  "code": 4091,
  "msg": "配送订单不存在或已删除，可重新发起配送",
  "canRedispatch": true,
  "redispatchUrl": "/admin/takeout/delivery/zsq/redispatch",
  "missingOpenOrderId": 54384514
}
```

运营前端收到 `code=4091 && canRedispatch=true` 时显示“重新叫骑手”按钮，不要把它当成通用网络错误。小程序接口同状态返回 `requiresMerchantRedispatch=true`，应提示“配送订单异常，请联系商家处理”。

## 7. 刷新建议

- `WAITING_RIDER`、`TO_SHOP`、`TO_USER`：页面可见时每 10–15 秒刷新一次；收到 `takeout_dispatch_changed` 后立即刷新。
- `DELIVERED`、`CANCELLED`、`ORDER_MISSING`：停止高频轮询。
- 每次接口成功后以整个 `tracking` 对象替换旧状态，不要将旧 `trajectoryState.cancelReason`、旧骑手坐标与新响应做字段级合并。

## 8. 本次问题的验收数据

对真省钱订单 `54384514`，即使历史轨迹中存在 23:45:47 的“超时未接单/取消”，最新 23:45:48 已重新配送，23:54:37 为取货中，因此应展示：

```json
{
  "sendStatus": 30,
  "statusDesc": "取货中",
  "phase": "TO_SHOP",
  "source": "ORDER_LOG",
  "effectiveLogId": 842232935031685,
  "parentOrderNo": "JH842230763496325",
  "thirdPartyOrderNo": "3749203565953626113",
  "updatedAt": "2026-08-26 23:54:37"
}
```

验收时还需覆盖：同一订单取消后重叫骑手、多个运力渠道一成一取消、刚发单尚无骑手坐标、远端订单被删除、已完成订单五类场景。
