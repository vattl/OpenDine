# Implementation Design — WI-007

## Root Fix / Owner

新增服务端 `ShopMenuSortService` 作为排序事务和稳定重排的唯一业务所有者；分类门店顺序存入新表 `t_category_shop`，菜品继续使用 `t_dish_shop.sorting_override`。

## Why this location

排序需要跨多行读取、锁定、计算和写入。放在事务服务而非控制器，才能保证 Spring 事务代理生效、复用一致锁顺序并可独立测试。

## End-to-End Change

### Backend

- 控制器校验请求和门店上下文，委托排序服务。
- 服务先 `SELECT t_shop ... FOR UPDATE`，同店排序串行、不同店并行。
- 分类按有效值 `(category_shop.sorting_override ?? category.sorting, category.id)` 稳定排序后写完整 `1..n` 覆盖。
- 菜品先确定当前门店链接与生效分类，只重排该分类链接，按 `(sorting_override ?? dish.sorting, dish.id)` 稳定排序后写完整 `1..n` 覆盖。

### Frontend

无需代码变更；继续提交拖拽后数组位置。

### UI / Interaction

无设计变化。

### Data / Persistence

- 新表 `t_category_shop(id, shop_id, category_id, sorting_override, updated_at)`。
- 唯一键 `(shop_id, category_id)`，外键约束到 `t_shop`/`t_category`。
- 读取缺少覆盖时回退总部排序，写排序时为当前店全量显式化。

### Interfaces / Contracts

路径、HTTP 方法、请求字段与响应外形不变；OpenAPI/API.md 明确门店作用域和分类内位置语义。

### Jobs / Events / Integrations

菜品排序保留既有菜单变更广播；分类排序新增同类广播以促使在线菜单刷新。

## Preserve / Compatibility

旧数据无需立即回填；无覆盖行自动回退 `t_category.sorting`。消费者字段零改动。

## API Consumer Migration / Handoff

无需迁移。消费者必须继续携带既有门店头，并传当前展示层级中的 1-based `targetIndex`。

## Failure / Boundary Behavior

- 缺门店上下文：`code=4001`。
- 分类/菜品不存在：业务错误。
- 菜品未挂当前店：业务错误。
- 越界位置收敛到首/末；`0` 收敛到首位。
- 数据库任一写入失败：整次排序回滚，不广播成功事件。

## Runtime / Performance / Reliability

单次排序 O(n log n) 读取与 O(n) 最多更新；n 为当前店分类数或当前分类菜品数。锁粒度为门店行，保证同店确定性且不阻塞其他门店。

## Security / Permissions

使用拦截器已解析且校验授权的门店 ID，不接受 body 中自行指定的门店范围。

## UI Design Track
N/A：服务端排序语义修复，无生产 UI 修改。

## Vertical Slice Plan

1. RED：新增门店隔离、分类内排序、错误边界测试并证明现状失败。
2. GREEN：新增持久模型/Mapper/事务服务并接入控制器与读取路径。
3. CONTRACT：同步 SQL、OpenAPI、API.md。
4. VERIFY：定向测试、全量测试、JAR 打包、独立代码审查、接受门禁。

## Verification Strategy

- 单元测试验证稳定重排、门店/分类隔离、越界与缺失上下文。
- Mapper XML/迁移契约测试验证门店分类排序 join 与唯一键。
- 全量 Maven 测试与强制 JAR 打包。
- Git diff 审查确保无跨范围改动。

## Rollback / Recovery

代码可回退到全局分类排序；新增表为加法迁移。若回退代码，可保留表且不会影响旧版本。

