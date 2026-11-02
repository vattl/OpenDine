# Impact Map — WI-007

## Authoritative Owner

门店菜单排序由服务端持久层模型与后台排序接口共同负责：分类门店覆盖为 `t_category_shop`，菜品门店覆盖为 `t_dish_shop`。

## Change Propagation Path

```text
后台拖拽 + 当前门店头
→ POST /admin/category/sort 或 /admin/dish/sort
→ 门店上下文校验
→ 当前门店行锁 + 稳定重排
→ t_category_shop / t_dish_shop
→ 后台列表、C 端分类/菜单、DishMapper 分页列表
→ 当前门店展示确定且隔离
```

## Consumer Coverage
| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 运营后台 | 排序写入与列表读取 | AFFECTED | NO（契约字段兼容） | 控制器与 OpenAPI |
| 小程序菜单 | 分类/菜品展示顺序 | AFFECTED | NO | `DishController#listAll` |
| C 端分类列表 | 分类展示顺序 | AFFECTED | NO | `CategoryController#listAll` |
| 收银台目录 | 后台门店菜品列表 | AFFECTED | NO | `DishMapper.xml` |
| WebSocket 菜单订阅 | 排序成功刷新 | VERIFIED_UNAFFECTED | NO | 继续广播既有事件 |

## Layer Coverage
| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 不改布局、交互或视觉，仅修复服务端既有拖拽语义 |
| Interaction | VERIFIED_UNAFFECTED | 仍传 `id + targetIndex` |
| Frontend State | VERIFIED_UNAFFECTED | 返回结构不变，刷新后按服务端顺序展示 |
| API Client | VERIFIED_UNAFFECTED | 路径、方法、字段不变 |
| Request Contract | AFFECTED | 明确 `targetIndex` 为当前门店、当前层级 1-based 位置 |
| Backend/Domain | AFFECTED | 门店作用域、分类内重排、原子并发控制 |
| Persistence | AFFECTED | 新增 `t_category_shop`；使用现有 `t_dish_shop.sorting_override` |
| Response Contract | VERIFIED_UNAFFECTED | `R` 结构不变 |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 继续发送 `dish_catalog_changed` |
| Config/Security | VERIFIED_UNAFFECTED | 复用拦截器解析且授权的门店上下文 |
| Runtime/NFR | AFFECTED | 同店行锁串行；不同门店互不阻塞 |
| Tests | AFFECTED | 控制器/排序服务/SQL契约回归 |

## Duplicate Logic / Patch Smells

两个控制器内均有手写重排；根修复将排序事务放入专用服务，控制器只处理 API 边界与事件。

## Contract Delta Summary

字段兼容、语义收紧：排序作用域从全局/全店混排改为当前门店对应层级；缺失门店上下文返回业务错误。

## UI Semantic Impact

排序结果可见但无 UI 设计变化，UI Design Track 不适用。

## Risks

- 目标数据库必须先执行新增表迁移。
- 旧分类排序首次读取时回退 `t_category.sorting`；首次排序后写入完整门店覆盖。
- 锁顺序统一先锁 `t_shop` 再读写排序行，避免同店并发交错。

