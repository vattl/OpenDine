# Acceptance Report — WI-070

Decision: ACCEPTED

## 1. 验收结论
- **状态**: ACCEPTED
- **决议**: 经过代码审计、数据库迁移结构升级、双层回退服务架构重构、安全越权拦截测试、全套自动化测试套件回归以及 OpenAPI / API.md 文档同步，WI-070 符合全部验收准则。

## 2. 验收清单核对

| 准则项 | 状态 | 验证说明 |
|---|---|---|
| 数据库迁移 `V048__combo_store_isolation.sql` 幂等执行，索引正确变更 | PASS | 包含 `shop_id` 列，复合唯一索引 `uk_combo_dish_shop (dish_id, shop_id)` 与索引 `idx_combo_shop` |
| 门店 A 与门店 B 保存同名套餐互不覆盖 | PASS | `saveComboDefinition` 仅删除 `(dish_id, targetShopId)` 维度的固定项与可选分组，两店数据完全隔离 |
| 门店查询套餐内容严格按门店隔离 | PASS | 优先匹配当前 `shop_id` 的专属定义 |
| 门店未自定义时平滑回退总部模板 | PASS | `shop_id = 0` / NULL 作为连锁总部模板，门店未定制时自动继承 |
| 小程序与收银端拉取菜单与详情按门店渲染 | PASS | `DishController.attachComboDefinitions` 传入当前门店参数获取专属套餐 |
| 越权保存与越权查看安全防护 | PASS | `AdminShopScopeGuard` 严格校验，越权访问返回 4003 |
| 全套自动化回归与单元测试 100% 通过 | PASS | 16 个套餐与隔离测试 + 3 个加菜测试全部 PASS |
| API 契约文档同步更新 | PASS | `docs/API.md` 与 `docs/openapi.yaml` 均已更新并注明 WI-070 |
| Maven 打包产出可执行 JAR | PASS | `mvn clean package -DskipTests` 成功生成 `target/diancan-0.0.1-SNAPSHOT.jar` |
