# 本地调试环境使用说明

本项目的调试环境使用独立 Spring Profile、MySQL schema、数据库账号、端口和文件目录。初始化完成后不会因关闭终端或重启电脑丢失，日常无需重复搭建。

## 环境隔离

| 项目 | 调试环境 | 生产/原默认环境 |
|---|---|---|
| Spring Profile | `debug`（必须显式启用） | 原部署配置 |
| HTTP | `127.0.0.1:18080` | 原配置 `8080` |
| MySQL 实例 | `127.0.0.1:3307`，数据位于 `.local/mysql-debug/` | 原 `MySQL80:3306` |
| MySQL schema | `db_diancan_debug` | `db_diancan` |
| MySQL 账号 | `diancan_debug`，仅限调试 schema | 原生产账号 |
| 上传文件 | `.local/debug/uploads/` | `/www/wwwroot/...` |
| 定时任务 | 全部关闭 | 保持原行为 |
| 配送、地图等外部调用 | 默认关闭 | 保持原行为 |

`.env.debug` 保存随机生成的调试数据库密码，已被 Git 忽略。独立实例的内部管理凭据保存在权限受限且被忽略的 `.local/mysql-debug/root-password`；不会修改或读取现有 MySQL root 密码。

## 首次初始化

确认已安装 MySQL 8.0 Server，然后在仓库根目录执行：

```powershell
.\scripts\setup-debug.ps1
```

脚本无需输入现有 MySQL 管理员密码，会自动完成：

1. 在 `.local/mysql-debug/data` 初始化独立实例并监听 `127.0.0.1:3307`。
2. 创建 `db_diancan_debug` 和最小权限账号 `diancan_debug`。
3. 首次创建时导入 `docs/db_diancan.sql`，并通过本地迁移账本执行当前 KDS、支付、打印和备货模块所需迁移；随后以独立迁移 CLI 执行 C007/V007 并记录版本。
4. 创建 `.local/debug/uploads/` 下的本地文件目录。
5. 生成被 Git 忽略的 `.env.debug`。
6. 打包项目、执行显式 V007 迁移并完成环境隔离自检。

重复执行该命令是安全的：如果调试库已有表，脚本会保留现有数据，不重复导入。

## 日常启动

初始化完成后，每次只需：

```powershell
.\scripts\start-debug.ps1
```

访问地址：`http://127.0.0.1:18080`。

该命令可重复执行：如果本项目的调试服务已经在 `18080` 健康运行，脚本会显示现有 PID 并成功退出；如果端口被其他程序占用，才会给出占用进程信息并拒绝启动。

启动脚本会自动启动独立 MySQL，强制激活 `debug` Profile，并验证 JDBC URL 必须精确指向 `127.0.0.1:3307/db_diancan_debug`。任何 `3306` 地址或其他 schema 都会被拒绝。

如需单独关闭调试数据库：

```powershell
.\scripts\stop-debug-database.ps1
```

## 环境自检

```powershell
.\scripts\check-debug-env.ps1
```

自检内容包括：本地环境文件、数据库 URL、调试账号、调试目录、schema 是否存在，以及账号是否误获生产 schema 权限。

仅检查文件配置、不连接数据库：

```powershell
.\scripts\check-debug-env.ps1 -SkipDatabase
```

脚本自身测试：

```powershell
.\scripts\test-debug-scripts.ps1
```

## 重置调试数据库

以下操作会永久删除调试库数据，但绝不会删除 `db_diancan`：

```powershell
.\scripts\setup-debug.ps1 -ResetDatabase
```

脚本要求再次输入完整的 `db_diancan_debug` 才会继续。自动化重建时可使用 `-ResetDatabase -Force`。

## 可选的第三方接口联调

普通调试不需要任何真实第三方密钥。若确实需要联调，可在本地 `.env.debug` 末尾增加 `.env.debug.example` 中对应的 `DEBUG_*` 变量。

注意：手动调用支付、打印、微信或配送接口仍可能产生真实外部副作用。只有在使用专用测试账号并明确了解影响时才启用对应凭据。

## 生产环境

调试脚本不会修改 `application.yml` 的数据库或第三方配置，也不会改变现有部署流程。生产启动不要运行 `start-debug.ps1`，并确保没有设置：

```text
SPRING_PROFILES_ACTIVE=debug
```

生产部署推荐显式指定自己的生产 Profile 和外部环境变量。本仓库现有 `application.yml` 中含有明文密钥，应作为独立安全任务迁移并轮换；本次环境隔离改造未擅自更改这些现有值。

## 常见问题

- `mysql.exe was not found`：将 MySQL 8 的 `bin` 目录加入 `PATH`。
- `mysqld.exe was not found`：安装 MySQL 8.0 Server 或将其 `bin` 目录加入 `PATH`。
- `Independent debug MySQL failed to start`：检查 `.local/mysql-debug/mysqld-error.log`，并确认端口 `3307` 未被占用。
- `Safety check failed`：不要绕过检查，修正 `.env.debug`，确保 URL 只连接 `db_diancan_debug`。
- 端口被占用：先关闭占用 `18080` 的进程；不要为了方便改回生产常用端口。
