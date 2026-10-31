# 调试环境实施任务

## Task 1: 添加调试配置基础

**Description:** 创建安全默认的 `debug` Profile、无秘密环境模板和本地文件忽略规则。

**Acceptance criteria:**
- [x] JDBC URL 只指向 `db_diancan_debug`，默认端口为 `18080`
- [x] 定时任务和外部业务集成默认关闭
- [x] `.env.debug` 与 `.local/` 被 Git 忽略

**Verification:** 检查 Spring 配置解析结果与 `git check-ignore`。

**Dependencies:** None

**Files likely touched:** `application-debug.yml`, `.env.debug.example`, `.gitignore`

**Estimated scope:** Medium

## Task 2: 验证调试 Profile 隔离

**Description:** 添加自动测试，证明调试配置不会回落到生产数据库、端口和文件目录。

**Acceptance criteria:**
- [x] 测试断言数据库名、端口、目录和调度开关
- [x] 测试不连接外部网络或真实数据库

**Verification:** `.\mvnw.cmd -Dtest=DebugProfileIsolationTest test`

**Dependencies:** Task 1

**Files likely touched:** `src/test/java/com/lanf/config/DebugProfileIsolationTest.java`

**Estimated scope:** Small

## Task 3: 添加调试环境脚本

**Description:** 添加环境加载、自检、幂等初始化和日常启动脚本，并对 schema 名执行硬保护。

**Acceptance criteria:**
- [x] 初始化不会默认删除已有调试数据
- [x] 启动拒绝任何不含 `db_diancan_debug` 的 JDBC URL
- [x] 本地凭据不会输出到控制台

**Verification:** PowerShell 语法解析、失败路径测试和自检脚本。

**Dependencies:** Task 1

**Files likely touched:** `scripts/debug-env-common.ps1`, `scripts/setup-debug.ps1`, `scripts/start-debug.ps1`, `scripts/check-debug-env.ps1`

**Estimated scope:** Medium

## Task 4: 编写操作文档

**Description:** 记录首次初始化、日常启动、重置、故障排查和生产启动边界。

**Acceptance criteria:**
- [x] 新成员只按文档即可完成初始化和启动
- [x] 明确说明生产密钥不应放入调试环境

**Verification:** 对照脚本参数逐项核对命令。

**Dependencies:** Task 3

**Files likely touched:** `docs/debug_environment.md`

**Estimated scope:** Small

## Task 5: 初始化并端到端验证

**Description:** 在本机创建隔离数据库与账号、导入基线、编译并启动应用进行验证。

**Acceptance criteria:**
- [x] 调试账号仅可访问独立实例中的 `db_diancan_debug`
- [x] 应用通过 `debug` Profile 在 `127.0.0.1:18080` 启动
- [x] 再次执行初始化不会破坏调试数据

**Verification:** MySQL 权限检查、Maven 测试/编译、HTTP/进程与日志检查。

**Dependencies:** Tasks 1-4

**Files likely touched:** `.env.debug`, `.local/debug/`（均被忽略）

**Estimated scope:** Medium
