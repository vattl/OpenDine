# Impact Map — WI-010

## Authoritative Owner

目标 Git 树 `integration/unified-baseline-20261012` 是本次本地统一候选；业务权威仍由各领域 owner 负责：KDS V2 服务、报表聚合服务和现有订单/菜单服务。

## Change Propagation Path

```text
分支提交历史
→ 三方合并与冲突裁决
→ API/数据库/领域实现/测试统一树
→ Maven 回归与可运行 JAR
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| KDS V2 客户端 | 命令账本/revision 契约消费者 | AFFECTED | 契约随分支合并 | KDS 分支差异与 KDS-CA-1.3 |
| 管理端报表 | 跨日营业窗口消费者 | AFFECTED | 契约随分支合并 | C012 分支差异 |
| 小程序/收银订单 | 既有外卖与订单能力 | VERIFIED_UNAFFECTED | 保留当前基线 | 外卖分支非 `.local` 差异为 0 |
| WI-007/008/009 | 已验收修复 | AFFECTED | 必须回归 | 对应 Work Item 测试 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 本工作项只合并服务端分支；UI 分支进入 WI-011 |
| Interaction | VERIFIED_UNAFFECTED | 不改变客户端交互 |
| Frontend State | VERIFIED_UNAFFECTED | 本工作项不编辑前端树 |
| API Client | AFFECTED | KDS/报表消费者依赖契约，需契约回归 |
| Request Contract | AFFECTED | KDS revision 与报表查询契约 |
| Backend/Domain | AFFECTED | KDS、报表与订单代码合并 |
| Persistence | AFFECTED | KDS ledger/event/revision 与报表索引迁移 |
| Response Contract | AFFECTED | API 文档必须与实现统一 |
| Jobs/Events/Integrations | AFFECTED | KDS 事件连续性和复制桥接 |
| Config/Security | AFFECTED | 排除 `.local` 凭据和运行物 |
| Runtime/NFR | AFFECTED | 幂等、并发和跨日聚合正确性 |
| Tests | AFFECTED | 专项与全量 Maven 回归 |

## Duplicate Logic / Patch Smells

外卖分支的业务树已经被当前历史吸收，剩余唯一内容为不应版本化的本机运行数据；使用保留当前树的 merge commit 接入历史，避免重新引入凭据和数据库文件。

## Contract Delta Summary

整合既有分支契约，不设计新的平行接口。冲突裁决以当前 OpenAPI、KDS-CA-1.3 和较新的已验收业务不变量为准。

## UI Semantic Impact

NONE。本工作项明确不接入包含 UI 生产文件的分支。

## Risks

- 老分支可能覆盖较新的订单时间、门店排序或权限修复。
- KDS 历史迁移可能与当前云端唯一权威迁移重叠。
- API 文档冲突若机械选择一侧会造成契约回退。
- 外卖分支含真实本机运行物和敏感材料，必须排除。
