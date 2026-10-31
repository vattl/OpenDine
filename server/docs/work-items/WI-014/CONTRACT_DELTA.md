# Contract Delta — WI-014

- `GET /admin/daily/pre-check`:
  - 响应新增 `voidable_stale_pack_takeout` 对象：包含 `count` (int), `amount` (double), `threshold_minutes` (int), `orders` (list);
  - 阻断项 `OPEN_ORDERS` 新增 `voidable_pack_takeout` 嵌套字段。
- `POST /admin/daily/void-stale-takeout-orders`:
  - 请求体支持可选 `minutes`（默认 30）与 `stat_date`；
  - 响应返回 `voided_count`, `voided_amount`, `voided_order_nos`。
