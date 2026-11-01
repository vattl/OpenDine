# OpenDine：从空服务器到首次登录

本指南针对本仓库当前代码的**全新安装**。已有营业数据的实例请直接阅读“升级与恢复”，不要导入 `deploy/sql/init.sql`，也不要运行 `FreshInstallBootstrap`。历史的 `DEPLOYMENT_AND_MIGRATION_GUIDE.md` 含旧路径、域名和 Flyway 描述，只供版本背景参考；本项目的业务进程不会自动执行全部 SQL 迁移。

## 1. 准备与选择

推荐先完成 Docker 本机验证，再接入客户端和第三方服务。需要 Git、Docker Engine/Desktop 和 Compose v2；使用 Linux 容器。Dockerfile 内部用 Maven 和 Java 8 构建后端，宿主机不需要额外安装 JDK。Windows 使用 Docker Desktop 的 Linux 容器环境。下载镜像和 Maven 依赖需要网络及足够磁盘空间。

原生部署需要 JDK 8、MySQL 8、Redis 和 Maven Wrapper 所需网络。不要把“Java 可以启动”当作其他 JDK 版本兼容性证明。客户端另外需要 Flutter（商家端当前要求 Dart `^3.11.4`）、目标平台 SDK；小程序需要 HBuilderX 和微信开发者工具。先运行 `flutter --version` 与 `flutter doctor` 检查平台工具。

生产准备可访问的域名、HTTPS 证书、备份位置、防火墙和负责运维的人。代码开源不等于微信、配送、打印或 AI 服务免费。

```bash
git clone https://github.com/vattl/OpenDine.git
cd OpenDine/deploy
cp .env.example .env
```

PowerShell 将最后一行替换为 `Copy-Item .env.example .env`。后续 Docker 命令均在 `OpenDine/deploy` 执行。

## 2. 填写环境变量

`.env.example` 故意不提供可用密码。可以使用密码管理器，或多次运行下面的命令分别生成随机值；每个用途使用不同值。

```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

也可用 `openssl rand -hex 32`。把结果放进本地 `.env`，不要贴到聊天、提交 Git 或共享日志。建议 Linux 执行 `chmod 600 .env`；Windows 限制文件 ACL。引号内的值按 Compose `.env` 规则读取；使用随机十六进制可以避免 `$` 插值等歧义。

| 变量 | 怎么填写、作用与影响 |
| --- | --- |
| `MYSQL_ROOT_PASSWORD` | 独立随机数据库管理员密码；MySQL 首次创建数据目录时使用。修改 `.env` 不会自动修改已经存在的数据库密码。 |
| `DB_PASSWORD` | `opendine` 业务数据库账号密码；初始化器和后端必须与 MySQL 中账号一致。账号仅有 `db_diancan` 库权限。 |
| `AUTH_JWT_CURRENT_SECRET` | 至少 32 字节随机值，用于 JWT 签名；丢失/改变会影响现有登录会话。 |
| `APPROVAL_TOKEN_ENVELOPE_KEY` | 独立高熵密钥，用于审批二维码令牌加密；多实例共享同一值，不要复用 JWT 密钥。 |
| `PAYMENT_CONFIG_MASTER_KEY` | 支付商户配置加密主密钥；必须安全备份。不能只改变量来“轮换”，否则旧密文无法解密，应先制定凭据重加密/重新配置方案。 |
| `BOOTSTRAP_ADMIN_USERNAME` | 初始管理员名，3–22 位英文字母、数字、点、下划线或短横线。 |
| `BOOTSTRAP_ADMIN_PASSWORD` | 初始管理员独立强密码，16–72 个 UTF-8 字节，无首尾空白；数据库仅保存 BCrypt。没有默认账号。 |
| `BOOTSTRAP_SHOP_NAME` | 第一家门店名称，1–64 字符；初始化后可管理，但暂停接单。 |
| `APP_PUBLIC_BASE_URL` | 实际服务根地址，不带末尾 `/`；本机为 `http://127.0.0.1:8080`，生产为 `https://你的域名`。用于生成外部可访问链接，不会替你修改客户端地址。 |
| `HTTP_BIND_ADDRESS` / `HTTP_PORT` | 宿主机 HTTP 监听地址/端口，默认 `127.0.0.1:8080`。局域网测试可改为 `0.0.0.0`，同时限制防火墙访问范围。 |

