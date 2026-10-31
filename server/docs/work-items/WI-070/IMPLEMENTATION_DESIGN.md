# Implementation Design — WI-070

## Root Fix / Owner

- 核心归属：套餐领域服务 `IComboMealService` 与实体表 `t_combo`。
- 根治逻辑：
  1. 表结构升级：`t_combo` 增加 `shop_id INT NOT NULL DEFAULT 0 COMMENT '门店ID，0表示总部通用模板'`；将唯一键由 `uk_combo_dish (dish_id)` 重构为 `uk_combo_dish_shop (dish_id, shop_id)`。
  2. 隔离查询机制：
     - 当传入门店 `shopId > 0` 时，首先检索 `dish_id = :dishId AND shop_id = :shopId` 的门店专属套餐；
     - 若未找到，无缝回退检索 `dish_id = :dishId AND (shop_id = 0 OR shop_id IS NULL)` 的总部统一模板；
     - 当未指定门店（`shopId` 为空或 0）时，直接操作总部统一模板。
  3. 隔离保存机制：
     - 保存套餐时，以 `(dish_id, targetShopId)` 为唯一定位键；
     - 仅删除属于当前门店的套餐记录及其下挂的子项与分组，彻底阻断对其他门店或总部套餐记录的误删；
     - 配合 `AdminShopScopeGuard` 拦截单店管理员跨店操作他店套餐的越权行为。

## Verification Strategy

1. **迁移幂等性与表结构验证**：
   - 执行 Flyway 迁移脚本，验证 `shop_id` 字段及 `uk_combo_dish_shop` 唯一索引成功创建，存量历史数据无损保留。
2. **多店防覆盖测试**：
   - 构造场景：门店 1 保存一套套餐内容（包含子菜 A、B）；
   - 门店 2 为同名/同 `dish_id` 的菜品保存另一套套餐内容（包含子菜 C、D）；
   - 验证：门店 1 查询仍返回（A、B），门店 2 查询返回（C、D），两店互不覆盖、互不干扰。
3. **总部模板回退测试**：
   - 总部保存 `shop_id = 0` 的默认套餐；
   - 门店 3 未曾保存过套餐，查询时成功命中并返回总部默认模板。
4. **越权防护测试**：
   - 门店 1 账号试图修改门店 2 的套餐配置，触发 `AdminShopScopeGuard` 4003 拦截。
5. **全量编译与打包**：
   - 运行 Maven 测试套件与全量打包 `mvn clean package -DskipTests`。
