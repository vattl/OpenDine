# WORK ITEM — WI-035

## Request

审计并修复并台后加菜导致订单总金额与桌台显示金额不一致的问题。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

加菜完成后，桌台金额必须等于该门店、该桌全部未结订单的实际净应付金额之和；并台多单不得被本次加菜的单笔订单金额覆盖。

### Current behavior

`POST /order/addDishes` 更新被加菜订单后，直接以该单的局部 `paidAmount` 覆盖 `t_table.amount`。并台后同桌存在多笔未结订单时，其他订单金额被遗漏；该局部公式也未复用统一 `OrderNetRevenue` 口径。

### Target behavior

- 加菜后先持久化订单金额，再查询同门店、同桌全部未结订单。
- 桌台金额使用 `OrderNetRevenue.netRevenueYuan` 逐单汇总并保留两位小数、最低为 0。
- 单订单、并台多订单、优惠/退款/赠送金场景使用同一口径。
- 加菜失败时订单、明细与桌台金额保持事务回滚。

### Must preserve

- 加菜权限、门店隔离、套餐标准化、库存、优惠券、KDS 与打印行为不变。
- 加菜不更新首次下单时间。
- 保留工作区 WI-034 套餐商业化未提交改动。

### Acceptance criteria

- [x] 并台两笔未结订单，对其中一单加菜后桌台金额等于两单最新净应付之和。
- [x] 加菜订单自身的 `sett_amount` 与优惠/服务费更新保持正确。
- [x] 桌台金额不再使用单笔局部公式覆盖。
- [x] API 文档同步，专项、全量测试与 JAR 打包通过。

## Tasks / Vertical Slices

- [x] T01 新增并台后加菜金额漂移的失败测试。
- [x] T02 统一加菜后的桌台金额汇总口径。
- [x] T03 审计并台、桌台状态与加菜消费者并同步 API 文档。
- [x] T04 运行专项、全量测试、审查、安全检查和打包。

## Business Invariants

- INV-TABLE-035-01：`t_table.amount` 等于同门店同桌全部未结订单净应付之和。
- INV-TABLE-035-02：任何单笔订单变更不得丢失并台桌上的其他未结订单金额。
- INV-ORDER-035-01：所有桌台汇总均复用 `OrderNetRevenue` 统一净应付口径。

## Consumer Handoffs

响应结构不变，消费者无需改造；仅修正加菜后的桌台金额语义。

## Acceptance Decision

ACCEPTED。

## Integration / Release

目标为本地 ACCEPTED；不含推送或部署。

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`
