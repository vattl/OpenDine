# D001 — 打印流水场景统一标识

Parent Work: `/change`
Status: VERIFIED
Created: 2026-09-02

## Intent

将新建打印流水的 `job_type` 统一为可读、稳定的小写场景码；覆盖十个内置场景，并允许未来以受限机器码增加自定义场景。

## Current → Target

- 当前：支付结账仍以 `order` 入流水，KDS 传菜以 `serve` 入流水；模板层才将 `serve` 转为 `EXPEDITE`。规则、模板、流水的标识不一致。
- 目标：结账流水为 `checkout`，传菜单流水为 `expedite`；十个内置场景均有唯一标准码。规则、模板、流水和响应均通过同一归一化入口处理；未知但合法的机器码作为自定义场景保留。

## Diff

| ID | Element | Current | Target | Operation | Risk |
|---|---|---|---|---|---|
| D1 | `PrintScenario` | 别名与模板标准码混用 | 统一场景注册、归一化、显示名与兼容查找码 | REPLACE | Medium |
| D2 | 调度与业务触发 | `order`/`serve` 写入流水 | 写入标准码，旧规则码仅回退匹配 | MODIFY | Medium |
| D3 | 流水查询响应 | 仅输出原始 `jobType` | 输出标准 `jobType`、名称和自定义标记；保留旧原始码 | MIGRATE | Low |
| D4 | 设备票据类型/规则校验 | 固定六场景枚举、规则不归一化 | 覆盖十场景并接受合法自定义码 | MODIFY | Low |
| D5 | 数据库与接口文档 | `job_type` 含旧示例 | 记录标准码与历史兼容语义 | MODIFY | Low |

## Compatibility

- 既有 `order`、`receipt`、`bill` 和 `serve` 等规则可作为标准场景无规则时的回退，不自动改写历史行。
- 历史流水不做不可逆更新：查询时规范化，并以 `legacyJobType` 暴露原值。

## Negative Acceptance Criteria

- 新增结账和传菜流水不得再分别写入 `order`、`serve`。
- 规则保存不得继续持久化内置别名。

## Verification

| ID | Status | Evidence |
|---|---|---|
| D1 | PASS | `PrintScenarioTest` 覆盖十类内置码、别名和自定义码。 |
| D2 | PASS | `PrintDispatcherServiceTest` 与全生命周期模拟确认结账写 `checkout`、传菜写 `expedite`。 |
| D3 | PASS | `jobSummary` 输出标准 `jobType`、`scenarioName`、`customScenario` 和历史 `legacyJobType`。 |
| D4 | PASS | 规则、模板与设备票据类型均通过统一归一化，模板单测覆盖 `pickup_notice`。 |
| D5 | PASS | OpenAPI、API 手册及数据库建表说明已同步。 |

## Final State

- Target State Match: YES
- Legacy Remaining: YES，仅限历史流水回显和旧规则无标准配置时的只读回退。
- Unexpected Active Behavior: NO
- Validation: `mvnw.cmd test`（632 run, 0 failures, 0 errors, 1 skipped）；`mvnw.cmd clean package -DskipTests`（BUILD SUCCESS，生成 `target/diancan-0.0.1-SNAPSHOT.jar`）。
