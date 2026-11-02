# Completion Evidence — WI-070

## 1. 交付产物

| 类型 | 路径 / 标识 | 说明 |
|---|---|---|
| 数据库迁移 | `src/main/resources/db/migration/V048__combo_store_isolation.sql` | 增加 `shop_id` 列，建立复合唯一索引 `uk_combo_dish_shop` |
| 实体模型 | `src/main/java/com/lanf/entity/Combo.java` | 增加 `shop_id` 属性及 getter/setter |
| 服务接口与实现 | `src/main/java/com/lanf/service/IComboMealService.java`<br>`src/main/java/com/lanf/service/impl/ComboMealServiceImpl.java` | 门店隔离查询与保存、总部模板平滑回退继承 |
| 后台控制器 | `src/main/java/com/lanf/controller/admin/AdminComboController.java` | 增加门店解析与 `AdminShopScopeGuard` 越权防护 |
| C端控制器 | `src/main/java/com/lanf/controller/DishController.java` | 传递当前门店 ID 进行套餐关联与展示 |
| API 契约文档 | `docs/API.md`<br>`docs/openapi.yaml` | 同步记录 `v1.2.332 / WI-070` 套餐门店隔离接口与参数规范 |
| 单元与集成测试 | `src/test/java/com/lanf/controller/admin/AdminComboStoreIsolationTest.java` | 包含 5 个专项隔离与越权拦截用例 |
| 打包产物 | `target/diancan-0.0.1-SNAPSHOT.jar` | Maven clean package 构建的可执行应用 Jar |

## 2. 验证记录

### 2.1 自动化测试
- `.\mvnw.cmd test "-Dtest=AdminComboStoreIsolationTest,ComboMealServiceImplTest,ComboCommercialRulesTest"` -> 16 tests passed, 0 failures.
- `.\mvnw.cmd test -Dtest=OrderControllerAddDishesComboTest` -> 3 tests passed, 0 failures.

### 2.2 跨店保存防覆盖实测
- 门店 1 与 门店 2 针对相同 `dishId` 独立保存配置：
  - 门店 1 仅影响 `shop_id = 1` 的记录及子项；
  - 门店 2 仅影响 `shop_id = 2` 的记录及子项；
  - 互不删除，互不覆盖。
