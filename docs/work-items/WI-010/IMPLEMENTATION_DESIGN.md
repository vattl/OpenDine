# Implementation Design — WI-010

## Root Fix / Owner

根因是并行分支未持续汇入共同基线。本次由专用本地 integration 分支承载统一树，以显式 merge commit 保存来源关系，并对不安全分支使用保留当前树的历史接入策略。

## Merge Strategy

1. 先提交当前已验证脏工作树为恢复点。
2. 对 KDS 与报表分支使用 `--no-ff --no-commit`，逐项裁决冲突并在每个切片后验证。
3. KDS 冲突以 KDS-CA-1.3、OpenAPI 以及云端唯一权威不变量为准。
4. 外卖分支仅剩 `.local` 运行物差异，使用 `ours` 内容策略建立祖先关系，不引入其树内容。
5. 最终确认三条分支均为祖先、敏感路径不存在，并运行完整验证。

## Preservation Rules

- 保留 WI-007 门店级稳定排序。
- 保留 WI-008 `admin:super` 自定义账单时间范围。
- 保留 WI-009 加菜不改 `order_time`。
- 已应用数据库迁移只通过更高版本纠正，不覆写历史迁移真源。

## Verification Strategy

- 合并图：`git merge-base --is-ancestor <branch> HEAD`。
- 敏感树：`git ls-tree -r --name-only HEAD` 检查 `.local`、私钥、密码。
- 契约：OpenAPI/API 文档 diff 与相关契约测试。
- 行为：KDS、报表及 WI-007/008/009 专项测试。
- 总回归：完整 Maven test；API 变化后执行 `mvn clean package -DskipTests`。

## Rollback

所有操作保留在未推送的 integration 分支；每个切片独立 merge commit，可通过创建新候选分支并选择已通过切片恢复，不改写其他分支历史。