初始化变量仅传入一次性 `bootstrap` 容器，不传给业务服务器。Compose 在解析时仍会检查这些必填变量；可将首次密码留在受限文件中，登录后在客户端修改密码使该首次密码失效。它不会随重启重新设置密码。

| 可选变量 | 用途与未配置时的边界 |
| --- | --- |
| `WEIXIN_APPID` / `WEIXIN_SECRET` | 微信小程序登录等；须与发布的小程序一致。未配置不能完成真实微信登录。与支付商户密钥不是一回事。 |
| `LLM_API_URL` / `LLM_API_KEY` / `LLM_MODEL` | AI 服务接口、密钥和模型；默认 URL/模型只说明适配目标，没有附送密钥或额度。 |
| `AMAP_WEB_KEY` | 后端高德路线服务；无 Key 时无法获得该服务的路网计算能力，应用可能使用已有直线距离降级。 |
| `ZSQ_USERNAME` / `ZSQ_PASSWORD` | 真省钱配送账号；首次安装默认不启用自动配送同步。 |
| `ZSQ_AUTO_API_ENABLED` / `ZSQ_TAKEOUT_SYNC_ENABLED` | 自动配送相关开关，模板均为 `false`；完成账号、门店和业务验证后再开启。 |
| `PERSONAL_COLLECT_WEBHOOK_SECRET` | 个人收款事件 Webhook 的独立校验密钥；不接该功能时留空，不使用源码中的示例字符串。 |

其余后端配置（停车、飞书、订阅模板等）见 `server/src/main/resources/application.yml`。**在 `.env` 增加一行不会自动传入容器**：必须同时在 `docker-compose.yml` 的对应服务 `environment` 中映射，或提供受控的外部 Spring 配置文件。不要把所有外部服务打开当作部署前提。

Compose 的 `.env` 仅供 Compose 插值，Java 不直接读取。修改已映射变量后执行 `docker compose up -d --force-recreate opendine-server`；`docker compose restart` 不更新环境。JWT 平滑轮换可按源码契约增加 `AUTH_JWT_PREVIOUS_SECRET` 映射，旧令牌过期后移除；不要复用审批或支付密钥。

## 3. 构建、空库初始化与启动

```bash
docker compose --profile tools build bootstrap
docker compose up -d opendine-mysql opendine-redis
docker compose --profile tools run --rm bootstrap
docker compose up -d opendine-server opendine-nginx
docker compose ps
docker compose logs --tail=100 opendine-server
```

构建在镜像内执行 `mvn -Pprod clean package -DskipTests`，生成 `/app/app.jar`；这是打包步骤，不是测试通过证明。首次运行下载依赖可能较慢。`bootstrap` 的预期末行是 `Fresh installation complete...`，只有它退出码为 0 才继续启动服务器。初始化过程先检查空库、取得锁，导入基线/RBAC/API 映射，应用版本迁移并登记校验和，建立管理员与门店，最后执行支付/KDS schema readiness。

基线已去掉重复的 V021/V033/V037 片段，由原始版本迁移补齐；V048 替换套餐唯一索引时另有外键支撑索引。初始化器还显式应用 `db_migration_kds_projection_intent.sql`、`db_migration_kds_shared_revision.sql`、`db_migration_report_job_recovery.sql` 和 `db_migration_shop_settle_flow.sql` 四个必需历史脚本，不给它们伪造 V 版本号。不要单独导入基线后直接启动，也不要自行填假迁移校验和。当前版本没有示例订单或真实支付凭据；历史迁移附带的无下载地址版本策略和订阅消息模板保持禁用。

数据库、Redis 和一次性 bootstrap 只加入不可对外路由的 `data` 网络；业务服务同时加入 `data` 与 `edge`，Nginx 只加入 `edge` 并独自暴露宿主机入口。这样入口容器不能直接访问数据库或 Redis。`docker compose up -d` / 重启不会重新初始化。`docker compose down` 停止服务但保留命名卷；不要使用删除卷选项处理普通故障。

