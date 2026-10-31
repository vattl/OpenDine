# WORK ITEM — WI-069

## Request

修复应用启动时 `DishFoodProfileMapper` 无法注册导致 AI MCP 依赖链启动失败。

## Type

BUG / CONFIGURATION / STARTUP

## State

ACCEPTED

## Requirement Contract

### Goal

让 `com.lanf.ai.mapper` 中的 MyBatis Mapper 进入 Spring 应用上下文，使 AI 服务依赖链可正常装配。

### Current behavior

`Application` 使用显式 `@MapperScan` 包清单，但遗漏 `com.lanf.ai.mapper`，启动时报 `NoSuchBeanDefinitionException`。

### Target behavior

统一 Mapper 扫描入口包含 `com.lanf.ai.mapper`，所有 AI Mapper 按与其他模块相同的方式注册。

### Acceptance criteria

- [x] 回归测试能在修复前复现扫描包缺失。
- [x] `@MapperScan` 包含 `com.lanf.ai.mapper`。
- [x] 应用上下文不再因 AI Mapper 缺失而失败。
- [x] 专项测试、完整打包通过；JAR 启动已越过 AI Mapper 装配并到达数据库/JWT 环境配置门禁。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 添加 Mapper 扫描回归测试并确认 RED。
- [x] T02 修复统一扫描配置并确认 GREEN。
- [x] T03 打包和启动冒烟验证。

## Acceptance Decision

ACCEPTED：原始 Mapper 缺失启动故障已修复。未把当前终端缺失数据库密码和 JWT 密钥误报为本缺陷。

## Business Invariants

- Spring 应用必须注册所有生产 Mapper；不得通过可选注入掩盖必需持久层能力。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-069/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-069/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none; executable gate pending.

## Completion Level

ACCEPTED
