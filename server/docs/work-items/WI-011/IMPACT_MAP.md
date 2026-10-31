# Impact Map — WI-011

## Authoritative Owner

当前 integration 分支内容树及 `badb30a` 的仓库边界决策是权威；遗留分支仅作为历史来源接入。

## Change Propagation Path

```text
遗留分支 tip → ours merge commit → ancestry unified → content tree unchanged
```

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 不编辑或恢复生产 UI；旧 UI 目录已被权威基线删除 |
| API Client | VERIFIED_UNAFFECTED | 内容树不变 |
| Backend/Domain | VERIFIED_UNAFFECTED | 内容树不变 |
| Persistence | VERIFIED_UNAFFECTED | 内容树不变 |
| Config/Security | VERIFIED_UNAFFECTED | 不恢复旧配置或凭据 |
| Runtime/NFR | VERIFIED_UNAFFECTED | 仅改变 Git ancestry |
| Tests | AFFECTED | 验证树哈希、边界与祖先关系 |

## UI Semantic Impact

NONE。被比较的 UI 属于已从本仓库删除的遗留应用，不是当前生产 UI 编辑。

## Risks

普通内容合并会恢复数千个已删除文件并覆盖较新服务端；必须使用保留当前树的 merge strategy。
