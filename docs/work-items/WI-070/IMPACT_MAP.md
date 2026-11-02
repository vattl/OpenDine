# Impact Map — WI-070

## Authoritative Owner

- Domain Owner: `IComboMealService` / `ComboMealServiceImpl`
- Persistence Owner: `t_combo` / `ComboMapper` / `ComboFixedItemMapper` / `ComboGroupMapper` / `ComboGroupItemMapper`
- API Owner: `AdminComboController` / `DishController` / `ComboController`

## Layer Coverage

### 1. Persistence / Database Layer
- `src/main/resources/db/migration/V048__combo_store_isolation.sql`: 增加 `shop_id INT NOT NULL DEFAULT 0`，变更唯一键为 `uk_combo_dish_shop`。
- `src/main/java/com/lanf/entity/Combo.java`: 增加 `shop_id` 属性。

### 2. Service / Domain Layer
- `src/main/java/com/lanf/service/IComboMealService.java`:
  - 增加 `Combo getByDishId(int dishId, Integer shopId);`
  - 增加 `void saveComboDefinition(int dishId, Integer shopId, ...);`
- `src/main/java/com/lanf/service/impl/ComboMealServiceImpl.java`:
  - 实现基于 `(dish_id, shop_id)` 的两级查询（门店专属 -> 总部模板）；
  - `saveComboDefinition` 精确按 `(dish_id, targetShopId)` 删除和写入，杜绝跨店删除。

### 3. Controller / API Layer
- `src/main/java/com/lanf/controller/admin/AdminComboController.java`:
  - `GET /admin/combo/getByDishId`: 支持 `shopId` 参数与 `X-Shop-Id` 头；
  - `POST /admin/combo/save`: 支持 `shopId` 参数与 `X-Shop-Id` 头，添加 `AdminShopScopeGuard` 越权检查。
- `src/main/java/com/lanf/controller/DishController.java`:
  - `attachComboDefinitions(dishList, resolvedShopId)`: 传入当前选定门店，挂载门店专属套餐定义。
- `src/main/java/com/lanf/controller/ComboController.java`:
  - `getCustomerComboDetail(dishId, resolved)`: 内部对齐使用 `getByDishId(dishId, resolved)`。

### 4. Tests & Verification
- `src/test/java/com/lanf/service/impl/ComboMealServiceImplTest.java`: 补充多门店隔离及回退总部模板单元测试。
- 新增 `src/test/java/com/lanf/controller/admin/AdminComboStoreIsolationTest.java`: 验证跨店不覆盖、越权防护及两级继承。
