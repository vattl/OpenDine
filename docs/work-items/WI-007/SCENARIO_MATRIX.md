# Scenario Matrix — WI-007

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 门店分类独立排序 | 店A/店B共享分类；店A移动分类 | 只写店A覆盖，店B顺序不变 | INV-SORT-01 | `ShopMenuSortServiceTest` + SQL作用域审查 | PASS |
| S02 | 门店菜品分类内排序 | 店A两分类；移动分类1菜品 | 只重排店A分类1 | INV-SORT-01/02 | `sortDishesReordersOnlyWithinEffectiveCategory` | PASS |
| S03 | 重复与空排序 | 有重复、NULL旧值 | 以ID兜底并写连续1..n | INV-SORT-03 | 服务测试 + 比较器/连续化审查 | PASS |
| S04 | 越界位置 | targetIndex=0/999 | 收敛至首/末 | INV-SORT-03 | 控制器回归测试 + `move` 边界审查 | PASS |
| S05 | 非本店菜品 | 菜品存在但未挂当前店 | 明确失败且零写入 | INV-SORT-01 | 控制器/服务回归测试 | PASS |
| S06 | 同店并发/中途失败 | 同店同时排序或任一更新失败 | 门店锁串行且事务全回滚 | INV-SORT-04 | `FOR UPDATE` + `@Transactional(rollbackFor=Exception.class)` 事务审查 | PASS |
| S07 | 读取一致性 | 排序后读取后台/C端菜单 | 分类、分类内菜品按覆盖+ID稳定返回 | INV-SORT-02/03 | `orderCategoriesUsesRequestedShopOverridesAndStableIdTieBreak` + Mapper契约 | PASS |

## Acceptance rule

Material scenarios must be PASS or explicitly accepted as out of scope. UNKNOWN / NOT_VERIFIED material scenarios block acceptance.