HTTP 根地址可能返回 404，因为它是 API，不是已经打包的管理网页。这不能单独判断启动是否成功。日志必须没有 readiness 失败，且下一步真实登录验证通过。

## 4. 验证初始管理员与门店

安装 Python 3 后，在 `deploy` 目录执行（仅使用 Python 标准库，不需安装额外包；PyYAML 仅开发者配置测试需要）：

```bash
python verify-login.py
```

输入服务地址、你设置的管理员名和隐藏输入的密码。脚本发起 `POST /adminLogin`，JSON 字段为 `userName`、`password`；期待响应顶层 `code: 0` 与 `token`。随后把 token 放到 `Authorization: Bearer ...` 请求 `GET /admin/me/permissions`，检查 `code: 0`、`scope: HQ`、`isSuperAdmin: true`、非空权限与门店。密码和 token 不打印、不保存，不需写在 shell 命令行。脚本拒绝 HTTP 重定向；请直接输入最终 HTTPS 地址。

这证明首次登录和权限/门店路径可用，不证明支付、打印或厨房设备已可营业。`/admin/me/permissions` 的门店摘要不含接单开关；在管理客户端查看门店设置，或通过受控数据库工具执行 `SELECT id,name,status,ordering_open FROM t_shop;`，初始接单值应为 `0`。

依次设置门店营业时间、分类/菜品/规格、桌台、员工和门店范围，再配置设备与支付。初始账号是全局管理员，用于初始化和权限管理；日常员工创建专用账号并分配最小权限，不共享初始账号。完成自己的下单、加菜、出餐、取消/退款、交班等演练后再打开接单。

## 5. 连接客户端

### 管理/收银端

编辑 `admin_panel/lib/src/core/app_config.dart` 的 `productionApiBaseUrl`，填写后端 HTTPS 根地址。Release 构建会忽略 `DEBUG_API_BASE_URL`，所以仅传 debug 的 dart-define 不会改变生产地址。

```bash
cd ../admin_panel
flutter --version
flutter doctor
flutter pub get
flutter build windows --release
# 或在 Android SDK 就绪后
flutter build apk --release
```

Windows 构建需 Windows + Visual Studio C++ 桌面工具链。分发整个 `build/windows/x64/runner/Release/` 文件夹，不能只复制 `.exe`。Android 产物为 `build/app/outputs/flutter-apk/app-release.apk`，正式分发需配置自己的签名并验证目标机权限。项目有 Web 相关代码，但本文不承诺桌面打印/局域网能力在 Web 上等价，先用桌面/Android 完成验收。

### KDS

```bash
cd ../kds_app
flutter pub get
flutter build apk --release --dart-define=KDS_CLOUD_API_BASE=https://api.example.com
# 如需 Windows，且对应工具链就绪
flutter build windows --release --dart-define=KDS_CLOUD_API_BASE=https://api.example.com
```

把示例域名换成你的地址。在后台配置工位/设备并走正式配对流程；设备身份由云端签发。确认 `/ws/kds/v2` WebSocket 通过反向代理。局域网代理不是另一个业务主库，不要按旧 replication 文档启用双主写入。

### 微信小程序

1. 用 HBuilderX 打开 `miniprogram/` Uni-App 项目；它不是可以直接把 Vue 源码交给微信开发者工具运行的普通小程序目录。
2. 修改 `utils/requestUtil.js` 的 `baseUrl`；将 `manifest.json` 中 `mp-weixin.appid` 配为自己的 AppID。后端 `WEIXIN_APPID`/`WEIXIN_SECRET` 与之对应。仓库 `project.config.json` 的示例 AppID 也不能作为真实发布账号。
3. 在该目录运行 `npm install` 安装声明的依赖，再通过 HBuilderX“运行到小程序模拟器 → 微信开发者工具”验证。发布使用“发行 → 小程序-微信”，输出通常在 `unpackage/dist/build/mp-weixin`（以 HBuilderX 的实际输出为准）。微信开发者工具导入编译后的目录，再上传审核。
4. 微信公众平台配置 request/upload/download/socket 合法域名和 HTTPS/WSS，使用真机验证。开发者工具“不校验域名”不代表发布可用。

