# WI-003 Plan

## Impact Map

| Surface | Classification | Evidence / action |
|---|---|---|
| Cloud authority | AFFECTED | `KdsWorkflowV2Service` 是四条 V2 数据链的统一组装入口 |
| Persistence | VERIFIED_UNAFFECTED | 复用既有 `t_dish` 与 `t_dish_shop` 列，无 DDL |
| Duration resolution | AFFECTED | `KdsDishServingDurationService` 增加 base/override 批量值对象，同时保持 SLA 秒数 API |
| Bootstrap | AFFECTED | queues 与 order_details 注入时长字段 |
| Commands | AFFECTED | patches.line 与附带 order_details 注入时长字段 |
| WebSocket / changes | AFFECTED | 同一持久化 event envelope 携带 fields；changes 原样读取 |
| LAN proxy | VERIFIED_UNAFFECTED | KDS-CA-1.3 要求透明转发云端正文 |
| KDS client | VERIFIED_UNAFFECTED | 已有 `serving_duration_override` 优先、base 回退逻辑与测试 |
| Admin/POS | VERIFIED_UNAFFECTED | 门店菜品覆盖写入路径与字段已存在 |
| API docs | AFFECTED | OpenAPI schemas、API.md 与版本说明同步 |
| Tests / release | AFFECTED | 服务、V2 contract/push/bootstrap、OpenAPI、完整 JAR |

## Implementation Design

1. 在既有时长服务中增加不可变 `ServingDuration` 值对象，单次批量读取菜品与门店关系，分别保留 base 和 override；既有秒数解析继续使用 override 优先并保持 fallback 语义。
2. V2 服务在每个批次入口预取 detail→duration map，行与 order_details 只做内存映射；公开单行方法保留兼容 fallback。
3. 合法性规则：base 非正数/缺失回退 10；override 非正数视为未配置并返回 null；Java `Integer` 保证 JSON 整数类型。
4. WebSocket 信封与 changes 共用持久化 envelope，不复制第二套逻辑。
5. OpenAPI 增加 V2 order detail schema，并在 bootstrap/event/command 响应中显式引用。

## Vertical Slices

1. RED：解析服务与 V2 行/事件契约测试先失败。
2. GREEN：批量解析与四条链路统一组装。
3. CONTRACT：OpenAPI/API.md 同步并解析验证。
4. VERIFY：定向测试、KDS 回归、review、`mvn clean package -DskipTests`。

