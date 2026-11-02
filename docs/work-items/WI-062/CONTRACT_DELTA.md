# Contract Delta — WI-062

## Additive response field
`POST /admin/access/evaluate` 的 data 新增 `outcome`：`ALLOW`、`REQUIRE_APPROVAL` 或 `DENY`。

## Compatibility
现有请求字段和路径不变；`allow`、`approvalRequired`、`reasonCode` 等字段保留。语义变化是无 context 请求也进入统一决策器，以及数据库映射缺失不再被代码清单静默补齐。

