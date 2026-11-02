# Impact Map — WI-034

## Authoritative Owner

- 运行时字段模型：`src/main/java/com/lanf/entity/Combo.java`。
- 正式增量迁移：`src/main/resources/db/migration`。
- 全量建库基线：`docs/db_diancan.sql`。
- 增量同步基线：`docs/db_schema_additive_sync.sql`。

## Failure Path

```text
GET /admin/dish/list
→ DishController.attachComboDefinitions
→ ComboMealServiceImpl.getByDishId
→ ComboMapper.selectOne
→ MyBatis-Plus 按 Combo 全字段生成 SELECT
→ 生产 t_combo 缺少 limit_per_order
→ BadSqlGrammarException
```

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 无界面代码或交互变化 |
| API Contract | VERIFIED_UNAFFECTED | 路径、字段和状态语义不变 |
| Controller/Service | VERIFIED_UNAFFECTED | 堆栈只暴露持久化结构缺失，业务代码无需降级绕过 |
| Entity/Mapper | AFFECTED_EXISTING | 当前未提交实现已经声明并查询新字段 |
| Persistence | AFFECTED | 缺少正式迁移及基线同步 |
| Data | PRESERVED | 仅 ADD COLUMN，安全默认值 |
| Deployment | AFFECTED | 必须先迁移、后启动新 JAR |
| Tests | AFFECTED | 需要迁移完整性与幂等保护测试 |

## Material Unknowns

0。错误 SQL、实体字段、现有表定义和迁移目录均已核对。

## Risks

- 多列 DDL 在大表上可能持有元数据锁；应在低峰执行并先备份。
- 若只修复首个缺失列，查询会在下一缺失列继续失败，因此必须一次补齐全部字段。
- 应用不会自动运行这些 SQL 资源；发布流程必须显式执行 V034。
