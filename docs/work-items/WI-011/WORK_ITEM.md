# WORK ITEM — WI-011

## Request

完成剩余两条跨应用遗留分支的历史接入，使所有本地/远端开发分支统一到同一本地集成基线。

## Type

MAINTENANCE / INTEGRATION

## State

ACCEPTED

## Requirement Contract

### Goal

接入 `origin/feat/kds-dual-mode-architecture-pos` 与 `origin/feature/love-food-theme` 的 Git 历史，同时保持当前服务端仓库的边界和更新实现。

### Current behavior

两条分支从 2026-05 的旧基线分叉，tip 分别停在 2026-09-16 和 2026-08-23；当前基线在 2026-09-04 已明确删除多余的管理端和小程序目录，并在其后继续演进服务端 KDS-CA-1.3。

### Target behavior

- 两条远端分支都成为 integration 分支祖先。
- 不恢复已明确删除的 `admin_panel_flutter`、`admin_mini`、`miniprogram` 等跨应用目录。
- 不以旧服务端树覆盖当前 KDS-CA-1.3 与已验收修复。

### Must preserve

- 当前仓库仅保留既定 server/workstreams 边界。
- 当前服务端内容树逐字节不因遗留分支接入而改变。
- 不推送、不更改远端默认分支、不删除分支。

### Acceptance criteria

- [x] 两条分支均为当前集成 HEAD 的祖先。
- [x] 合并前后内容树哈希相同。
- [x] 被删除的跨应用目录没有重新出现。
- [x] 服务端完整回归与 JAR 状态仍有效。

### Open product questions

NONE。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 记录合并前树哈希并接入 POS/KDS 遗留分支历史。
- [x] T02 接入 love-food 遗留分支历史。
- [x] T03 核对祖先、树哈希、目录边界与最终分支覆盖。

## Verification Evidence

执行后写入 `COMPLETION_EVIDENCE.md`。

## Review

PASS：全部本地/远端 ref 已成为统一基线祖先，内容树与仓库边界保持不变。

## Acceptance Decision

ACCEPTED（本地历史统一，不代表远端推送或发布）。

## Consumer Handoffs

NONE；不改变运行内容或接口契约。

## Integration / Release

本地 integration 分支，不推送、不部署。

## Business Invariants

- INV-REPO-BOUNDARY-01：已从服务端仓库移除的跨应用目录不得被旧分支复活。
- INV-BASELINE-01：历史接入不得改变当前已验证内容树。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-011/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-011/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`
