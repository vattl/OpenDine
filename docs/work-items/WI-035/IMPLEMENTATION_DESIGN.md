# Implementation Design — WI-035

## Root Fix / Owner

删除加菜路径对 `table.amount` 的单订单覆盖。订单更新成功后，按 `shop_id + table_number + transac_status=unsettled` 查询整桌订单，使用 `OrderNetRevenue.netRevenueYuan` 汇总后写回桌台。

## Compatibility

- API 路径、请求字段、响应结构和状态码不变。
- 单订单桌台结果与原正确场景一致。
- 并台多订单由少算修正为完整汇总。
- 使用统一净应付公式后，退款与赠送金不会被局部公式遗漏。

## Failure / Transaction Behavior

桌台更新仍位于 `addDishes` 事务内；查询或更新失败抛异常并回滚订单、明细和桌台变更。

## Verification Strategy

1. RED：并台桌两单，第一单加菜后旧实现只写第一单金额。
2. GREEN：验证桌台写入两单净应付总和。
3. 回归单订单套餐加菜、首次下单时间、并台服务与桌台状态测试。
4. 全量测试与强制 JAR 打包。