手机或平板的 `localhost` 是它自己，不能指向你的电脑。局域网试用时使用服务器局域网 IP、开放受限 HTTP 端口并修改所有客户端地址；正式微信发布使用有效 HTTPS 域名。

## 6. 文件、HTTPS 与外部服务

`application-deploy.yml` 统一把菜品、二维码、头像、广告、通用图片、线下收款图片和客户端包目录设在 `/var/lib/opendine/public`。Compose 命名卷 `public-files` 持久化它们；`/image/**` 由后端读取对应目录，`/upload/**` 由 Nginx 读取公共卷。邀请海报背景需自行准备在 `poster/bg/invite-bg.jpg`，系统不包含你的营业素材。

支付 PEM/P12 文件只进入 `/var/lib/opendine/private/payment-keys`，对应独立 `payment-keys` 卷；Nginx 不挂载它，同时拒绝 `/upload/payment-keys/` 和 `/private/`。不要把历史私钥直接拷进公共上传目录。

默认 Nginx 配置仅提供 HTTP。公网推荐在宿主机/上游反向代理终止 TLS，把域名请求转发到默认回环 `127.0.0.1:8080`；也可自行维护容器 Nginx 的证书与 443 配置。转发需保留 Host、真实 IP、协议和 WebSocket Upgrade。现有容器 Nginx 以 `$scheme` 设置 `X-Forwarded-Proto`；若 TLS 在上游终止，需在受信上游链中正确设置该字段，不能直接信任任意公网传入头。设置 `APP_PUBLIC_BASE_URL=https://你的域名`，验证外部链接和回调实际能到达。

微信商户凭据通过后台支付配置能力设置，不能放进客户端或把小程序 Secret 当成支付密钥。逐项验证商户号、应用绑定、证书/公钥、支付/退款回调及测试交易。打印需要真实设备和平台账号；配送、地图、AI 等需分别配置和验收。订阅消息模板初始化为禁用，替换成你账号的真实模板、配置参数并验证后再启用。

## 7. 不用 Docker 的原生部署

以下从仓库根目录执行；Windows 使用 `server\mvnw.cmd`，Linux/macOS 用 `sh server/mvnw`。先让 `JAVA_HOME` 与 PATH 指向 JDK 8。

```bash
sh server/mvnw -f server/pom.xml -Pprod clean package -DskipTests
```

用 MySQL 管理工具创建空库（例如 `db_diancan`，utf8mb4）和仅该库权限的账号。初始化要有建表、索引、存储过程等 DDL 权限；业务运行可进一步拆分为较小权限账号，但应按实际 SQL 验证权限，不要直接使用 root。新建库必须没有任何表。Redis 只监听可信网络，配置主机/端口/必要认证。

将以下变量设置到**启动 Java 的当前进程环境**，密钥在本机密码管理器/受限环境文件中输入，不在命令参数中传递：

| 初始化变量 | 示例/来源 |
| --- | --- |
| `MIGRATION_JDBC_URL` | `jdbc:mysql://127.0.0.1:3306/db_diancan?serverTimezone=Asia/Shanghai&useUnicode=true&characterEncoding=utf8&allowPublicKeyRetrieval=true&useSSL=false`（仅本机数据库例子，远程数据库应配置验证证书的 TLS） |
| `MIGRATION_DB_USER` / `MIGRATION_DB_PASSWORD` | 你创建的专用库账号/密码 |
| `BOOTSTRAP_REPOSITORY_ROOT` | 克隆根目录的绝对路径，包含 `deploy/` 和 `server/`，不是 server 子目录 |
| `BOOTSTRAP_CONFIRM_EMPTY_DATABASE` | `YES` |
| `BOOTSTRAP_ADMIN_USERNAME` / `BOOTSTRAP_ADMIN_PASSWORD` / `BOOTSTRAP_SHOP_NAME` | 与上表同义 |

