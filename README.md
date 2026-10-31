<p align="center">
  <h1 align="center">🍽️ OpenDine 智膳系统</h1>
  <p align="center">
    <strong>全场景高可用开源餐饮数字化系统</strong><br>
    微信小程序点餐 + 智能收银 POS + KDS 后厨流批协同 + AI 销量与备料预测 + 飞鹅云打印
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
    <img src="https://img.shields.io/badge/Java-8%20%7C%2011%20%7C%2017-orange.svg" alt="Java">
    <img src="https://img.shields.io/badge/Spring%20Boot-2.3.2.RELEASE-brightgreen.svg" alt="Spring Boot">
    <img src="https://img.shields.io/badge/Flutter-3.x-blue.svg" alt="Flutter">
    <img src="https://img.shields.io/badge/Uni--App-Vue-green.svg" alt="Uni-App">
    <img src="https://img.shields.io/badge/MySQL-5.7%20%2F%208.0-blue.svg" alt="MySQL">
    <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome">
  </p>
</p>

---

## 📖 项目简介

**OpenDine** 是一套专为现代实体餐饮门店与连锁品牌打造的**全链路数字化开源系统**。项目基于真实餐饮业务场景持续打磨，覆盖**顾客端扫码点餐与外卖**、**商家收银前台与日结交班**、**KDS 后厨流批协同大屏**、**供应链物料 BOM 与 AI 销量备货预测**以及**多联网络云打印**的完整闭环。

系统针对餐饮高峰期并发高、网络易抖动等痛点，在收银与后厨模块深度实现了**云端权威与局域网容灾双模通信架构**，保障点餐、结账与厨房打件出餐永不停摆。

---

## 🏗️ 仓库模块架构 (Monorepo)

本项目采用标准化单体多包仓库管理，包含以下核心工程：

```text
OpenDine/
├── server/          # ☕ 后端微服务 (Spring Boot 2.3.2 / MyBatis-Plus / Redis / WebSocket)
├── miniprogram/     # 📱 顾客端：微信点餐小程序 (DCloud Uni-App / Vue)
├── admin_panel/     # 💻 商家端：智能收银台与管理工作台 (Flutter 3.x 跨端：Windows / Android / Web)
├── kds_app/         # 🍳 后厨端：KDS 实时出餐协同大屏 (Flutter 3.x 跨端：大屏看板 / 双模容灾)
├── packages/        # 📦 前端共享基础组件包 (shop_core 共享领域模型)
├── deploy/          # 🚀 容器化部署 (Docker-Compose / Nginx 反向代理与 WebSocket 升级 / 数据库初始化脚本)
└── docs/            # 📚 数据库字典、OpenAPI 接口规范、权限设计与排障文档
```

---

## 🌟 各端核心功能与代码实现

### 1. 后端服务 (`server/`)

- **技术底座**：Java 8+（兼容 Java 11/17），Spring Boot 2.3.2.RELEASE，MyBatis-Plus 3.3.2，Druid 1.1.10 连接池，MySQL 5.7 / 8.0，Redis + Caffeine 二级缓存。
- **认证与细粒度权限 (`ApiPermissionMapping` / `SysInterceptor`)**：
  - **C 端用户**：微信静默登录与手机号快速绑定，签发安全 JWT Token，统一通过 HTTP 请求头 `X-User-Token` 认证；
  - **B 端收银与管理**：拦截器对齐 `t_api_permission` 表，实现精确到 `HTTP Method + Path Pattern` 的细粒度权限校验；管理员密码采用 Spring Security BCrypt 强哈希加密；
  - **收银双人审批复核**：针对收银改价、整单大额退款等高风险操作，支持动态生成审批二维码（`bbq://approval`），由店长扫码授权放行。
- **聚合支付与资金安全 (`com.lanf.payment.*`)**：
  - 微信支付 APIv3 直连（证书与商户配置隔离存放在 `t_payment_merchant_config`）；
  - 支持特约商户服务商分账模式；
  - 支持线下个人扫码聚合收款 Webhook 兜底；
  - 退款状态机与幂等守护（`t_payment_refund_guard`），防止网络重试导致超额退款。
- **AI 智能销量与物料 BOM 备料预测 (`StockPrepForecastServiceImpl`)**：
  - **历史销量回溯**：回溯过去 56 天同一星期几的历史销量中位数与移动加权均值；
  - **公休长假因子**：读取 `holidays/cn-public-holidays.json` 自动计算节假日与调休日客流溢价；
  - **天气维度联动**：自动请求 Open-Meteo 真实气象 API 获取未来降水量与温度对堂食销量的修正系数；
  - **物料 BOM 消耗拆解**：根据菜品预测销量，联动 `t_dish_material_bom` 自动计算未来 7 天生鲜食材、蔬菜、肉类所需备料计划（`t_stock_prepare_plan`）。
