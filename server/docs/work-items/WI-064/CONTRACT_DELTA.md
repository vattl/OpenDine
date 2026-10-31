# Contract Delta — WI-064

## Affected Endpoints
- `POST /order/addDishes`
- `POST /cashier/order/addDishes`
- `POST /cashier/order/refundDish`
- `POST /cashier/order/updatePrice`
- `POST /cashier/order/discount`

## Additive Request
```json
{"expectedVersion": 12}
```
兼容别名：`expected_version`。本阶段可选，非负整数。

## Additive Success
```json
{"code": 0, "revision": 13}
```

## New Conflict
HTTP 409：
```json
{
  "code": 409,
  "error": "ORDER_VERSION_CONFLICT",
  "error_code": "ORDER_VERSION_CONFLICT",
  "msg": "订单已被其他终端修改，请刷新后重试",
  "data": {"orderNo": "ORD-1", "revision": 13, "transacStatus": "unsettled"}
}
```
