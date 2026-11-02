# Security Audit — WI-070

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: PASS
SAST: PASS

## 1. 审计范围
本次审计针对套餐门店隔离改造涉及的越权防护、数据隔离及参数穿透风险进行评估。

## 2. 检查项与审计结论

| 检查项 | 风险等级 | 防护实现 | 审计结论 |
|---|---|---|---|
| **水平越权：跨店保存套餐** | HIGH | `AdminComboController.save` 调用 `adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder)` 校验。门店管理员尝试保存其他门店套餐时，立即返回 `4003 (无权限操作此门店)`。 | PASS |
| **水平越权：跨店查看套餐** | MEDIUM | `AdminComboController.getByDishId` 调用 `adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder)` 校验请求者门店权限。 | PASS |
| **数据覆盖漏洞：同名菜品覆盖套餐** | CRITICAL | 数据库迁移引入 `shop_id INT NOT NULL DEFAULT 0`，唯一约束变更为 `uk_combo_dish_shop (dish_id, shop_id)`。`saveComboDefinition` 严格限制删除范围为 `(dish_id, targetShopId)`，阻断全局物理覆盖。 | PASS |
| **SQL 注入 / 越权查询** | LOW | 全部使用 MyBatis-Plus 条件构造器 (`LambdaQueryWrapper`) 参数化绑定，不存在动态拼串注入风险。 | PASS |
| **总部模板污染防护** | MEDIUM | 门店端管理员无权指定 `shop_id = 0` 保存，仅能针对自身管辖门店保存专属套餐配置。 | PASS |

## 3. 自动化用例验证
- `AdminComboStoreIsolationTest.testSaveCombo_CrossStoreForbidden_DeniedByScopeGuard`: 验证非本店管理员跨店提交返回 4003 拦截。
- `AdminComboStoreIsolationTest.testSaveCombo_StoreIsolation_NoOverwrite`: 验证两个门店连续保存套餐，内容完全独立。
