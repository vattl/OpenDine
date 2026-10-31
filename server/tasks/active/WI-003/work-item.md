# WORK ITEM — WI-003

## Request

增加了实际配送费字段，获取配送记录的接口增加返回实际配送费，接口要支持自定义时间筛选，默认获取当前营业日的数据

## Type

FEATURE / ENHANCEMENT / BACKEND

## State

DONE

## Requirement Contract

### Goal

1. 配送记录接口 `POST /admin/takeout/delivery/list` 返回结果包含实际配送费（`zsq_actual_fee` 与 `actual_delivery_fee`）。
2. 支持自定义时间筛选（`startTime` / `start_time` 与 `endTime` / `end_time`）。
3. 当客户端未提供时间时，默认获取门店当前营业日 `[D settle_time, D+1 settle_time)` 的配送记录数据。

### Current behavior

- `POST /admin/takeout/delivery/list` 仅接收 `pageNum`, `pageSize`, `dispatch_status`，未支持时间筛选参数。
- 数据库查询未施加时间限制，默认返回门店全部历史记录。
- `TakeoutDelivery` 已持久化 `zsq_actual_fee`，但无 `actual_delivery_fee` 语义别名属性。

### Target behavior

- `POST /admin/takeout/delivery/list` 支持接收可选的 `startTime`（或 `start_time`）与 `endTime`（或 `end_time`）。
- 未传时间时，根据当前门店 `settle_time`（默认 04:00）自动计算当前活动营业班次 `[D settle_time, D+1 settle_time)` 并筛选 `t_takeout_delivery.created_at`。
- 响应返回 `list`, `total`, `startTime`, `endTime`, `pageNum`, `pageSize`。
- 列表项及详情中的 `TakeoutDelivery` 对象均序列化返回 `zsq_actual_fee` 与 `actual_delivery_fee`。

### Must preserve

- 现有 `pageNum`, `pageSize`, `dispatch_status` 筛选功能与分页行为。
- `X-Shop-Id` 门店隔离与权限校验。
- 其他外卖配送接口（`/delivery/detail`, `/delivery/tracking` 等）的已有行为。

### Acceptance criteria

- [x] `TakeoutDelivery` 具备 `actual_delivery_fee` 属性，与 `zsq_actual_fee` 对齐。
- [x] `ITakeoutDeliveryService.pageByShop` 支持时间区间重载。
- [x] `AdminTakeoutController.deliveryList` 支持 `startTime`/`endTime` 参数，未传时默认取当前营业日。
- [x] 响应体包含生效的 `startTime` 与 `endTime`。
- [x] 单元测试覆盖默认当前营业日、自定义时间区间、实际配送费字段校验。
- [x] `docs/openapi.yaml` 与 `docs/API.md` 同步更新。
- [x] Maven 全量编译打包成功（`mvn clean package -DskipTests`）。
