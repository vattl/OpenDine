# WORK ITEM — WI-070

## Request

审计并实现套餐门店数据隔离，修复同名套餐跨店覆盖套餐内容缺陷。

## Type

BUG / DATA_MODEL / MULTI_TENANT_ISOLATION

## State

ACCEPTED

## Requirement Contract

### Goal

为套餐定义（`t_combo`）引入门店（`shop_id`）隔离机制，实现：
1. 套餐定义与固定子菜、可选分组按门店维度独立存储和维护；
2. 同名套餐在不同门店间具有独立的套餐内容与商业化规则，互不覆盖；
3. 支持总部通用套餐模板（`shop_id = 0`）与门店专属自定义套餐（`shop_id = :shopId`），未定制的门店可自动回退继承总部模板；
4. 小程序端与收银端点餐、算价、下单及展开套餐明细全链路按所在门店读取专属套餐配置。

### Current behavior

1. `t_combo` 缺少 `shop_id` 字段，且设有 `UNIQUE KEY uk_combo_dish (dish_id)`；
2. 门店在新建菜品时若命中同名菜品，`AdminDishController.save` 会强制复用总库已有的 `dish_id`；
3. `POST /admin/combo/save` 保存时直接根据 `dish_id` 物理删除原套餐所有固定项和可选分组；
4. 导致多门店配置同名套餐时发生严重的跨店覆盖，后保存的门店内容会直接覆盖前一个门店的内容。

### Target behavior

1. 数据库迁移 `V048__combo_store_isolation.sql` 为 `t_combo` 增加 `shop_id INT NOT NULL DEFAULT 0`，复合唯一索引变更为 `uk_combo_dish_shop (dish_id, shop_id)`；
2. `AdminComboController`（`getByDishId`、`save`）支持解析门店上下文（请求体/参数 `shopId` 或请求头 `X-Shop-Id`），并受 `AdminShopScopeGuard` 越权防护；
3. `ComboMealServiceImpl.getByDishId(dishId, shopId)` 优先查询指定门店专属套餐，未配置时回退总部模板（`shop_id = 0`）；
4. `saveComboDefinition` 仅删除和重写当前门店的套餐记录，严禁跨店删除其他门店或总部的套餐内容；
5. `DishController.attachComboDefinitions` 与 `ComboController.detail` 传入当前门店 `shopId`，获取并展示该门店专属套餐；
6. `OrderController` 下单与加菜展开套餐时按订单 `shop_id` 解析套餐及子菜。

### Acceptance criteria

- [x] 数据库迁移 `V048__combo_store_isolation.sql` 幂等执行，索引正确变更为 `uk_combo_dish_shop (dish_id, shop_id)`。
- [x] 门店 A 保存套餐内容后，门店 B 配置同名套餐（共享或独立 `dish_id`）保存，门店 A 的套餐内容完好无损。
- [x] 门店 B 查询套餐返回门店 B 的内容，门店 A 查询套餐返回门店 A 的内容。
- [x] 门店 C 未自定义套餐时，可正常回退读取总部模板（`shop_id = 0`）。
- [x] 小程序与收银端拉取菜单与套餐详情时，正确渲染对应门店的套餐与子菜。
- [x] 全套自动化回归与单元测试 100% 通过。
- [x] API 契约文档（`docs/API.md` 与 `docs/openapi.yaml`）同步更新。
- [x] Maven 编译打包成功生成可运行 JAR 包。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 数据库迁移脚本 `V048__combo_store_isolation.sql`。
- [x] T02 实体类 `Combo.java` 扩展 `shop_id` 字段。
- [x] T03 核心服务 `IComboMealService` & `ComboMealServiceImpl` 实现门店隔离与回退查找。
- [x] T04 控制器 `AdminComboController`、`DishController`、`ComboController` 接入门店上下文。
- [x] T05 权限与安全 `AdminShopScopeGuard` 拦截越权。
- [x] T06 单元测试与回归测试套件验证。
- [x] T07 文档同步与打包交付。

## Acceptance Decision

ACCEPTED：所有修改实施完毕，测试全部通过，JAR 打包完成，API 规范同步更新。

## Business Invariants

- 套餐配置不得跨店泄露与覆盖；
- 门店未定制套餐时必须平滑继承总部模板，保障连锁标准化能力；
- 下单计算与子菜校验必须在当前门店上下文中生效。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-070/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-070/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none

## Completion Level

ACCEPTED
