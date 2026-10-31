# Contract Delta — WI-009

## Endpoints

- `POST /order/addDishes`
- `POST /cashier/order/addDishes`（内部委托前者）

## Before

成功加菜会把订单主表 `order_time` 刷新为加菜时刻。

## After

成功加菜保持订单首单创建时的 `order_time` 不变。

## Compatibility

请求字段、响应字段、错误码及权限不变。消费者无需迁移。
