# Contract Delta — WI-012

`GET /admin/table/status` 路径、参数和响应结构保持兼容。金额语义修正为：`tableList[].amount`、`amountAudit.payable_amount` 均来自当前桌未结订单的持久化实际净应付金额；明细不再作为金额真源。