例如 Bash 可在可信私有环境文件中写 `export NAME='value'` 并 `source /安全路径/opendine-env.sh`；PowerShell 可在当前会话用 `$env:NAME='value'`，密码使用 `$env:MIGRATION_DB_PASSWORD = Read-Host -MaskInput`（PowerShell 7）避免显示。不要把私密环境文件放进仓库。确认变量后运行以下**完整命令**：

```bash
java -Dfile.encoding=UTF-8 -Dloader.main=com.lanf.database.FreshInstallBootstrap -cp server/target/diancan-0.0.1-SNAPSHOT.jar org.springframework.boot.loader.PropertiesLauncher
```

成功后，业务进程使用以下变量（不会读取 `MIGRATION_*`）：

| 变量 | 设置 |
| --- | --- |
| `SPRING_DATASOURCE_URL` / `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` | 对应实际数据库 URL/业务账号/密码 |
| `SPRING_REDIS_HOST` / `SPRING_REDIS_PORT` / 必要时 `SPRING_REDIS_PASSWORD` | 实际 Redis 参数 |
| `AUTH_JWT_CURRENT_SECRET` / `APPROVAL_TOKEN_ENVELOPE_KEY` / `PAYMENT_CONFIG_MASTER_KEY` | 前述独立随机密钥 |
| `APP_PUBLIC_BASE_URL` | 对外服务 URL |
| `SPRING_CONFIG_ADDITIONAL_LOCATION` | `file:/绝对路径/OpenDine/deploy/application-deploy.yml`；Windows 可用 `file:C:/OpenDine/deploy/application-deploy.yml` |
| `OPENDINE_PUBLIC_DIR` | 可写公共文件目录，如 `C:/OpenDineData/public` 或 `/var/lib/opendine/public` |
| `PAYMENT_PRIVATE_KEY_UPLOAD_DIR` | 与公共文件分开的可写私钥目录 |
| `ZSQ_AUTO_API_ENABLED` / `ZSQ_TAKEOUT_SYNC_ENABLED` | 未配置配送时均设 `false` |
| `PERSONAL_COLLECT_WEBHOOK_SECRET` | 设置独立随机值；不用该功能也不要沿用源码示例值 |

创建这些数据目录及公共目录下的 `qrcode`、`dish`、`avatar`、`advertising`、`images`、`offline-collect`、`packages`、`poster/bg` 子目录，授予运行账号写权限（二维码写入路径依赖目录存在）；确认未启用 `debug` profile。启动：

```bash
java -Dfile.encoding=UTF-8 -jar server/target/diancan-0.0.1-SNAPSHOT.jar
```

执行 `python deploy/verify-login.py`。用 systemd/Windows 服务管理器配置开机、工作目录、受限运行用户和受保护环境文件；环境必须属于服务进程，不能只在交互终端设置。原生反向代理按第 6 节提供同等静态目录和 WebSocket 转发。

## 8. 备份、升级与恢复

备份至少包括：MySQL 全库及迁移记录、`public-files`、私有 `payment-keys`、安全保存的密钥与环境配置、实际使用的代码版本/JAR。数据库备份和私钥应加密并限制访问，异地保留；不要只有同一磁盘上的副本。Redis 不是业务账本备份。

Docker 下可在 `deploy` 使用下面命令，密码由容器环境读取，未作为 mysql 命令行参数传递。先创建受限的 `backups` 目录；SQL 文件仍包含敏感业务数据，导出后加密转移。

```bash
mkdir -p backups
docker compose exec -T opendine-mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --routines --events --no-tablespaces db_diancan > /tmp/opendine-backup.sql'
docker compose cp opendine-mysql:/tmp/opendine-backup.sql backups/database.sql
```

PowerShell 创建目录用 `New-Item -ItemType Directory -Force backups`。确认备份成功后从容器清理临时备份文件。通过 Docker 卷备份工具或基础设施快照备份公共和私钥卷；用 `docker compose config --volumes` 查看声明、`docker volume ls` 确认实际卷名（默认前缀 `opendine_`），不要猜测另一套部署的卷名。备份和恢复期间需停写或采用一致性快照。

