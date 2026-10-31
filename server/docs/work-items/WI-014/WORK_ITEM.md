# WORK ITEM — WI-014

## Request

给日结预检增加提示可作废的打包单外卖单，超过30分钟未支付可一键全部作废。

## Type

FEATURE

## State

ACCEPTED

## Requirement Contract

### Goal

在日结预检（`GET /admin/daily/pre-check`）和日结流程中增强对未支付打包单/外卖单的智能识别与一键清理机制：
1. **日结预检提示**：
   - 在预检接口中，针对阻断项 `OPEN_ORDERS`（当前营业日未结账订单），识别出满足“可作废条件”的打包/外卖订单；
   - 判定规则：`transac_status = 'unsettled'`，且就餐方式为打包、自提、外卖（即 `PaymentDiningTypeUtil.isPackOrDeliveryType(dineInOrTakeOut)` 为 `true`），且订单创建时间距今已超过指定阈值（默认 30 分钟，`order_time <= now - 30 minutes`）；
   - 在预检响应中返回结构化统计与明细（如 `voidable_pack_takeout_count`、`voidable_pack_takeout_amount`、`voidable_pack_takeout_orders` 以及在 `blockers` 对应条目中附带 `voidable_pack_takeout` 汇总），明确提示收银员/店长可一键清理；
2. **一键全部作废**：
   - 暴露专属端点 `POST /admin/daily/void-stale-takeout-orders`（或在 `POST /cashier/order/batch-cancel-stale-takeout` 提供对应收银能力）；
   - 权限要求：具备 `daily:settle` 或 `order:operate` 或 `admin:manage` 权限；
   - 在单次数据库事务中，原子将符合条件的订单状态置为 `cancelled`（`transac_status = 'cancelled'`, `order_receiving = 'cancelled'`）；
   - 完整触发关联副作用：
     - 回退菜品占用库存（`dishShopStockService.restoreForDetail`，跳过已退菜行）；
     - 同步通知 KDS 厨房显示屏作废工单（`kdsOrderHook.afterOrderCancelled`）；
     - 取消关联外卖配送单（`takeoutDeliveryService.markCancelledIfPresent`）；
     - 取消关联的未完成收款意向（`collectionIntentService.cancelAllForOrder` 或批量清理）；
     - 记录特权/批量操作审计日志（`t_operation_log`）。

### Current behavior

- `GET /admin/daily/pre-check` 仅对当前营业日窗口内所有 `transac_status = 'unsettled'` 进行计数统计，只要存在未结订单就返回 `can_settle = false`；
- 打包单和外卖单由于没有桌台清台机制，若顾客下单后未付款或跑单，必须收银员一笔笔翻找订单并手动取消；如果未结订单较多，日结预检会严重受阻；
- 无批量作废超时打包/外卖单的安全快捷通道。

### Target behavior

1. 预检响应丰富化：
   - `GET /admin/daily/pre-check` 的响应体顶层及 `OPEN_ORDERS` blocker 中带出 `voidable_stale_pack_takeout`：
     - `count`: 可作废的超时未支付打包外卖单数量；
     - `amount`: 可作废订单总金额（元）；
     - `threshold_minutes`: 判定超时阈值（30）；
     - `orders`: 可作废订单精简清单（`id`, `order_no`, `order_time`, `sett_amount`, `dineInOrTakeOut`, `age_minutes`）；
2. 一键批量作废端点：
   - `POST /admin/daily/void-stale-takeout-orders`；
   - 支持请求参数：`minutes`（可选，默认 30，最小 10）；`stat_date`（可选，指定营业日窗口或当前活动营业日）；
   - 批量作废成功后，返回作废笔数 `voided_count`、释放金额 `voided_amount`、作废订单号列表 `voided_order_nos`；
   - 完整保证库存释放、KDS 作废、配送单取消与收款意向清理；
   - 作废完成后再次调用日结预检，可直接消除这部分打包/外卖单的阻断，若全为超时打包外卖单，一键作废后日结预检即可通过。

### Must preserve

1. 严禁误伤堂食（`dine_in`）订单！堂食必须结账或手动清台，绝不允许被一键作废。
2. 严禁误伤已支付订单（`transac_status = 'success'`）或已退款订单。
3. 严格遵循 30 分钟超时边界，距下单时间不足 30 分钟的打包/外卖单不得被一键作废，避免误取消正在制作或顾客刚下的单。
4. 必须同步释放库存并通知 KDS，不得产生“订单作废但厨房还在炒菜、库存未还回”的数据不一致。

### Acceptance criteria

- [x] 日结预检正确识别超过 30 分钟未支付的打包/外卖单，并在 `OPEN_ORDERS` 与顶层输出提示与统计。
- [x] 堂食单、已支付单、未满 30 分钟打包单绝不计入可作废列表。
- [x] 提供 `POST /admin/daily/void-stale-takeout-orders` 一键作废端点。
- [x] 作废时原子更新订单状态为 `cancelled`，回退库存，通知 KDS 作废工单，取消外卖配送与收款意向，记录审计日志。
- [x] 同步更新 `docs/openapi.yaml` 与 `docs/API.md`。
- [x] 全量通过 Maven 打包构建。

## Tasks / Vertical Slices

- [x] T01 扩展 `DailyCloseServiceImpl.precheck` 增加可作废打包外卖单识别
- [x] T02 实现 `DailyCloseServiceImpl.voidStalePackTakeoutOrders` 批量作废与副作用
- [x] T03 在 `AdminDailyController` 与 `ApiPermissionMapping` 暴露并保护端点
- [x] T04 编写单元测试验证预检统计与作废副作用
- [x] T05 同步文档并全量打包验证

## Acceptance Decision

ACCEPTED。

## Business Invariants

- INV-VOID-TAKEOUT-01：严禁自动作废堂食订单（`dine_in`）。
- INV-VOID-TAKEOUT-02：未满指定超时时长（默认 30 分钟）的打包/外卖单严禁作废。
- INV-VOID-TAKEOUT-03：作废订单必须级联释放库存与通知 KDS。

## Implementation Ready

- Status: `YES`
- Blockers: NONE

