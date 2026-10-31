# POS商业化收银、交班、日结与对账系统：三端构建产物与部署迁移手册

> **文档版本**：v1.0.0 (Commercial Production Release)  
> **发布日期**：2026-10-03  
> **适用范围**：云端服务端（Server）、管理/收银客户端（Cashier POS & Admin）、厨显端（KDS App）  
> **对应任务清单**：`tasks/active/POS-shift-daily-close-commercial-todo-20261003.md` (Phase 0 ~ Phase 5 全链路闭环)

---

## 一、三端构建产物清单

本次发布涵盖系统核心三端，所有产物均已在 Windows 11 / JDK 11 / Flutter 3.41.6 稳定环境下完成全量测试与 Release 编译打包：

| 端别 | 平台/格式 | 产物物理绝对路径 | 文件大小 | 生产配置/特征 |
| :--- | :--- | :--- | :--- | :--- |
| **云端服务端 (Server)** | Java Runnable JAR | `server/target/diancan-0.0.1-SNAPSHOT.jar` | ~70 MB | 包含 V014~V018 Flyway 迁移脚本、不可变账本服务、渠道对账引擎、影子切读控制器 |
| **收银与管理端 (Cashier POS)** | Windows 64位桌面端 | `admin_panel_flutter/build/windows/x64/runner/Release/laofei_cashier.exe` | 91.6 KB (主程序) + 资源/动态库 | 生产环境 API 锁死（`https://www.laofei.com.cn`）、不可变账本盲盘交班、Z报表热敏排版 |
| **收银与管理端 (Cashier POS)** | Android 离线/手持 APK | `admin_panel_flutter/build/app/outputs/flutter-apk/app-release.apk` | 79.0 MB | 适配 Android 7.0+ POS 触屏终端、蓝牙/USB 小票打印、渠道对账三层全景审核 |
| **厨显端 (KDS App)** | Windows 64位桌面端 | `KDS_front/kds_app/build/windows/x64/runner/Release/kds_app.exe` | 可执行程序 + runner资源 | 局域网+云端双通道无感容灾，支持厨房流水大屏触控与叫号联控 |
| **厨显端 (KDS App)** | Android 挂壁平板 APK | `KDS_front/kds_app/build/app/outputs/flutter-apk/app-release.apk` | 57.7 MB | 适配 10寸~21寸 厨房商用挂壁平板，WebSocket 长连接心跳保活 |

---

## 二、数据库升级与 Flyway 迁移规范

### 1. Flyway 脚本清单与依赖顺序

数据库升级由 Flyway 自动管理，服务端 JAR 启动时会自动检测并应用未执行的迁移。若生产环境限制自动 DDL，可由 DBA 依次执行以下脚本：

1. **`V014__payment_ledger.sql`**：
   - 创建不可变支付流水表 `t_payment_ledger`；
   - 引入唯一性约束 `uk_payment_ledger_req (shop_id, request_id, entry_type, channel)` 防止网络抖动导致的重复记账；
   - 建立索引 `idx_payment_ledger_order` 与 `idx_payment_ledger_day`。
2. **`V015__drawer_session_and_cash_movement.sql`**：
   - 创建钱箱会话表 `t_drawer_session` 与不可变现金流水表 `t_cash_movement`；
   - 建立虚拟列与唯一索引 `UNIQUE KEY uk_active_drawer (shop_id, terminal_id, drawer_code, active_slot)`，在 MySQL 物理层杜绝同设备存在多个开启状态的钱箱；
   - 扩充 `t_shift` 班次关联字段。
3. **`V016__daily_close_snapshot_and_precheck.sql`**：
   - 创建日结不可变快照表 `t_daily_close_snapshot` 与日结调整单表 `t_daily_adjustment`；
   - 引入订单、支付台账、钱箱流水三水位线（`cutoff_ledger_id`, `cutoff_movement_id`, `cutoff_order_id`）与 SHA-256 数据签名防篡改机制。
4. **`V017__reconciliation_and_channel_statement.sql`**：
   - 创建外部渠道对账批次表 `t_channel_statement_batch` 与明细表 `t_channel_statement_entry`；
   - 引入批次 SHA-256 文件防重唯一约束 `uk_statement_batch_hash`；
   - 创建对账差异处理单表 `t_reconciliation_case`（支持责任人留痕与状态流转审计）。
5. **`V018__backfill_and_cutover.sql`**：
   - 为 `t_payment_ledger` 增加数据溯源字段 `source VARCHAR(32) DEFAULT 'NATIVE'` 与数据可信度等级 `trust_level VARCHAR(32) DEFAULT 'TRUST_HIGH'`；
   - 创建历史回填审计日志表 `t_ledger_backfill_log`，记录扫描数、插入数、涉及金额、异常 JSON 与执行数据签名。

