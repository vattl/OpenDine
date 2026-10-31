# Layer Impact Matrix — WI-009

| Layer / Consumer | Impact | Required action | Verification |
|---|---|---|---|
| 小程序 `/order/addDishes` | 共享逻辑修复 | 无客户端改动 | 共享控制器测试 |
| 收银 `/cashier/order/addDishes` | 间接受益 | 无客户端改动 | 委托代码检查 + 全量回归 |
| AI `add_dishes` | 间接受益 | 无调用改动 | 委托代码检查 + 全量回归 |
| `t_order` | `order_time` 不再被加菜刷新 | 删除错误赋值 | 固定时间回归断言 |
| `t_order_detail` / 库存 / 桌台金额 | 无语义变化 | 保持现状 | 现有加菜测试 |
| 账单、报表与 KDS 读路径 | 获得稳定首单时间 | 无读路径改动 | 完整回归 + 契约检查 |
| API 文档 | 语义澄清 | 同步 OpenAPI/API.md | YAML 解析 + diff review |

Material UNKNOWN count: 0