- **外卖与同城运力调度 (`com.lanf.service.impl.TakeoutServiceImpl`)**：
  - 对接**真省钱（ZSQ）同城配送平台** OpenAPI，实现自动分发订单、运力接单、取消配送与异常单重派；
  - 对接**高德地图 Web 服务**（驾车/骑行路径规划），精准计算路网真实行驶距离与阶梯配送费，支持直线距离智能降级；
  - 内置 WGS84、GCJ-02（火星坐标）、BD-09（百度坐标）坐标系无损纠偏算法。
- **多联云打印调度引擎 (`com.lanf.printing.*`)**：
  - 深度集成**飞鹅云（Feieyun）**网络云打印机，支持根据单据类型分发至不同打印设备；
  - 预设 5 大票种：前台全单结算联（FULL_ORDER）、收银预结单（PRE_CHECKOUT）、厨房各工位分单联（KITCHEN）、传菜联（RUNNER）与外卖打包联（PACKING）；
  - 支持打印机在线状态实时探测与异常待打印队列一键清空。
- **电子发票引擎 (`OrderInvoiceServiceImpl`)**：
  - 校验企业增值税发票抬头与 18 位统一社会信用代码税号规则，支持消费者自助申请开票，开票成功邮件自动推送。

---

### 2. 顾客端：微信点餐小程序 (`miniprogram/`)

- **技术栈**：DCloud Uni-App（Vue 2 运行时，兼容微信小程序端）。
- **主包四大核心 TabBar 页面**：
  - **首页 (`pages/index/index`)**：门店轮播图、营业中状态检测、门店公告广播、堂食点餐入口、排队取号入口。
  - **菜单与购物车 (`pages/home-page/page`)**：左侧品类联动分类栏、菜品卡片列表、多规格/做法选弹窗、沽清状态展示、底部动态购物车、多人协同加菜。
  - **订单中心 (`pages/myorder/myorder`)**：堂食订单、外卖配送与自提订单列表，实时流转“待支付 → 制作中 → 待取餐/配送中 → 已完成”状态。
  - **个人中心 (`pages/my/my`)**：会员卡片、本金与赠送余额、可用优惠券数、邀请好友入口、收货地址与停车减免入口。
- **独立分包 (`packageOther/`)**：
  - `select-shop/`：多门店列表、基于地理位置计算门店直线距离与当前切换；
  - `select_number/`：扫码就餐人数与桌台确认；
  - `confirm-order/`：下单确认页，支持就餐方式（堂食/打包外带）、立减券/满减券抵扣选择、订单备注；
  - `combo-select/`：组合套餐动态选菜，支持“固定项 + 分组多选一”菜品搭配；
  - `ai-order-chat/`：基于大模型 API 的智能交互式对话点餐助手；
  - `order-details/`：订单详情流水、出餐进度追踪、外卖配送员实时地图轨迹、电子发票开具申请；
  - `member-recharge/`：会员充值台账与多档位“充值赠送”办理；
  - `invite-friend/`：好友邀请裂变、专属邀请码、海报生成与首单奖励流水明细；
  - `queue-ticket/`：在线取号排队、前方等待桌数与叫号微信订阅消息即时提醒；
  - `takeout-address/`：高德地图地址智能联想与收货地址簿管理；
  - `parking/`：就餐顾客停车优惠绑定与车牌登记。

---

### 3. 商户端：智能收银台 POS (`admin_panel/`)

- **技术栈**：Flutter 3.x（支持 Windows 桌面触摸屏收银、Android 平板/手持机、Web 端）。
- **核心业务模块 (`lib/src/features/`)**：
  - **桌台与前台收银 (`pos/`, `tables/`)**：桌台网格状态（空闲、就餐中、已结账未清台）、开台点菜、整单改价、折扣优惠、就餐人数修改、挂单/取单、换桌/并桌。
  - **全渠道结算 (`cashier_bills/`)**：支持微信付款码刷卡支付（Micropay）、微信主扫（Native）、现金记账、会员余额划扣、免单、挂账与组合支付。
  - **逆向交易与退款**：反结账（还原单据重新结算）、整单退款与指定单品退菜。
  - **日结与交接班 (`cashier_shift/`)**：当班人员钱箱现金盘点、各渠道收单汇总、打印交班结算小票、营业时段禁止日结防误操作。
  - **菜品沽清与调价 (`cashier_catalog/`)**：前台一键快速标记菜品沽清/恢复上架，实时同步至点餐小程序。
  - **会员管理 (`cashier_member/`)**：根据手机号查询会员画像、储值余额、后台人工充值与充赠流水。
  - **小票模版与设备设置 (`cashier_printing/`, `cashier_settings/`)**：内置小票可视化排版设计器、飞鹅云打印机绑定、多联打印规则分配。
  - **局域网双模协作 (`kds_local/`)**：内置本地服务端发现与证书生成工具，保障在断公网状态下本地局域网点单直接推向后厨 KDS。