---

## 三、历史数据回填与平滑切读实施流程

为确保历史线上订单无缝平稳过渡至新架构，必须遵循以下“演练 -> 回填 -> 影子核对 -> 切读”的标准迁移作业 SOP。

### 步骤 1：全量历史数据演练（Dry Run）
在不对数据库产生任何写修改的前提下，扫描所有结账历史订单，评估数据健康度并生成数据哈希签名。

- **调用接口**：`POST /admin/migration/ledger/backfill`
- **请求 Payload**：
  ```json
  {
    "dry_run": true,
    "shop_id": null
  }
  ```
- **验证输出**：
  - 检查返回中的 `total_scanned_orders`（扫描历史订单总数）、`inserted_ledger_rows`（预估生成流水条数）；
  - 确认 `anomalies_count`（分项金额与订单净应收不符的异常单数）。若有异常单，记录其 `order_no` 和不平衡原因；
  - 记录本次演练生成的 `integrity_hash`（SHA-256 数据防篡改摘要）。

### 步骤 2：执行历史账本幂等回填
- **调用接口**：`POST /admin/migration/ledger/backfill`
- **请求 Payload**：
  ```json
  {
    "dry_run": false,
    "shop_id": null
  }
  ```
- **核心安全保障**：
  - 回填数据全部被打上 `source = 'BACKFILLED_ORDER'`，绝不冒充原生交易流水；
  - 缺失收银员凭证与设备信息的历史订单，规范填入 `operator_id = null`，`terminal_id = 'UNKNOWN'`；
  - 数学不变量平衡的记录赋予 `trust_level = 'TRUST_HIGH'`，存在不平衡差异的记录赋予 `trust_level = 'TRUST_SUSPECT'`；
  - 接口具备严格幂等性，已存在于台账的订单自动跳过，多次重复调用安全无害。

### 步骤 3：双写影子验证（Shadow Verification）
在切读前，以特定门店与营业日为单位，运行双向影子比对，核实旧订单口径与新台账口径是否 100% 对齐。

- **调用接口**：`POST /admin/migration/ledger/shadow-verify`
- **请求 Payload**：
  ```json
  {
    "shop_id": 1,
    "business_day": "2026-10-03"
  }
  ```
- **放行硬性门禁**：
  - 仅当响应中 `ready_for_cutover == true`，且 `variance_fen == 0`，`discrepancies` 列表为空时，方可批准切读；
  - 若存在差异，必须先核实未对平订单并处理完毕。

### 步骤 4：无损切读新台账（Read Cutover）
- **调用接口**：`POST /admin/migration/ledger/cutover`
- **请求 Payload**：
  ```json
  {
    "read_source": "PAYMENT_LEDGER"
  }
  ```
- **生效机制**：
  - 服务端配置项 `finance.ledger.read_source` 切换为 `PAYMENT_LEDGER`；
  - 渠道营收统计（`AdminDailyController#byChannel`）及报表直接从不可变台账表 `t_payment_ledger` 聚合，彻底解决历史遗留的查询空表缺陷。

### 步骤 5：紧急回滚预案（Rollback SOP）
若切读后发现任何业务不适或需临时降级，执行读源回切即可：
- **调用接口**：`POST /admin/migration/ledger/cutover`
- **请求 Payload**：
  ```json
  {
    "read_source": "LEGACY_ORDER"
  }
  ```
- **安全保障**：回退仅切换数据读取路由，**绝不物理删除**新写入的不可变账本数据，确保后续再次切读时数据零丢失。

---

## 四、服务端部署指南（Spring Boot）

### 1. 运行环境配置
- **操作系统**：Linux (CentOS 7+ / Ubuntu 20.04+) 或 Windows Server 2022
- **Java 环境**：OpenJDK 11 / Oracle JDK 11 或更高版本
- **数据库**：MySQL 8.0+（字符集 `utf8mb4`, 排序规则 `utf8mb4_unicode_ci`）

