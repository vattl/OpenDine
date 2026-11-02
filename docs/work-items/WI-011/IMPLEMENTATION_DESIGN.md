# Implementation Design — WI-011

## Root Fix / Owner

用 merge commit 统一提交图，而不是把旧 monorepo 内容重新引入当前 server 基线。

## Strategy

- 记录合并前 `HEAD^{tree}`。
- 对两条分支分别执行 `--no-ff -s ours`。
- 验证两条分支成为祖先且最终 `HEAD^{tree}` 与合并前一致。
- 验证 `admin_panel_flutter`、`admin_mini`、`miniprogram` 不在根树。

## Verification Strategy

使用 `git merge-base --is-ancestor`、`git rev-parse HEAD^{tree}` 与 `git ls-tree` 提供证据；复用 WI-010 刚完成的 1245 项回归和 JAR 打包，因为内容树保持相同。
