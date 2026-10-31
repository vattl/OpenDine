# Backend Capability Request — BCR-DAILY-SEQUENCE-001

- Work Item: WI-067
- Status: IMPLEMENTATION_PLANNED
- Owner: server / DailyCloseServiceImpl
- Target Delivery: WI-067 backend slices T01-T03
- Verification Evidence: PENDING until implementation

## Business / UI Need

日结中心必须获得服务端权威的最早待结营业日，并且所有写入口强制按该日期顺序执行。

## Current Backend Capability

现有 precheck/settle 支持可选 `stat_date`，但缺省取当前活动营业日且不检查更早缺口。

## Gap Analysis

| Need | Existing Support | Gap | Proposed Action |
|---|---|---|---|
| 权威待结日 | 无 | 客户端自行算日 | 服务端基于快照序列计算 next |
| 积压提示 | 无 | UI 不知遗漏天数 | precheck 增加 pending 字段 |
| 跳日拒绝 | 无 | settle 可直接成功 | 事务内 409 硬拒绝 |
| 历史补结稳定性 | 部分 | 全局钱箱/水位污染 | 按目标营业日/窗口过滤 |

## Proposed Contract

- Endpoint/interface: `/admin/daily/pre-check`, `/admin/daily/settle`
- Method/event: GET / POST
- Request: precheck 可不传 `stat_date`；settle 传 precheck 返回的 `stat_date`。
- Response: 增加权威日期和积压字段。
- Error/validation semantics: 跳日返回 409 `DAILY_CLOSE_OUT_OF_SEQUENCE`，不可 force。

## Why Existing API Is Insufficient

现有接口把日期选择权交给客户端，无法跨客户端保证财务顺序。

## Expected Backend Impact

- Controller/interface: `AdminDailyController`
- DTO/schema: Map response / OpenAPI schema fields
- Domain/service: `DailyCloseServiceImpl`
- Persistence/query: `DailyCloseSnapshotMapper` 及窗口水位查询
- OpenAPI/docs: required
- Tests: service/controller regression

## Compatibility

成功响应加字段；错误语义收紧。旧消费者必须停止以本机时钟构造日结日期。

## Verification Criteria

S01-S13 全部通过，后端 capability 状态升级为 VERIFIED。
