# Implementation Plan: 可复用且隔离的调试环境

## Overview

按照 `docs/debug_environment_spec.md`，在不覆盖现有生产配置和用户未提交改动的前提下，为 Windows 本机提供一次初始化、长期复用的 Spring Boot 调试环境。

## Architecture Decisions

- 复用已安装的 MySQL 8.0 二进制，在 `.local/mysql-debug` 初始化端口 `3307` 的独立实例；不修改现有 `MySQL80:3306` 或其 root 密码。
- 调试环境只能通过显式 `debug` Profile 启动，端口、文件目录、定时任务和第三方配置均由该 Profile 覆盖。
- 本地凭据写入被忽略的 `.env.debug`；仓库只保存无秘密的模板。
- 初始化脚本默认幂等，数据库重置必须显式传参并二次确认。
- 启动脚本在运行应用前校验 JDBC 数据库名，阻止误连 `db_diancan`。

## Dependency Graph

```text
debug Profile + 环境变量约定
              |
              +--> 初始化脚本 --> 独立数据库/本地目录
              |
              +--> 自检脚本 --> 启动脚本 --> 运行态验证
```

## Task List

### Phase 1: 配置隔离基础

- [x] Task 1: 添加 `debug` Profile、环境模板和 Git 忽略规则
- [x] Task 2: 添加配置隔离测试并验证 Profile 覆盖值

### Checkpoint: 配置隔离

- [x] 测试证明调试端口、数据库名、目录和外部调用开关安全
- [x] `.env.debug` 与 `.local/` 不会被 Git 跟踪

### Phase 2: 可复用工具链

- [x] Task 3: 添加通用环境加载和安全校验脚本
- [x] Task 4: 添加幂等初始化脚本与日常启动脚本
- [x] Task 5: 添加使用文档

### Checkpoint: 工具链

- [x] PowerShell 脚本均能通过语法解析
- [x] 缺少凭据、数据库或错误 schema 时快速失败且提示明确

### Phase 3: 本机初始化与端到端验证

- [x] Task 6: 创建调试数据库、账号、目录并导入基线
- [x] Task 7: 编译、运行测试并实际启动 `debug` Profile
- [x] Task 8: 验证端口、Profile、数据库权限和生产隔离

### Checkpoint: Complete

- [x] 一次初始化完成，日常启动只需一个命令
- [x] 调试实例与生产实例使用不同端口、数据目录和账号
- [x] 原生产配置与已有未提交改动未被覆盖

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 当前工作区有大量用户改动 | 高 | 主要新增文件；对 `.gitignore` 只做末尾追加 |
| SQL 基线包含破坏性 `DROP TABLE` | 高 | 仅在确认目标 schema 为 `db_diancan_debug` 后导入 |
| 第三方调用由数据库配置再次开启 | 高 | 调试环境全局关闭 Scheduling，并在文档注明真实联调需显式开启 |
| 现有 MySQL root 密码未知 | 低 | 调试实例使用独立数据目录和自动生成的本地凭据，不依赖现有 root |
| 全量测试受现有未提交代码影响 | 中 | 先运行本次隔离测试，再记录全量测试中与本改动无关的失败 |

## Open Questions

- 无；规格中的方案已由用户确认。
