# Implementation Plan: 独立打包单打印

## Capability and authoritative owners

- Capability: 打包订单在既有厨房单/前台单之外，可按门店规则独立打印一张打包单，并可设计独立模板。
- 场景语义 owner: `PrintScenario`。
- 模板与规则 owner: `PrintingService`、`PrintTemplateEngineImpl`、`PrintDispatcherServiceImpl`。
- 业务触发 owner: `OrderController` 的订单接单打印链路与 `KdsSupplementalPrintService` 的事务后附加打印链路。
- UI owner: 管理端打印设备、打印规则、票据模板与预览模型。

## Architecture decisions

- 新增标准场景 `PACKING`（持久化规则码 `packing`），不新增表或接口。
- 复用现有“场景 → 设备/模板/份数/启停”规则；未配置 `PACKING` 规则时不打印，避免存量门店突然多出票。
- 仅 `PaymentDiningTypeUtil.isTakeOutType(...)` 判定的打包/自提订单触发独立打包单；外卖继续使用 `TAKEOUT`，堂食不触发。
- 打包单与厨房/前台票据独立派发；KDS 模式仍由云端订单提交后的附加打印服务执行，不改变 KDS 权威状态。
- 默认打包单突出取餐码、订单号、餐品数量和备注，不把它伪装成支付凭证。

## Affected-surface map

- Backend domain: `PrintScenario` 内置枚举、显示名与别名归一化。
- Backend service: 系统默认模板初始化、模板元数据、默认 DSL、订单打印派发。
- Persistence: 复用 `t_printing_template`/`t_printing_rule`；启动时幂等补充系统模板，无 schema 变更。
- API contract: 元数据场景数由 10 增至 11；模板/规则/job 场景枚举新增 `PACKING`/`packing`。
- Frontend mapping/state: 打印设备票据类型、规则场景、模板筛选、设计器默认值、预览场景新增打包单。
- UI display: 可选择“打包单”，可创建/筛选模板，可新增并启停独立打印规则。
- KDS: 仅事务提交后的物理打印附加通道增加同一订单的 `PACKING` 派发；权威状态、API、WS、revision 均不变。

## Layer Impact Matrix

| Layer | Classification | Evidence / action |
|---|---|---|
| UI | CHANGE | 新增打包单选项、筛选、标签与预览场景 |
| Interaction | CHANGE | 可新增/启停 `PACKING` 规则并选择独立设备/模板 |
| Frontend State | CHANGE | 静态场景集合和 fallback DSL 增加 `PACKING` |
| API Client | VERIFY_NO_CHANGE | 继续使用现有模板、规则与预览接口 |
| Request Contract | CHANGE | `scenario` 合法标准码新增 `PACKING`/`packing` |
| Controller | CHANGE | 打包订单接单打印链路额外派发 `PACKING` |
| Service | CHANGE | 模板元数据、初始化与 KDS 附加打印派发扩展 |
| Domain | CHANGE | 新增内置打印场景 `PACKING` |
| Persistence | VERIFY_NO_CHANGE | 现有字符串场景列和通用规则/模板表可直接承载 |
| Response Contract | CHANGE | 模板元数据与打印流水可返回新场景 |
| Frontend Mapping | CHANGE | `PACKING` 映射为打包单而不是未知/结账单 |
| UI Display | CHANGE | 管理端完整显示打包单配置与模板 |

## Contract Delta

- Added enum value: `PACKING`（请求/模板 DSL/元数据）与 `packing`（规则、job 标准码）。
- `GET /admin/printing/templates/meta`: `scenarios[]` 新增打包单，`parametersByScenario.PACKING` 复用订单变量。
- `GET/POST/PUT /admin/printing/templates`: `scenario` 支持 `PACKING`。
- `PUT /admin/printing/rules`: `rules[].scenario` 支持 `packing`。
- `GET /admin/printing/jobs`: `jobType` 可能返回 `packing`，`scenarioName` 为“打包单”。
- No route, auth, pagination, schema, or error-model change.

## Verifiable tasks

1. RED: 添加后端场景、默认模板、元数据和打包订单独立派发测试。
2. GREEN: 实现 `PACKING` 场景、模板及普通/KDS 打印触发。
3. RED/GREEN: 添加管理端模型与界面契约测试并实现最小 UI 适配。
4. 同步 `docs/openapi.yaml` 和 `docs/API.md`。
5. 运行定向测试、静态分析、完整 Maven 打包，检查工作区差异。

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| 存量门店意外多打一张 | `PACKING` 无规则即不出票，完全 opt-in |
| 打包单失败阻塞 KDS 权威接单 | KDS 中保持附加打印语义，不影响已提交业务状态 |
| 外卖与打包混淆 | 只用 `isTakeOutType`，外卖仍走 `TAKEOUT` |
| 活跃脏工作区覆盖他人修改 | 只做定点 patch，不格式化或回退无关文件 |

