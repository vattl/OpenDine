# Work Item — WI-076

## Title

KDS 划菜整单制作完成自动叫骑手集成 (Automatic Rider Dispatch on KDS Whole Order Completed for Takeout)

## Type

FEATURE

## Goal

在 KDS 划菜整单完成流转（KdsOrderStatus.ALL_DONE）中增加外卖订单自动化叫骑手逻辑：当外卖订单的所有菜品在厨房完成制作与出餐时，系统自动识别外卖类型，校验配送状态与幂等性保护，安全触发聚合配送服务（真省钱/ZSQ）叫骑手，实现厨显出品与外卖履约骑手调度的无缝联动，提升出餐及配送流转效率。

## Requirement Contract

### Acceptance criteria

- [x] AC-01: 外卖订单在 KDS 所有菜品划菜完成流转至 `ALL_DONE` 时，自动触发真省钱叫骑手服务。
- [x] AC-02: 堂食、自提等非外卖订单整单完成时，仅执行取餐广播，绝不触发外卖叫骑手。
- [x] AC-03: 已处于 `dispatched`、`delivering`、`completed` 或 `pending` 的订单，整单完成事件重复触发时自动跳过，绝无重复扣费或呼叫。
- [x] AC-04: 叫骑手过程中第三方接口报错或超时被安全捕获，KDS 划菜出餐状态正常持久化，不抛出异常阻断业务。
- [x] AC-05: 单元测试全量通过，同步更新 OpenAPI/API 契约文档，Maven 打包生成可运行 JAR 产物。

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

NONE（KDS 服务端与外卖履约服务端同属于服务端内部事件驱动流转）。

## Integration / Release

INTEGRATED / NOT_RELEASED

## Related IDs

Workstream: KDS-TAKEOUT-AUTO-DISPATCH-V1
