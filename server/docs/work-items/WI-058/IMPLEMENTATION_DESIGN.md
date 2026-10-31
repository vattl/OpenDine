# Implementation Design — WI-058

## Root Fix / Owner

以 `.ai/project/business-rules.json` 作为唯一机器可读不变量源；由校验脚本检查人类文档包含同一组 ID，并从代码/契约生成后端契约清单。根因是耐久基线存在双写冲突且缺乏漂移检查。

## Why this location

`.ai/project` 是仓库既有 Project Baseline；`docs/project` 面向人类评审；`scripts/governance` 提供不进入运行时的确定性维护工具，职责边界清晰。

## End-to-End Change

### Backend

不修改运行时代码。新增开发期扫描/校验脚本。

### Frontend

不修改；后续任何契约变化由对应 Work Item 单独 handoff。

### UI / Interaction

NOT_APPLICABLE

### Data / Persistence

不修改数据库。JSON/Markdown 是版本库基线数据。

### Interfaces / Contracts

从 `docs/openapi.yaml`、Java Controller 注解、`ApiPermissionMapping`、`ApiException`/`R.error` 调用和状态常量生成审计清单。清单是现状快照，不替代 OpenAPI 或运行时权限权威。

### Jobs / Events / Integrations

不受影响。

## Preserve / Compatibility

保持所有 API 和行为不变。旧不变量 ID 不重命名。规则以 `ENFORCED`/`TARGET` 区分当前已证实事实与待落地约束，禁止把路线目标伪报为当前能力。

## API Consumer Migration / Handoff

NOT_APPLICABLE：无 API delta。

## Failure / Boundary Behavior

- JSON 解析失败、Markdown 缺少任一不变量 ID、生成清单与提交版本不一致时脚本非零退出。
- 扫描结果排序稳定，避免无意义 diff。
- 扫描只覆盖静态可识别文本，并在清单中披露限制。

## Runtime / Performance / Reliability

脚本仅开发/CI 执行；不得进入应用启动路径。

## Security / Permissions

本项不改变权限，只固化 `INV-APPROVAL-001` 和权限治理后续切片。生成清单不得输出密钥、凭据或请求数据。

## UI Design Track

NOT_APPLICABLE

## Vertical Slice Plan

1. 先增加会因当前双基线矛盾而失败的校验测试。
2. 更新 JSON 与 Markdown，使不变量集合一致。
3. 增加治理路线、兼容策略与生成的契约清单。
4. 运行校验、目标测试、独立 diff 评审与 accept gate。

## Verification Strategy

- `python scripts/governance/generate_backend_contract_inventory.py --check`
- `python scripts/governance/validate_business_rules.py`
- `python .ai/scripts/gate.py work --work-item docs/work-items/WI-058 --phase ready|accept`
- `./mvnw.cmd test` 中与基线/权限相关的现有测试（Windows）。

## Rollback / Recovery

本项全部是版本控制内文档与开发脚本，可按文件回退；不涉及运行态数据恢复。