---

### 4. 后厨端：KDS 实时出餐大屏 (`kds_app/`)

- **技术栈**：Flutter 3.x（深度适配 1080P/2K/4K 厨房大屏显示与触摸屏工位机）。
- **通信架构 (`core/ws/`, `core/lan_v2/`)**：
  - 建立 WebSocket 长连接直连后端推送通道（`/ws/kds`）；
  - **双模自动容灾（`kds_dual_mode_transport`）**：公网畅通时走云端统一调度；网络异常时无感切入局域网广播模式；
  - **离线命令发件箱（`kds_command_outbox_store`）**：离线状态下厨师完成出餐的操作先暂存本地 SQLite/文件快照，网络恢复后幂等同步。
- **出餐协同看板 (`features/board_v2/`)**：
  - **工位流批分类**：支持按菜品分类筛选（如烧烤工位、热炒工位、凉菜工位、传菜主控台）；
  - **单品/整单出餐操作**：点击单品划菜出餐，支持误触一键撤回（Undo Toast）；
  - **超时警报指示**：根据订单等待时间阶梯式变色预警（绿 → 黄 → 红闪烁）；
  - **前台退菜/加菜联动**：前台退菜瞬间标红并阻断制作，避免食材浪费；前台加菜带强提示声光动效。

---

## 🚀 极速部署指引

### 方式一：Docker Compose 一键启动（推荐）

进入项目 `deploy` 目录，一键启动 MySQL 8.0、Redis、Nginx 与 OpenDine 服务端：

```bash
# 1. 进入部署目录
cd deploy

# 2. 启动全套容器集群
docker compose up -d

# 3. 检查容器运行状态
docker compose ps
```

- **统一入口（Nginx）**：`http://localhost`
- **后端服务端口**：`http://localhost:8080`
- **MySQL 端口**：`3306`（默认密码 `root`，数据库 `db_diancan`，首次启动自动执行 `sql/init.sql` 初始化数据表）
- **Redis 端口**：`6379`

---

### 方式二：源码本地开发环境调试

#### 1. 后端工程 (`server/`)
- **环境要求**：JDK 1.8 或更高版本，Maven 3.6+，MySQL 5.7/8.0，Redis
```bash
cd server

# 导入数据库
# 将 deploy/sql/init.sql 导入本地 MySQL 的 db_diancan 数据库

# 编译打包并启动
./mvnw clean package -DskipTests
./mvnw spring-boot:run
```

#### 2. 微信小程序 (`miniprogram/`)
1. 使用 **微信开发者工具** 直接打开 `miniprogram` 目录；
2. 在 `project.config.json` 或 `manifest.json` 中配置您的小程序 `appid`；
3. 检查 `utils/requestUtil.js` 中的 `baseUrl` 指向本地开发接口（默认已设为 `http://localhost:8080`）；
4. 点击编译即可直接在模拟器中体验扫码点餐与外卖链路。

#### 3. 收银端与 KDS 后厨端 (`admin_panel/` & `kds_app/`)
- **环境要求**：Flutter SDK 3.x+
```bash
# 运行智能收银台（支持 Windows 桌面端或 Web 浏览器）
cd admin_panel
flutter pub get
flutter run -d windows # 或 flutter run -d chrome

# 运行 KDS 后厨大屏
cd ../kds_app
flutter pub get
flutter run -d windows # 或 flutter run -d chrome
```

---

## 🗄️ 核心数据库表结构简述

系统包含 60 余张精细化业务表，核心业务模型包括：

- `t_user` / `t_user_address`：顾客信息、OpenID 与外卖地址簿；
- `t_order` / `t_order_detail` / `t_order_log`：主订单、菜品明细与订单全生命周期操作日志；
- `t_dish` / `t_dish_shop` / `t_category`：主菜品库、多门店独立库存/沽清覆盖与分类体系；
- `t_combo` / `t_combo_group` / `t_combo_group_item`：组合套餐与动态自选配料组合；
- `t_table` / `t_shift`：桌台分布、钱箱状态与交接班日结记录；
- `t_kds_order` / `t_kds_ticket` / `t_kds_station`：后厨 KDS 工位映射、出餐流批与工位状态；
- `t_printing_device` / `t_printing_rule` / `t_printing_job`：云打印机设备台账、分单路由规则与打印日志；
- `t_stock_prep_forecast_run` / `t_dish_material_bom`：AI 备货预测批次与菜品原材料消耗 BOM；
- `t_api_permission` / `t_admin` / `t_role` / `t_role_permission`：细粒度 API 权限矩阵与后台管理角色。

---

## 📄 开源许可证

本项目基于 [Apache License 2.0](LICENSE) 协议开源。  
允许个人与企业免费商用、修改与集成，商业使用请保留原始版权声明与许可文件。
