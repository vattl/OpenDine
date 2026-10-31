# Implementation Design — WI-009

## Root Fix / Owner

在 `OrderController.addDishes` 共享加菜事务中停止为既有订单重新设置 `order_time`。

## Why this location

问题由该方法直接赋当前时间造成；收银端和 AI 均委托此方法。在读路径补偿会保留错误数据并导致消费者口径继续不一致。

## End-to-End Change

### Backend

保留已从数据库锁定行读取的原 `order_time`，更新金额、费用、折扣、轮次、状态和备注时不改变它。

### Frontend

无需修改。

### UI / Interaction

NONE。

### Data / Persistence

无 DDL 或历史数据迁移；仅阻止未来加菜改写 `t_order.order_time`。

### Interfaces / Contracts

请求/响应兼容；文档补充 `order_time` 的稳定语义。

### Jobs / Events / Integrations

KDS、打印、库存与事件发布流程不变。

## Preserve / Compatibility

加菜权限、套餐标准化、库存扣减、优惠重算、服务费、桌台金额、自动接单和幂等逻辑均保持。

## API Consumer Migration / Handoff

NONE。

## Failure / Boundary Behavior

原有参数与业务失败行为不变。

## Runtime / Performance / Reliability

无新增查询；同一订单仍使用行锁串行化。

## Security / Permissions

无权限变化；继续使用既有身份与门店校验。

## UI Design Track

NOT_APPLICABLE。

## Vertical Slice Plan

1. 在现有成功加菜测试中设置固定原始时间并断言加菜后不变，先获得 RED。
2. 删除共享入口的时间重置，获得 GREEN。
3. 同步文档并运行定向、全量与 JAR 打包。

## Verification Strategy

定向运行 `OrderControllerAddDishesComboTest`，再运行完整 Maven 测试；解析 OpenAPI YAML，并执行强制 clean package。

## Rollback / Recovery

回退单行行为变更及对应测试/文档即可；无数据迁移。
