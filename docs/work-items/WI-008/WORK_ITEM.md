# WORK ITEM — WI-008

## Request

收银账单列表默认仅返回当前门店未结账订单及最近 3 小时订单，并支持 `admin:super` 权限管理员按自定义时间范围查询。

## Type

CHANGE

## State

ACCEPTED

## Requirement Contract

### Goal

限制普通收银账单历史暴露范围，同时为超级管理员提供受控的历史时间区间查询能力。

### Current behavior

`GET /cashier/order/today` 默认返回当前活动营业班次 24 小时内的订单，`date` 可由普通 `cashier:operate` 调用者指定。

### Target behavior

- 不传自定义时间时，返回当前门店全部 `unsettled` 订单，以及 `order_time` 位于最近 3 小时内的其他订单。
- 传 `startTime` 和 `endTime` 时，按当前门店、`order_time` 闭区间查询；两者必须同时提供，最大跨度 31 天。
- 旧 `date` 参数保留为营业班次日期兼容入口，但与自定义时间一样要求 `admin:super`。
- `date` 与 `startTime/endTime` 不得混用。
- 自定义时间权限由服务端按当前 JWT 管理员 ID 的精确权限码 `admin:super` 强制校验。

### Must preserve

- 门店上下文及跨店拒绝逻辑不变。
- `transac_status` 筛选、响应 `R` 结构及 `list` 字段不变。
- `/cashier/order/today` 基础接口权限仍为 `cashier:operate`；仅自定义时间能力增加条件权限。

### Acceptance criteria

- [x] 普通收银请求只覆盖未结账订单和最近 3 小时订单。
- [x] 无 `admin:super` 的调用者传任一自定义时间参数均返回 403，且不查询数据库。
- [x] `admin:super` 可使用合法的 `startTime/endTime` 查询当前门店订单。
- [x] 部分时间参数、格式错误、倒序、超过 31 天及与 `date` 混用均明确返回 400。
- [x] 旧 `date` 查询仅 `admin:super` 可用。
- [x] OpenAPI、API.md、权限迁移与可运行 JAR 同步完成。

### Open product questions

NONE。自定义区间采用现有项目格式 `yyyy-MM-dd HH:mm:ss`、`yyyy-MM-dd HH:mm`、ISO `T` 或日期；结束时间含边界。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 以失败测试固化默认 3 小时窗口、自定义权限及参数边界。
- [x] T02 实现控制器条件授权与查询窗口。
- [x] T03 注册并仅向 `super_admin` 角色授予 `admin:super` 权限。
- [x] T04 同步 API 文档并完成回归、打包、安全审查和接受门禁。

## Verification Evidence

见 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

PASS：完成 correctness/security/performance/maintainability/deployment 五轴复核，无 HIGH/CRITICAL 未决项。

## Acceptance Decision

ACCEPTED（工程验收，不代表已集成或已发布）。

## Consumer Handoffs

见 `CONTRACT_DELTA.md`。客户端可选增加超级管理员时间筛选；普通调用无需修改。

## Integration / Release

目标状态为 ACCEPTED；部署前先执行权限迁移，发布不在本 Work Item 授权范围。

## Related IDs

Workstream: cashier-bill-custom-range
UI: NONE
Capability: cashier-bill-query
Commits: PENDING

## Business Invariants

- INV-BILL-01：所有账单查询必须绑定鉴权解析后的当前门店。
- INV-BILL-02：普通收银不得读取默认窗口以外的历史账单。
- INV-BILL-03：自定义历史范围必须由服务端验证 `admin:super`。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-008/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-008/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`