Compose 和 Dockerfile 的上游官方镜像都使用内容摘要锁定，避免相同标签在无人审核时变成另一份镜像。维护者应定期查询官方仓库的新摘要和安全公告，在单独变更中更新标签/摘要，重新执行部署契约、镜像构建、空库初始化和登录回归后再发布；不要只运行 `pull` 就把生产环境视为已升级。

每次升级先备份，在克隆环境核对当前 `t_app_schema_version` 与目标迁移，执行该版本要求的显式 CLI/SQL，再替换 JAR/镜像并完成同样登录和业务回归。V007–V012 有专用显式迁移入口，后续脚本并非全部幂等；不要重复执行整个 migrations 目录，不要把版本文件出现等同于已执行。DDL 可能自动提交，回滚通常需要旧应用加已验证的数据库/文件备份，不能只切回旧 JAR。

定期把备份恢复到另一套隔离 MySQL 和文件目录，校验迁移记录、登录、门店、业务数量及加密凭据可读取；不要在生产库做恢复演练。空库 bootstrap 中途失败时会留下部分 DDL 并拒绝重跑：保留失败阶段和 SQLState，修复后只能对**确认没有业务数据的独立测试/新安装库**重建再试。已有数据一律走备份恢复/专项迁移，不提供自动清库按钮。

## 9. 常见问题与验证范围

| 现象 | 检查 |
| --- | --- |
| Compose 报 required variable | `.env` 是否在 deploy 目录、对应值是否为空；变量只在正确服务映射才会注入。 |
| 数据库 Access denied | 账号实际密码与 `.env` 是否一致；改环境不会改已持久化的 MySQL 密码。 |
| Bootstrap 非空拒绝 | 正常保护，可能是已有库或上次失败留下的表；不自动清理。 |
| Bootstrap SQLState/vendorCode | 记录最后 `Stage` 与代码；确认 JAR、基线和文档来自同一提交，使用 MySQL 8，先在空测试库重现。 |
| JWT/审批密钥启动错误 | 检查密钥长度、是否真正注入服务、实例间是否一致；不要贴出密钥。 |
| readiness 缺表/校验和错误 | 未完成初始化、JAR 与数据库版本不匹配；不要跳过检查或手填校验和。 |
| 根 URL 404 | API 服务未托管管理客户端；用真实登录验证。 |
| 登录成功但无权限/门店 | 核对 `t_admin_role`、角色权限和门店状态；首次管理员应为 `super_admin` / HQ。 |
| 图片不存在/上传失败 | 检查 deployment.yml 已加载、卷挂载/目录权限和真实文件；设置公网 URL 不会移动文件。 |
| 手机连接失败 | 不能使用服务器之外设备的 localhost；检查客户端地址、监听地址、防火墙、HTTPS 和合法域名。 |
| 后厨不实时更新 | 检查云端设备配对、WebSocket Upgrade、反向代理超时，不用旧双主复制方案替代。 |

当前 API 权限审计清单与历史 SQL 的方法/别名口径不同：初始化补齐 4 条缺失路由，并保留已有更严格映射。启动日志仍可能报告 `missing=0, different=1, extra=67`；差异包括门店通知配置的更严格管理权限，以及历史兼容别名。它不是 schema 初始化失败，也不应通过批量覆盖权限表消除。通知配置应由有管理权限的账号操作；升级时必须单独审查授权变化。

本指南发布前已在隔离的 MySQL 8 与 Java 8 环境完成一次全新空库验证：bootstrap 独立执行成功，49 个版本化迁移校验和一致，管理员密码以 BCrypt 保存，首店保持停止营业，服务实际启动后管理员登录、权限读取和错误密码拒绝均通过；随后对非空库重跑 bootstrap 被安全拒绝，数据数量未变化。Compose 配置也完成了必填变量正反校验。验证环境没有 Docker Engine，因此未实跑容器镜像构建/启动，也未代替你在 Windows/Android/微信真机、真实支付或硬件上验收。部署者仍需在自己的目标环境执行本指南并保留验证记录。