### 2. 生产启动示例（Systemd 服务）
创建服务文件 `/etc/systemd/system/diancan.service`：
```ini
[Unit]
Description=Diancan Cloud Backend Service
After=syslog.target network.target mysql.service

[Service]
Type=simple
User=appuser
Group=appgroup
WorkingDirectory=/opt/diancan/server
ExecStart=/usr/bin/java -Xms1024m -Xmx2048m \
    -Dspring.profiles.active=prod \
    -Dfile.encoding=UTF-8 \
    -jar /opt/diancan/server/diancan-0.0.1-SNAPSHOT.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启动并验证服务：
```bash
sudo systemctl daemon-reload
sudo systemctl enable diancan
sudo systemctl start diancan
sudo systemctl status diancan
```

### 3. Nginx 反向代理配置（含 WebSocket 升级）
```nginx
server {
    listen 443 ssl http2;
    server_name www.laofei.com.cn;

    ssl_certificate /etc/nginx/ssl/laofei.crt;
    ssl_certificate_key /etc/nginx/ssl/laofei.key;

    # 后端 REST API
    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 客户端安装包静态下载通道（支持 HTTP 206 断点续传，避免命中前端 SPA index.html 导致 SHA-256 哈希校验失败）
    location /packages/ {
        proxy_pass http://127.0.0.1:18080/packages/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 500m;
    }

    # KDS & 收银 WebSocket 实时通道
    location /ws/ {
        proxy_pass http://127.0.0.1:18080/ws/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

> **避坑排查（重要）**：
> 若在 Nginx 中将根路径 `/` 部署为单页应用（SPA）并配置了 `try_files $uri $uri/ /index.html;`，当客户端请求未在 Nginx 中显式配置代理的静态安装包路径（如 `/packages/...`）时，Nginx 会以 HTTP 200 状态码返回 `index.html`。这会导致客户端将 HTML 文本保存为安装包并触发“安装包 SHA-256 完整性哈希校验失败，已被删除以防篡改”报错。
> 系统现已原生支持并默认使用 `/admin/app/packages/` 直链，由于 `/admin/` 默认已被反代，可自动免疫此问题。若仍需直接访问 `/packages/`，请确保 Nginx 包含了上述 `location /packages/` 代理块。

---

## 五、客户端部署指南（Cashier POS & KDS）

### 1. 收银端 Windows 桌面部署
- **目标终端**：前台收银 PC / 触屏一体机（Windows 10/11 x64）。
- **部署步骤**：
  1. 将打包目录 `admin_panel_flutter/build/windows/x64/runner/Release/` 打包成 zip 发布；
  2. 解压到收银机指定目录（例如 `D:\POS\Cashier\`）；
  3. 创建 `laofei_cashier.exe` 桌面快捷方式；
  4. 首次启动使用管理员账号登录，在“设置”中绑定前台 58mm/80mm 热敏打印机驱动与钱箱开箱端口。

### 2. 收银端 Android 手持/移动 POS 部署
- **目标终端**：商用手持收银机（如商米 Sunmi、联迪、智掌柜等 Android POS 设备）。
- **部署步骤**：
  1. 使用 USB 线连接设备并开启调试模式，或将 `admin_panel_flutter/build/app/outputs/flutter-apk/app-release.apk` 上传至内部企业应用市场；
  2. 执行安装：`adb install -r app-release.apk`；
  3. 打开应用，输入门店账号密码登录并授予存储与打印权限。

### 3. 厨显端（KDS）挂壁平板 / 厨房大屏部署
- **目标终端**：后厨挂壁式防油触控平板（Android）或厨房一体机（Windows）。
- **部署步骤**：
  1. **Android 平板**：安装 `KDS_front/kds_app/build/app/outputs/flutter-apk/app-release.apk`；
  2. **Windows 一体机**：解压 `kds_app/build/windows/x64/runner/Release/` 并运行 `kds_app.exe`；
  3. 首次启动时，扫描前台或管理端配对二维码完成快速配对；
  4. 绑定工作站档口队列（如“热菜档”、“凉菜档”、“烤炉档”），长连接自动连入云端及局域网收银机，开启实时同步。

---

## 六、部署验收检查表（Checklist）

- [ ] 数据库完成 V014~V018 迁移，表结构及约束完整就绪。
- [ ] 历史订单完成 Dry Run 演练与正式回填，审计日志写入 `t_ledger_backfill_log`。
- [ ] 运行影子核验 `POST /admin/migration/ledger/shadow-verify`，确认 net_variance = 0 且 ready_for_cutover = true。
- [ ] 读源切换为 `PAYMENT_LEDGER`，验证管理端日报表渠道数据正常显示。
- [ ] 收银端完成一次盲盘交班流程演练，50元超额长短款成功触发店长授权审批。
- [ ] 收银端发起日结，验证四项阻断检查、三水位线抓取与 Z 报表小票打印。
- [ ] 厨显端长连接与局域网热备切换正常，出餐划菜双向状态一致。
