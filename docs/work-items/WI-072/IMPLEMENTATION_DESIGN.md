# Implementation Design — WI-072

## Root Fix / Owner

核心归属为 `ApiPermissionMapping` 与 `DbApiPermissionMapping`。
通过系统性审计补全所有未配置权限的 Controller 端点，并在 `t_permission` 与 `t_api_permission` 中建立细粒度的权限分类字典，彻底杜绝 403 `接口权限未配置`，同时实现最小特权安全授权。

## 架构与分类设计

### 1.1 权限码细粒度设计规则
权限码命名空间遵循：`<module>:<submodule>:<action>` 或 `<module>:<action>`。
对于历史已有粗粒度角色，在 `t_api_permission.permission_code` 中使用管道符 `|` 声明允许的角色权限集合，格式为：
`coarse_permission|fine_permission`

### 1.2 细粒度补充清单与分类

#### (1) 菜品与套餐模块 (dish / combo)
- `/admin/combo/getByDishId`: `dish:manage|dish:manage:dish|dish:manage:combo`
- `/admin/combo/save`: `dish:manage|dish:manage:dish|dish:manage:combo`

#### (2) 订单与发票模块 (order / invoice)
- `/admin/order/invoice/qrcode`: `order:operate|order:invoice:create`
- `/admin/order/invoice/status/*`: `order:view|order:invoice:view`
- `/admin/order/updateDiners`: `cashier:operate|order:operate`
- `/admin/order/commands`: `cashier:operate|order:operate`
- `/admin/merchant/orders`: `order:view`
- `/admin/merchant/orders/summary`: `order:view`

#### (3) 营销与首单立减活动 (marketing)
- `/admin/marketing/first-order/campaigns` (GET): `marketing:firstorder:view`
- `/admin/marketing/first-order/campaigns` (POST): `marketing:firstorder:manage`
- `/admin/marketing/first-order/campaigns/*` (PUT): `marketing:firstorder:manage`
- `/admin/marketing/first-order/eligibility/evaluate` (POST): `marketing:firstorder:view`
- `/admin/marketing/first-order/redemptions` (GET): `marketing:firstorder:view`

#### (4) 高级库存模块 (inventory)
- `/admin/inventory/batches`: `inventory:view`
- `/admin/inventory/boms` (GET): `inventory:view`
- `/admin/inventory/boms` (POST): `inventory:manage`
- `/admin/inventory/boms/*` (PUT): `inventory:manage`
- `/admin/inventory/boms/*/activate` (PUT): `inventory:manage`
- `/admin/inventory/purchases` (GET): `inventory:view`
- `/admin/inventory/purchases` (POST): `inventory:manage`
- `/admin/inventory/purchases/*` (PUT): `inventory:manage`
- `/admin/inventory/suppliers` (GET): `inventory:view`
- `/admin/inventory/suppliers` (POST): `inventory:manage`
- `/admin/inventory/suppliers/*` (PUT): `inventory:manage`
- `/admin/inventory/suppliers` (DELETE): `inventory:manage`
- `/admin/inventory/transfers` (GET): `inventory:view`
- `/admin/inventory/transfers` (POST): `inventory:manage`
- `/admin/inventory/transfers/*/receive` (PUT): `inventory:manage`
- `/admin/inventory/warehouses` (GET): `inventory:view`
- `/admin/inventory/warehouses` (POST): `inventory:manage`
- `/admin/inventory/warehouses/*` (PUT): `inventory:manage`

#### (5) 日志归档与导出 (log)
- `/admin/logs`: `log:view`
- `/admin/logs/archive-search` (POST): `log:archive`
- `/admin/logs/archive-search/*` (GET): `log:archive`
- `/admin/logs/exports` (POST): `log:export`

#### (6) 通知规则 (notifications)
- `/admin/notifications/rules` (GET): `notifications:view`
- `/admin/notifications/rules` (POST): `notifications:manage`
- `/admin/notifications/rules/*` (PUT): `notifications:manage`
- `/admin/notifications/rules/*` (DELETE): `notifications:manage`
- `/admin/notifications/rules/*/test` (POST): `notifications:manage`
- `/admin/notifications/deliveries` (GET): `notifications:view`

#### (7) 报表导出与跨店结算 (report)
- `/admin/reports/exports` (POST): `report:export`
- `/admin/reports/exports` (GET): `report:export`
- `/admin/reports/exports/*/download` (GET): `report:export`
- `/admin/report/member/cross-shop-clearing`: `report:view|finance:view`

#### (8) 系统设置管理 (settings)
- `/admin/settings/overview` (GET): `settings:view`
- `/admin/settings/store` (GET): `settings:view`
- `/admin/settings/store` (PUT): `settings:manage`
- `/admin/settings/store/override` (DELETE): `settings:manage`
- `/admin/config/member-balance-cross-shop`: `shop:manage|admin:manage`

#### (9) 支付渠道运营 (payment)
- `/admin/payment/channels/*/impact` (POST): `payment:view|payment:manage`
- `/admin/payment/channels/*/test` (POST): `payment:manage`

#### (10) 会员画像标签 (member / user)
- `/admin/member/persona-tags` (GET): `user:view`

#### (11) 收银台与移动 POS 别名接口 (cashier / pos)
- `/cashier/shop/business`: `cashier:operate|shop:manage`
- `/api/pos/orders/hang-list`, `/api/pos/hang-list`: `cashier:operate`
- `/api/pos/orders/today`, `/api/pos/today`: `cashier:operate`
- `/api/pos/orders/search`, `/api/pos/search`: `cashier:operate`
- `/api/pos/orders/printContent`, `/api/pos/printContent`: `cashier:operate`
- `/api/pos/tables/open`, `/api/pos/open`: `cashier:operate|table:operate`
- `/api/pos/tables/merge`, `/api/pos/merge`: `cashier:operate|table:operate`
- `/api/pos/tables/transfer`, `/api/pos/transfer`: `cashier:operate|table:operate`
- `/api/pos/tables/clear`, `/api/pos/clear`: `cashier:operate|table:operate`
- `/api/pos/tables/statusMap`, `/api/pos/statusMap`: `cashier:operate`
- `/cashier/table/table-areas`, `/cashier/table/tables/areas`, `/api/pos/tables/areas`, `/api/pos/tables/table-areas`, `/api/pos/tables/tables/areas`, `/api/pos/areas`: `cashier:operate|table:view`
- `/cashier/table/tables/batch-clear`, `/api/pos/tables/tables/batch-clear`, `/api/pos/batch-clear`: `cashier:operate|table:operate`
- `/cashier/table/tables/pulse`, `/api/pos/tables/tables/pulse`, `/api/pos/pulse`: `cashier:operate|table:view`
- `/activity/getAllPopup`: `banner:manage`
- `/api/feieyun/*`: `printing:manage|cashier:operate`

## Verification Strategy

1. **扫描与审计自动化验证**：运行审计脚本验证所有 Controller 路径 100% 映射或白名单放行，UNMAPPED 数量归零；
2. **安全断言测试**：运行 `ApiPermissionMappingCompletenessSecurityTest`，断言全部关键业务路径具备确切且细粒度的权限码；
3. **拦截器集成测试**：验证粗粒度角色与细粒度角色均能按预期放行/拒绝；
4. **编译与打包**：执行 `mvn clean package -DskipTests` 验证 Flyway 脚本与生产构建。
