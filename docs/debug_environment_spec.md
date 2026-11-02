# 调试环境一次性搭建规格

## 目标

为本项目提供一套 Windows 本地调试环境：首次执行初始化脚本后，后续只需执行一个启动命令即可运行；调试环境使用独立数据库、端口、文件目录和第三方服务配置，不连接或修改生产数据。

## 技术现状

- Spring Boot 2.3.2、Java 8、Maven Wrapper。
- 本机已安装 MySQL 8.0 程序并运行生产/原实例 `MySQL80:3306`，未安装 Docker 和 Redis。
- 当前默认 `application.yml` 包含线上风格配置，生产启动行为必须保持兼容。
- 数据库基线位于 `docs/db_diancan.sql`。

## 设计

1. 新增 Spring Profile `debug`，通过 `application-debug.yml` 覆盖以下配置：
   - HTTP 端口使用 `18080`，避免与现有 `8080` 服务冲突。
   - 使用独立 MySQL 数据目录 `.local/mysql-debug/data` 和端口 `3307`；数据库固定为 `db_diancan_debug`，账号仅拥有该 schema 权限。
   - 上传和二维码文件写入仓库内被忽略的 `.local/debug/uploads/`。
   - `app.public-base-url` 使用 `http://127.0.0.1:18080`。
   - 关闭真省钱自动发单、配送同步、备货定时任务和 Spring Scheduling，防止调试时触发外部副作用。
   - 微信、AI、打印、地图等外部服务默认使用空白调试凭据；需要联调时只能在本地环境文件中显式提供。
2. 新增 `.env.debug.example`，首次初始化时复制为被 Git 忽略的 `.env.debug`；真实调试密码不得提交。
3. 新增 `scripts/setup-debug.ps1`：
   - 检查 Java 8、Maven Wrapper、MySQL 客户端和服务端程序。
   - 首次初始化独立 MySQL 数据目录，自动生成本地凭据，创建数据库与最小权限账号，并导入基线及所需迁移。
   - 创建本地上传目录。
   - 预下载 Maven 依赖并执行一次编译。
   - 默认幂等：已初始化时不删除、不重建现有调试数据；仅显式 `-ResetDatabase` 才允许重置。
4. 新增 `scripts/start-debug.ps1`：
   - 加载 `.env.debug`。
   - 强制激活 `debug` Profile。
   - 启动前检查当前 JDBC URL 必须包含 `db_diancan_debug`，否则拒绝启动。
   - 使用 Maven Wrapper启动应用。
5. 新增 `scripts/check-debug-env.ps1`，以不启动外部业务调用的方式验证 Profile、数据库隔离和必要目录。
6. 新增使用文档，说明首次初始化、日常启动、数据库重置及生产启动方式。

## 命令

```powershell
# 首次且仅需一次（无需现有 MySQL root 密码）
.\scripts\setup-debug.ps1

# 后续日常调试
.\scripts\start-debug.ps1

# 环境自检
.\scripts\check-debug-env.ps1

# 显式重置调试数据库（破坏性操作，脚本需二次确认）
.\scripts\setup-debug.ps1 -ResetDatabase

# 生产仍沿用现有部署命令，不自动激活 debug Profile
.\mvnw.cmd spring-boot:run -Dspring-boot.run.profiles=prod
```

## 文件范围

- `src/main/resources/application-debug.yml`：调试 Profile。
- `.env.debug.example`：可提交的本地变量模板。
- `.gitignore`：忽略 `.env.debug` 与 `.local/`。
- `scripts/setup-debug.ps1`：一次性初始化。
- `scripts/start-debug.ps1`：日常启动。
- `scripts/check-debug-env.ps1`：隔离自检。
- `docs/debug_environment.md`：操作说明。
- `src/test/...`：仅在需要验证 Profile 行为时新增测试。

## 测试策略

- 脚本静态验证：PowerShell 解析无错误，缺少依赖或配置时给出明确错误。
- 配置验证：`debug` Profile 解析后的 JDBC URL、端口、目录和外部服务开关符合本规格。
- 数据隔离验证：调试实例只监听 `127.0.0.1:3307`；调试账号能访问 `db_diancan_debug`，不能访问 `db_diancan`。
- 构建验证：`.\mvnw.cmd -DskipTests compile` 成功。
- 回归验证：运行现有 Maven 测试；若全量测试受已有工作区改动影响，记录与本次改动无关的失败。
- 运行验证：应用在 `18080` 启动，日志显示激活 `debug` Profile，且没有连接生产 schema。

## 边界

- 始终：使用独立 schema 和账号；本地密钥文件进入 Git 忽略；启动前执行防误连检查。
- 需确认：修改现有生产配置、安装 Docker/Redis、变更现有 `MySQL80:3306`、轮换已提交的线上密钥。
- 禁止：在脚本中硬编码真实密码；自动删除 `db_diancan`；调试默认调用支付、配送、打印或消息推送服务。

## 验收标准

- 首次初始化完成后，关闭终端或重启电脑不会丢失调试数据库和配置。
- 日常只运行 `.\scripts\start-debug.ps1` 即可启动。
- 调试服务固定监听 `127.0.0.1:18080`（除非本地环境文件显式覆盖）。
- 调试数据库位于独立实例 `127.0.0.1:3307/db_diancan_debug`，最小权限账号无法访问生产实例。
- 调试上传文件只写入 `.local/debug/`。
- 调试默认不会触发定时任务或第三方真实业务调用。
- `.env.debug` 和 `.local/` 不会被 Git 跟踪。
- 原有生产启动配置和部署路径不被本次改造覆盖。

## 已确认决策

- 使用本机已安装的 MySQL 8.0 二进制创建端口 `3307` 的独立调试实例，不修改现有 root 密码。
- 调试 HTTP 端口使用 `18080`。
- “清理并轮换当前已提交到 `application.yml` 的生产密钥”保留为后续独立安全任务。
