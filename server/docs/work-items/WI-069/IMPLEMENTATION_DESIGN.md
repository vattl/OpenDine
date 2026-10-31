# Implementation Design — WI-069

## Route

- Work type: BUG
- Complexity: TRIVIAL
- UI impact: NONE
- Contract impact: NONE
- Baseline impact: LEVEL_0

## Root Fix / Owner

根因位于应用级 MyBatis 扫描清单。把 `com.lanf.ai.mapper` 加入 `Application.@MapperScan`，由统一基础设施注册全部 AI Mapper；不在各 Service 中增加可选注入或手工 Bean。

## Verification Strategy

- 反射读取 `MapperScan.value` 的小型回归测试，修复前失败、修复后通过。
- Maven 编译/打包。
- 使用最小启动配置运行 JAR，确认不再出现 `DishFoodProfileMapper` 缺失。

## Compatibility

仅补全缺失 Bean 注册，无 API、数据或行为契约变更。
