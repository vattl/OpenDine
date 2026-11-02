# Impact Map — WI-058

## Authoritative Owner

- Machine-readable business invariant owner: `.ai/project/business-rules.json`
- Human-readable baseline view: `docs/project/BUSINESS_RULES.md`
- Governance roadmap owner: `docs/project/BACKEND_GOVERNANCE_ROADMAP.md`
- Generated contract inventory owner: `scripts/governance/generate_backend_contract_inventory.py`

## Change Propagation Path

```text
审计方案
→ WI-058 Requirement Contract
→ machine-readable invariant baseline
→ human-readable business rules / governance roadmap
→ deterministic inventory generator
→ versioned backend contract inventory
→ future Work Item ready/accept checks
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 后续后端 Work Item | 读取不变量与治理顺序 | AFFECTED | YES | 审计方案阶段 0 |
| 开发/评审人员 | 阅读 Markdown 基线 | AFFECTED | YES | `docs/project/BUSINESS_RULES.md` |
| CI/本地门禁 | 执行一致性与清单校验 | AFFECTED | YES | 新增治理脚本 |
| 收银端/管理端/KDS 客户端 | 运行时 API 消费者 | VERIFIED_UNAFFECTED | NO | 无生产代码/API 修改 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 不修改 UI |
| Interaction | NOT_APPLICABLE | 不修改用户交互 |
| Frontend State | VERIFIED_UNAFFECTED | 不修改运行时数据 |
| API Client | VERIFIED_UNAFFECTED | 不修改 API |
| Request Contract | VERIFIED_UNAFFECTED | 只生成现状清单 |
| Backend/Domain | VERIFIED_UNAFFECTED | 不改生产类 |
| Persistence | VERIFIED_UNAFFECTED | 不改迁移/表 |
| Response Contract | VERIFIED_UNAFFECTED | 不改响应 |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 不改任务/事件 |
| Config/Security | AFFECTED | 增加审批安全不变量与后续路线 |
| Runtime/NFR | VERIFIED_UNAFFECTED | 脚本只在开发/CI 运行 |
| Tests | AFFECTED | 增加基线一致性校验 |

## Duplicate Logic / Patch Smells

- `business-rules.json` 与 `BUSINESS_RULES.md` 当前互相矛盾。
- 契约事实分散在 Controller、`ApiPermissionMapping`、OpenAPI 与实体常量中；本项只建立可审计快照，不宣布其为运行时新权威。

## Contract Delta Summary

无运行时契约增删改；新增的是开发治理清单和校验命令。

## UI Semantic Impact

NOT_APPLICABLE

## Risks

- 静态扫描不能完整解释 Spring 组合注解；清单必须标注来源和局限。
- 自动生成文件若未纳入 `--check`，仍可能漂移。
- 新不变量是后续变更约束，不得误称为当前所有链路已满足。
