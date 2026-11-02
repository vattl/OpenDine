# Contract Delta — WI-035

## Endpoints

- `POST /order/addDishes`
- `POST /cashier/order/addDishes`
- 后续读取桌台列表/状态的金额字段

## Delta

请求、响应字段与状态码不变。修正副作用：加菜完成后 `t_table.amount` 不再等于被加菜的单笔订单，而是等于当前门店、当前桌全部未结订单的实际净应付之和。

## Compatibility

Backward compatible bug fix。客户端无需变更。
