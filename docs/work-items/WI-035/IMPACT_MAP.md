# Impact Map — WI-035

## Authoritative Owner

- 订单净应付公式：`OrderNetRevenue.netRevenueYuan`。
- 加菜事务：`OrderController.addDishes`。
- 并台事务：`CashierTableOperationTransactionalService`。
- 桌台状态展示：`AdminTableController.status` / `TableStatusAmountCalculator`。

## Failure Path

```text
并台 → 同桌保留多笔 unsettled 订单
→ 对其中一单调用 POST /order/addDishes 或 /cashier/order/addDishes
→ 被加菜订单金额更新
→ t_table.amount 被单笔 paidAmount 覆盖
→ 桌台列表金额少算同桌其他订单，与订单总额不一致
```

## Layer Coverage

| Layer | Classification | Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 不编辑客户端界面；现有 UI 读取后端桌台金额 |
| API Contract | AFFECTED_BEHAVIOR | 加菜后可观察的桌台金额语义修正，结构不变 |
| Controller | AFFECTED | `OrderController.addDishes` 错误覆盖桌台金额 |
| Domain utility | REUSED | `OrderNetRevenue` 是统一净应付口径 |
| Merge service | VERIFIED_CORRECT | 并台使用 `outstandingAmount` 汇总全部未结订单 |
| Persistence | AFFECTED_EXISTING | 更新现有 `t_table.amount`，无 schema 变化 |
| KDS/printing | PRESERVED | 加菜后处理链不变 |
| Tests | AFFECTED | 增加并台多单加菜回归 |

## Dirty Worktree Boundary

现有 WI-034 修改了 `OrderController` 的套餐规则校验以及套餐/数据库相关文件。本 Work Item 只在加菜金额同步位置做最小增量修改，不重置、不覆盖 WI-034 内容。

## Material Unknowns

0。
