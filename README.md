# OpenDine 智膳系统

面向中小餐饮门店的开源点餐、收银、后厨协作与经营管理系统。

一家店通常不缺软件，缺的是能接起来的业务流程：顾客下单后还要手写传菜单，前台不知道后厨做到哪一步，交班要从几个地方拼流水，菜品卖完了却来不及同步给顾客。OpenDine 把这些环节放进同一个服务端和数据库，供商家自行部署、配置和维护。

## 它能帮门店处理什么

| 门店问题 | 对应能力 | 使用前需要准备 |
| --- | --- | --- |
| 高峰期反复录入订单、加菜容易遗漏 | 顾客小程序点餐，收银端桌台、加菜、挂单与结账 | 菜单、桌台、门店营业配置 |
| 前台与后厨对不上制作进度 | KDS 工位看板、出餐操作、订单变更同步 | 厨房设备、工位配置、可用网络 |
| 交班依赖手工汇总，退款难追溯 | 钱箱、交班、日结、支付账本与对账记录 | 员工权限、结算规则及实际支付渠道 |
| 多店菜单、人员和会员数据难管理 | 门店范围、角色权限、会员与储值相关管理 | 明确每位员工可操作的门店和权限 |
| 备货靠经验，经营数据分散 | 销量报表、物料 BOM、备料预测和可选 AI 能力 | 菜品物料关系、足够历史数据；AI 另需服务账号 |

这些能力提供业务工具，不保证门店永不掉线、预测必然准确或对账自动无差异。首次营业前应使用自己的设备和业务流程验收。

## 项目组成

| 目录 | 作用 | 技术 |
| --- | --- | --- |
| `server/` | 云端 API、权限、业务状态、账本和任务 | Java 8、Spring Boot 2.3.2、MySQL 8、Redis |
| `admin_panel/` | 商家管理与收银客户端 | Flutter；当前 Dart 约束 `^3.11.4` |
| `kds_app/` | 后厨显示与出餐客户端 | Flutter |
| `miniprogram/` | 微信顾客点餐小程序源码 | Uni-App / Vue |
| `packages/` | Flutter 共享代码 | Dart |
| `deploy/` | 容器构建、环境模板、反向代理和空库初始化输入 | Docker Compose / Nginx |
| `server/docs/` | API、数据库和运维文档 | Markdown / OpenAPI / SQL |

KDS 以云端为唯一业务权威；收银端局域网服务是代理/缓存。网络故障时不能把本地暂存当作云端业务成功。具体边界见 [KDS 架构说明](server/docs/KDS_ARCHITECTURE.md)。

## 从零部署

**第一次安装请按 [完整部署指南](server/docs/DEPLOYMENT.md) 操作。** 它包含环境变量解释、初始账号、客户端构建、验证、备份和故障处理。Docker 流程会在镜像中构建 JAR，不需要先在宿主机安装 Java/Maven。

```bash
git clone https://github.com/vattl/OpenDine.git
cd OpenDine/deploy
cp .env.example .env
# 按部署指南填写 .env；模板不含可用密码
docker compose --profile tools build bootstrap
docker compose up -d opendine-mysql opendine-redis
docker compose --profile tools run --rm bootstrap
docker compose up -d opendine-server opendine-nginx
docker compose ps
```

Windows PowerShell 用 `Copy-Item .env.example .env` 替代 `cp`。默认 HTTP 入口为 `http://127.0.0.1:8080`，这是 API 入口，**不会直接出现商家管理网页**；管理/收银、KDS 和小程序需分别构建与安装。

初始化器只接受完全空的数据库，执行当前迁移、建立角色/权限，以及你指定的 BCrypt 管理员和第一家暂停接单的门店。没有 `admin/admin` 等默认账号。正常重启不会再次初始化；已有实例不能使用这套空库流程升级。

MySQL/Redis 不发布宿主机端口，支付私钥存放在独立卷，不交给 Nginx。公网部署需要 HTTPS、域名和防火墙；手机/平板上的 `localhost` 指设备自己，不能用来连接另一台服务器。

## 环境变量先看这几项

| 变量 | 用途 |
| --- | --- |
| `MYSQL_ROOT_PASSWORD` / `DB_PASSWORD` | 数据库管理员与应用账号的独立密码 |
| `AUTH_JWT_CURRENT_SECRET` | 登录令牌签名密钥，至少 32 字节随机值 |
| `APPROVAL_TOKEN_ENVELOPE_KEY` | 审批令牌加密密钥，独立于 JWT，所有实例保持一致 |
| `PAYMENT_CONFIG_MASTER_KEY` | 支付商户凭据加密主密钥，需与数据库一起安全备份 |
| `BOOTSTRAP_ADMIN_USERNAME` / `BOOTSTRAP_ADMIN_PASSWORD` / `BOOTSTRAP_SHOP_NAME` | 仅首次初始化使用的管理员和门店信息 |
| `APP_PUBLIC_BASE_URL` | 客户端和回调实际可访问的服务根地址 |

`.env` 是 Docker Compose 的变量输入文件，Java 不会自动读取它。更改变量后需重建对应容器；单纯 `restart` 不更新环境变量。完整变量表及原生进程注入方法见 [部署指南](server/docs/DEPLOYMENT.md)。

## 外部服务与运行边界

基础服务可以先不配置微信、支付、配送、地图或 AI；这不代表相关功能已经可用。微信登录需要自己的小程序 AppID/Secret 与合法域名；在线支付还需要真实商户配置、证书和回调验证。打印、配送、地图、停车、发票及 AI 功能各自有账号、设备、网络或服务资费要求，必须逐项配置并实测。开源代码不包含这些服务的授权、生产密钥或可用额度。

运营方需要负责服务器维护、数据备份、账号权限和上线验收。当前 Spring Boot/Java 技术栈较旧，公网使用前还需独立评估依赖安全与部署环境。

## 开发与文档

- [部署与运维指南](server/docs/DEPLOYMENT.md)：新安装的唯一入口。
- [API 说明](server/docs/API.md) / [OpenAPI](server/docs/openapi.yaml)：客户端对接契约。
- [后端项目概况](server/docs/project/PROJECT_PROFILE.md)：服务端结构与约束。
- [历史迁移手册](server/docs/DEPLOYMENT_AND_MIGRATION_GUIDE.md)：仅供历史版本背景参考，其中旧路径、地址及 Flyway 自动迁移表述不适用于本安装流程。

提交问题时请附版本、复现步骤和已脱敏日志，不要上传 `.env`、数据库备份、登录令牌或证书私钥。许可证见 [LICENSE](LICENSE)。
