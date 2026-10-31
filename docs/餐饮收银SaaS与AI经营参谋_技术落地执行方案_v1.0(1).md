# 餐饮收银 SaaS 与 AI 经营参谋平台｜完整技术落地执行方案

> **Technical Implementation Blueprint v1.0**  
> 编制日期：2026-10-08　｜　研发状态：**基于数据库快照与 OpenAPI 的设计评审稿，尚未验证运行中代码/生产库**  
> 面向对象：Java 后端、Web/Flutter/小程序前端、数据库工程师、测试、运维、产品负责人和 AI 编程 Agent  
> 基线资料：`db_diancan.sql`（2026-09-07 导出）、`openapi(1).yaml`（OpenAPI 3.0.3）、《餐饮收银 SaaS 与 AI 经营参谋平台 PRD V1.0》（2026-10-08）。

## 0. 执行结论：先隔离、再收费、再分析、最后引入 AI

**落地路线：保留现有 Java 收银核心和 API → 建立租户与门店归属 → 隔离平台订阅支付 → 建立统一经营指标 → 引入第三方 Excel/CSV → 基于证据生成 AI 诊断与经营策略。**

这不是一个从零重写 POS 的项目，也不应在一开始拆成许多微服务。建议采用**Java 模块化单体 + 异步任务 Worker（可同一代码仓库独立部署）+ MySQL + Redis（如已有）+ 私有对象存储 + 第三方大模型**。初期先提供“免费收银 + 高级分析订阅 + 独立数据导入分析”三个入口。

### 0.1 六条绝对工程红线

1. **不能让订阅/AI/导入故障阻断点餐、结账、退款、出餐和基本查单。** 免费版在会员到期后继续营业；平台账单与餐厅交易严格分离。
2. **不能把现有 `t_order.merchantId` 当作 SaaS `tenant_id`。** 该字段参与现有商户号/统计过滤，已有默认值 `"1"`，语义与租户所有权不同。
3. **不能相信请求传入的 `shop_id`、`X-Shop-Id` 或 `merchant_id` 就代表已授权。** 必须在服务端完成用户→租户→门店→功能权限→套餐权益校验。
4. **不能直接以现有数据库快照作为生产库真相。** OpenAPI 描述了部分快照里没有的后续表与能力；上线前必须补齐真实运行库 `SHOW CREATE TABLE`、增量 migration、后端实现与部署版本证据。
5. **不能让 LLM 直接计算或写入营收、利润、价格和库存。** 所有经营数值来自确定性指标引擎；AI 默认只读，只能提出建议。
6. **不能为了 SaaS 改造重写现有 KDS Cloud-first 权威模型。** 沿用 `/kds/v2/*` 与云端设备 Token 权限，异步只读取合法业务事件；KDS 数据采集不能反向依赖 AI。

### 0.2 设计决策清单

| 编号 | 本方案默认决策 | 原因/后续核验 |
|---|---|---|
| ADR-01 | 保留现有 Java 应用，新增 `saas-*` 边界模块 | 降低营业链路回归风险；未提供实际代码，不能假设 Maven/Gradle/框架版本 |
| ADR-02 | 新建 `saas_tenant`、`saas_store`，POS 店映射 `t_shop.id` | 同时支持有 POS 与纯导入商家；不强迫纯导入商家初始化收银设备 |
| ADR-03 | POS 内各业务表分阶段做租户安全改造 | `t_order` 等部分表 `shop_id` 可为空；菜品、分类、用户等缺乏租户维度 |
| ADR-04 | 收银与平台会员费使用两套订单、商户号及对账域 | 避免商户经营实收混入 SaaS 收费；财务可核对 |
| ADR-05 | 新分析统一 `saas_*` 规范层，不直接让 AI 查 POS SQL | 外部来源统一、版本化数据口径与可复现性 |
| ADR-06 | 会员权限 = RBAC × 店铺范围 × 功能权益 × 额度 | 防止“买了套餐就所有员工都能看成本” |
| ADR-07 | MySQL 5.7 兼容性为当前样本最低基线 | SQL dump 报告 MySQL `5.7.44-log`；升级数据库需单独评估 |
| ADR-08 | 报告根据“源数据快照 + 规则版本 + 模型版本”固化 | 既能复盘，也能避免同源重复扣费/重复生成 |
| ADR-09 | 对旧客户端保持接口及报文兼容；高级分析优先新路由 | 现有 OpenAPI 已有 466 个 path，不能草率修改大量调用方 |
| ADR-10 | V1 不提供自动续费、自动采购或 AI 自动作单 | 降低支付/合规/误操作风险；之后按产品需求扩展 |

## 1. 输入资料审计与可信边界

### 1.1 实际检查的文件

| 资料 | 审计结果 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| `db_diancan.sql` | 107 个 `CREATE TABLE`；导出标注 MySQL 5.7.44，时间 2026-09-07 | 快照时表名、列、索引、已有业务结构 | 当前线上是否部署了后续 migration、表是否已有数据、实际存量大小 |
| `openapi(1).yaml` | YAML 可解析，约 466 个路径、516 个 HTTP 操作、256 个 schema；`info.version=1.2.272`，描述顶部写到 `v1.2.279` | 对外约定的接口、权限码、历史变更说明 | 接口一定已在实际代码中实现、部署版本与文档一致 |
| PRD V1.0 | 免费收银、专业版、AI 经营版、独立分析版；V1.0→V1.3 阶段划分 | 产品目标和验收原则 | 新模块已经存在或具有真实支付授权 |

**特别风险：** SQL 快照中未发现 `t_access_policy`、`t_role_policy`、`t_admin_permission_override`、`t_daily_close_snapshot`、`t_payment_ledger` 等表；但 OpenAPI 较新变更说明引用了相应的权限/结算能力。**判断为“快照与接口描述不一致，待验证”，不能直接定性为线上缺失。** 不允许因为快照里未出现就自动重新创建与现有迁移可能重名的表。

### 1.2 当前可复用的数据结构

| 现有表 | 核心字段/关系 | 本项目用途 | 需要处理的问题 |
|---|---|---|---|
| `t_shop` | `id, code, settle_time, status` | POS 门店基础信息 | 无归属 tenant；时区字段待补；结算日注释与新 API 语义需统一 |
| `t_admin`,`t_admin_shop`,`t_admin_role` | 员工与门店、角色关联 | 沿用 POS 账号和员工权限 | 员工/角色未显式拥有租户归属，跨租户授权风险 |
| `t_role`,`t_permission`,`t_role_permission`,`t_api_permission` | RBAC、接口权限映射 | 复用岗位权限内核 | 需区分全局模板权限与租户自定义角色；新资源权限要落库 |
| `t_order`,`t_order_detail` | `shop_id,order_no,pay_time,transac_status`；明细 `mId,dish_id,refunded_quantity,line_type` | 主营收、商品销售与退款事实 | `t_order.shop_id` 可空；订单号只有普通索引；商品明细依赖主单关联；套餐防重复计算 |
| `t_payment` | `order_no,amount,pay_time,shop_id` | 旧支付事实/对账线索 | `shop_id` 可空；不能默认其等于不可变支付台账真源 |
| `t_daily_stat` | `stat_date,shop_id,total_amount,discount_amount,refund_amount,material_cost` | 已有日结报表辅助校验 | `shop_id` 可空；`UNIQUE(stat_date,shop_id)` 无法防多行 NULL；与新快照/调整单需核对 |
| `t_dish`,`t_dish_shop`,`t_category` | 全局菜品/分类与门店覆盖价 | 商品维度和成本 | 菜品及分类缺 tenant；跨租户同名菜品复用必须阻断 |
| `t_dish_material_bom`,`t_inventory_bom`,`t_material` | 成本配比、版本化 BOM、原材料 | 条件性成本与备货 | 单位换算、成本有效期、实际耗用缺失时不能宣称真实利润 |
| `t_kds_ticket` | `shop_id,order_id,detail_id,accepted_at,done_at,served_at,completed_wait_seconds` | 分析出餐耗时 | 缺失事件与档口状态必须分开标识；不能擅自重放操作 |
| `t_stock_prep_forecast_*` | 现有备货预测结果表 | 未来复用预测能力 | 不重复研发；确认已有算法的数据窗口/准确率及授权归属 |
| `t_report_export_job` | 导出任务、门店、令牌 | 复用报表任务经验 | 文件与任务必须严格按租户、门店、套餐权限校验 |
| `t_payment_merchant_config` | `shop_id,channel,mch_id,private_key_ref` | **仅餐厅支付配置** | 不可用于平台会员收费商户号 |
| `t_user` | openid、手机号、余额 | POS 顾客身份 | 无 tenant/store 字段，顾客资产与营销隔离需专项迁移 |

### 1.3 关键接口复用矩阵（以 YAML 为准）

| 现有路径 | 当前用途 | 商业化改造决策 |
|---|---|---|
| `GET /admin/report/dashboard` | 今日营业、复购等组合看板 | **拆分响应级权限**：免费仅今日基础统计，复购等高级字段按权益决定；避免一次返回绕过前端隐藏 |
| `GET /admin/report/daily`,`/weekly`,`/monthly` | 经营报表 | 可复用计算，但历史高级分析用新 API 封装并统一授权；原业务必须保留必要对账 |
| `GET /admin/analytics/business`,`/business/trend`,`/dishes` | 经营/趋势/菜品分析 | 对已有 `statistics:view` 增加 entitlement，不可只限制新页面 |
| `GET /admin/daily/pre-check`,`POST /admin/daily/settle`,`GET /admin/daily/z-report` | 日结与法定/必要对账 | **核心经营保障，不因订阅到期拦截**；先校对 API 依赖的真实表结构 |
| `GET /admin/daily/grossProfit`,`GET /admin/report/shopProfit` | 毛利/利润分析 | 仅当成本数据可信时展示；升级专业版后解锁；验收营业额与费用口径 |
| `GET /admin/merchant/orders` 与 `/summary` | 依既有 `merchant_id` 筛选 | **不能**用它代替 SaaS 租户授权；读取前必须先完成所属门店约束 |
| `POST /admin/order/list`,`GET /cashier/order/search` | 查询订单、售后 | 免费保留按角色受控的必要历史查单与合理导出 |
| `POST /cashier/order/checkout`,`POST /cashier/order/refund` | POS 结账/退款 | 收银核心链路原样兼容；不添加 AI 远程依赖 |
| `GET /kds/v2/bootstrap`,`GET /kds/v2/changes`,`POST /kds/v2/commands` | Cloud-first KDS | 继续设备 Token 权威验证，不改命令和事件序列；分析仅消费副本 |
| `GET/POST /admin/access/employees`,`POST /admin/access/evaluate` | 员工权限/策略解释 | 继承 POS 授权，但租户上下文必须强校验；不要把“订阅权益”塞进原岗位策略 |
| `POST /admin/reconciliation/import` | **微信/支付宝渠道对账单**导入 | 不作为第三方经营报表导入入口；两类业务的语义与存储严格隔离 |
| `POST /admin/reports/exports` | 报表导出 | 免费必要导出与高级聚合导出分权，下载路径与对象存储防 IDOR |
| `GET /admin/report/stockPrepForecast` | 备货预测 | 已有预测，后期纳入 AI 建议数据源；先验证质量与 `persist` 副作用授权 |

### 1.4 源资料冲突和上线前必须解决的 8 项问题

| 问题编号 | 证据 | 处理方式 | 阻断级别 |
|---|---|---|---|
| G-01 | API 元数据 `1.2.272`，变更说明到 `1.2.279` | 以部署 commit/构建号和实际运行接口为准，纠正文档版本 | 必须核对 |
| G-02 | 权限 v2、日结快照/台账在 API 被引用，但不在 SQL 快照 | 获取全部 `db_migration_*.sql`、`SHOW CREATE TABLE`、migration 清单 | **阻断租户付费开放** |
| G-03 | API 旧历史描述曾用 12h 结算窗/`close_time` 兜底；较新描述要求 24h `[D settle_time,D+1 settle_time)` | **以 v1.2.258 和目标产品口径**建立统一业务日测试；实测所有 API | **阻断财务分析** |
| G-04 | 部分 `analytics` 参数 description 仍写“endTime 含”、order_time 和旧兜底 | 新分析 API 明确左闭右开、事件时间和新参数；旧 API 做适配器 | **阻断口径验收** |
| G-05 | 多表 `shop_id` 可空、全局菜品/分类/顾客 | 制定数据治理、租户归属、读写隔离、回填失败隔离队列 | **阻断外部多租户 POS** |
| G-06 | `t_order.merchantId` 默认 `"1"` 且过滤出现在统计代码说明 | 新增 `tenant_id` 专用标识；`merchantId` 原样保留、明确支付语义 | **阻断租户映射** |
| G-07 | API 已有经营分析、成本、备货预测 | 先复用已有算法并做新口径比较；不重复创建同类 SQL/接口 | 重复开发风险 |
| G-08 | 数据库导出于 9 月，PRD 编制于 10 月 | 此方案不能证明当前生产代码实现状态；迁移前补齐版本快照 | **阻断生产 DDL** |

## 2. 目标架构与领域边界

### 2.1 逻辑分层

```text
   商家 Web / Flutter POS / 微信小程序 / 独立分析门户
                         │
             API Gateway / 认证鉴权
                         │
    ┌────────────────────┴────────────────────┐
    │             现有 POS 域                 │
    │ 商品·桌台·订单·收银·退款·KDS·日结·会员   │
    │ 保持已有路由/回调/打印/设备权威           │
    └─────────────┬───────────────────────────┘
                  │ 事务提交后 Outbox / 增量读取
      ┌───────────┴──────────────┐
      │ SaaS 租户与门店 / RBAC 桥接 │
      │ 套餐权益 / 平台计费与收款     │
      └───────────┬──────────────┘
                  │
    第三方 CSV/Excel ── 导入/去重/校验 ── 统一经营规范层
                                              │
                         经营指标引擎(确定性/版本化)
                                              │
                         异常检测与证据快照引擎
                                              │
                           AI 诊断/策略/报告
                                              │
                       站内通知 / 反馈 / 复查追踪
```

### 2.2 Java 工程模块与职责

| 模块包（建议） | 职责 | 对外依赖限制 |
|---|---|---|
| `com.xxx.saas.tenant` | Tenant/Store/Membership/Context | 可以桥接 `t_shop`，不能绕过本域做跨商户查询 |
| `com.xxx.saas.entitlement` | FeatureFlag/PlanVersion/FeatureGrant/Quota | POS 核心功能全部 fail-open（只对会员判断而言）；付费功能 fail-closed |
| `com.xxx.saas.billing` | 平台订阅订单、异步支付确认、续期/退款 | 使用独立平台商户配置，不调用 `t_payment` 写商家收入 |
| `com.xxx.saas.ingestion` | 来源注册、上传、列映射、批次回滚、质量校验 | 原始文件隔离；不信任导入字段里的 tenant/store |
| `com.xxx.saas.canonical` | 标准订单/商品/支付/退款/KDS 投影 | 不在 POS 核心事务里执行重型聚合 |
| `com.xxx.saas.metrics` | 统一口径指标、版本快照、覆盖率 | 纯确定性，无 LLM、无改价能力 |
| `com.xxx.saas.insight` | 规则异常、证据卡、建议跟踪 | 默认只读，仅消费 metrics 快照 |
| `com.xxx.saas.ai` | 脱敏、模型适配、JSON Schema 校验、额度 | 不接收任意 SQL；白名单工具 |
| `com.xxx.saas.jobs` | Outbox、队列、日报、周报、重试与幂等 | 队列宕机不影响 POS 主流程 |
| `com.xxx.saas.ops` | 平台后台、人工纠错、审计、客服 | 双重身份+操作原因+临时授权 |

**部署原则：** 初期可以同一 Java 仓库分包、分数据库 schema 或同库 `saas_` 前缀；Worker 可以独立启动进程。避免为了“微服务”先引入分布式事务。生产数据量大时再将规范数据与指标处理迁入专用数据库。对象存储、数据库凭证及支付密钥应采用不同权限集。

## 3. SaaS 身份、租户、门店与原账号桥接

### 3.1 三种完全不同的 ID

- `tenant_id`：订阅/账单/数据所有权主体（商家组织），不可变，不等于收单商户号。
- `saas_store_id`：平台内的经营门店，支持 `source_mode=POS/IMPORT_ONLY/HYBRID`，每个门店归属一个 tenant。
- `legacy_shop_id`：现有 `t_shop.id`，仅 POS 门店存在；纯导入门店可以为 NULL。历史 POS API 继续用既有 shop ID，但服务端必须先解析映射。

### 3.2 身份桥接

商户老板在平台注册 → 创建 `saas_tenant` 和 `saas_member(owner)` → 创建 `saas_store` → 选择“开通 POS 门店”或“纯导入门店”。如果开通 POS，再通过带审计的 provisioning 事务创建 `t_shop` 并绑定 `saas_store.legacy_shop_id`，**不得由客户端传任意既有 shop_id 后声称归属自己**。

现有 `t_admin` 账号继续服务旧 POS，并通过 `saas_member.legacy_admin_id` 建立关联。商户平台登录和 POS 员工登录可以分阶段统一，但第一阶段必须实现 `TenantContextResolver`：从签名 JWT 的身份与服务端 membership 查授权门店集合，再将原有 `t_admin_shop` 限制为同租户授权。跨租户协作人员使用显式多 membership，不能借用全局角色绕过隔离。

### 3.3 请求授权流程（后端统一拦截器）

```text
JWT/device Token 验证
  → 识别主体(用户/设备/平台运营)
  → 查询 tenant membership 与成员状态
  → 由 saas_store_id 映射 legacy_shop_id + 校验同 tenant
  → 检查原业务 RBAC / 门店授权 / 角色策略(含 DENY)
  → 如为收费功能，再校验有效权益 + 使用额度
  → 查询自动注入服务端作用域；返回审计 trace_id
```

**不允许**仅在 Controller 里 `if (role == admin)` 判断租户；也不允许一个店主自定义请求头绕过 membership。设备 Token（KDS、打印）也应绑定所属门店及租户。WebSocket 握手、任务重试、对象存储下载、WebMCP 工具调用必须采用同一资源授权原则。

### 3.4 原始数据隔离三阶段

- **阶段 A：限定单现有商户 + 纯导入试点**。把当前 POS 门店归属唯一 tenant；外部租户只能进独立导入数据层，不直接使用共享 POS 写路径，直到安全验证通过。
- **阶段 B：小规模新 POS 租户**。完成 `t_shop` 归属、菜品/分类/角色/顾客信息隔离改造，旧接口完整回归且隔离测试绿灯才开启新 POS 门店注册。
- **阶段 C：多门店/跨组织完善**。跨店 BI 与共享商品模板遵循同 tenant，平台级商品模板必须显式复制到租户，禁止默认跨租户共享修改。

## 4. 现有库的数据库迁移总策略

### 4.1 采用 Expand → Backfill → Verify → Switch → Contract

1. **预检查**：备份和恢复演练；读取生产库 `information_schema`、表行数、索引、字符集/时区，保留 schema 指纹；对所有 DDL 出具锁表/复制延迟评估。
2. **扩展**：新建 `saas_*` 表、新增可空映射列；新增只读兼容代码，不删除旧字段、不改 POS 请求格式。
3. **回填**：一次性建“旧店归属清单”，扫描旧订单、支付、员工、菜品；能确定归属才填充，不确定进异常隔离表。
4. **双读/影子比对**：旧报表与新指标在同店同时间窗比较；差异分解至每个订单/退款/支付流水。
5. **灰度切换**：按 tenant 白名单启用新权限检查和新分析；仍保留旧 POS 核心路径。
6. **收紧**：修复所有空 shop、无效跨店引用后，再考虑 `NOT NULL`、唯一约束、代码删除及旧字段下线；合同期内保留必要兼容。

**MySQL 5.7 注意：** 大表 `ALTER TABLE` 不保证在线无锁；使用适当在线迁移工具、低峰灰度和复制滞后观察，新增唯一索引之前先清理重复；不要把下方概念 DDL 直接应用到生产库。

### 4.2 历史数据必跑审计 SQL（只读样例）

```sql
-- 空门店归属（不要自动归到默认 1 号店）
SELECT COUNT(*) AS missing_shop FROM t_order WHERE shop_id IS NULL;
SELECT COUNT(*) AS missing_shop FROM t_payment WHERE shop_id IS NULL;
SELECT COUNT(*) AS missing_shop FROM t_table WHERE shop_id IS NULL;
-- 一个订单号是否出现在多店/多条业务主单中
SELECT order_no, COUNT(*) AS n, COUNT(DISTINCT shop_id) AS stores
  FROM t_order GROUP BY order_no HAVING n > 1 LIMIT 100;
-- 商品明细与主单缺失关联
SELECT COUNT(*) AS orphan_detail FROM t_order_detail d
  LEFT JOIN t_order o ON o.id=d.mId WHERE o.id IS NULL;
-- POS 员工被授予的门店是否横跨不同拟定 tenant：须在 saas_store 映射回填后查询
-- 检查所有全局菜品、分类、总部配置、顾客资产在新商家接入时是否可见
```

### 4.3 针对高风险旧表的专项改造

| 对象 | 当下风险 | 稳妥改造 |
|---|---|---|
| `t_shop` | 无 tenant | 以 `saas_store.legacy_shop_id UNIQUE` 为主映射；双向校验与禁止重复认领 |
| `t_order` | `shop_id NULL` / 旧默认 merchantId | 不从 merchantId 推导 tenant；先冻结异常订单集合；API 查询总通过映射店铺作用域 |
| `t_order_detail` | 无店铺列 | **必须连接主单 `t_order.id=mId` 后取所属店**，绝不可只按 `dish_id` 跨店查明细 |
| `t_payment` | 订单号非全局唯一、shop nullable | 根据明确的订单 ID/交易号/门店 + 支付时间映射；无法唯一匹配进待核对 |
| `t_dish`,`t_category` | 全局产品字典 | 新增 tenant 范围或租户副本；旧“按名称复用 t_dish”只能在**同租户**内做，绝不跨租户归并同名商品 |
| `t_user`,顾客余额/积分 | 微信 openid 与会员资金可能共享 | 按 appid/openid/tenant 的客户关系建店铺会员映射；余额迁移需账本核对与业务审批，不粗暴复制 |
| `t_role`,`t_admin` | 全局角色和员工 | 租户内独立 role 绑定/系统角色模板；原 `t_admin_shop` 必须限制为同租户店 |
| `t_daily_stat` | `NULL shop_id` 唯一键可多行，指标口径旧 | 新分析采用独立版本化快照；旧日结不可原地改写 |
| `t_hq_settings`、`t_system_config.shop_id=0` | 全局默认参数和密钥 | 区分平台默认、租户默认、店铺覆盖；商户严禁修改平台/其他租户默认值 |
| 打印设备、KDS Token、导出文件 | 看似归店、实际可能通过 ID 跳越 | 对文件、设备、工单及 WebSocket 全链路重新做 tenant/store 作用域测试 |

## 5. 新增数据库设计：逻辑表清单、关系和约束

> **以下表定义为新增设计，不是声称旧库已经存在；迁移版本号从实际代码仓库最新 migration 后继续编号。** 不使用物理外键硬锁住旧 POS 事务链路，数据库通过唯一键/索引保障局部一致性，业务服务校验租户所有权。

### 5.1 表清单与字段契约

| 模块 | 建议新表 | 必填关键字段、关键唯一约束 |
|---|---|---|
| 身份 | `saas_tenant` | `id,tenant_code,name,status,created_at`; `UK(tenant_code)` |
| 门店 | `saas_store` | `id,tenant_id,legacy_shop_id NULL,name,source_mode,timezone,settle_time,status`; `UK(legacy_shop_id)`（NULL 可多条），`IDX(tenant_id,id)` |
| 成员 | `saas_member` | `id,tenant_id,principal_id,legacy_admin_id,role,status`; `UK(tenant_id,principal_id)`；角色/作用域可附加明细表 |
| 授权门店 | `saas_member_store` | `member_id,saas_store_id`; `UK(member_id,saas_store_id)` |
| 套餐 | `saas_plan`,`saas_plan_version` | `plan_code,version,status,effective_at,currency,price_fen,features_json`；历史版本不可覆写 |
| 权益 | `saas_subscription`,`saas_entitlement_usage` | 以 `saas_store_id` 为授权主体；订阅周期、状态、权益快照、账期使用量；周期唯一键 |
| 账单 | `saas_billing_order`,`saas_billing_payment` | 平台订单号、幂等键、应付金额、支付渠道交易号、回调原文摘要、状态；商户订单维度分离 |
| 数据来源 | `saas_data_source` | `tenant_id,saas_store_id,source_type,external_provider,scope,authorization_status` |
| 文件批次 | `saas_import_batch`,`saas_import_row_error`,`saas_import_mapping` | `source_id,file_sha256,object_key,cover_from/to,status,row_counts,mapping_version`；报错行号和原因 |
| 原始事实 | `saas_raw_record`（或加密对象存储文件） | `batch_id,entity_type,record_key,payload_ref,status`；禁止储存不必要的顾客敏感字段 |
| 统一事实 | `saas_fact_order`,`saas_fact_order_item`,`saas_fact_payment`,`saas_fact_refund`,`saas_dim_product`,`saas_fact_kds_event` | `tenant_id,saas_store_id,source_id,source_record_id,normalized fields,source_version,ingested_at`；按来源去重 |
| 数据质量 | `saas_data_issue`,`saas_data_revision` | 字段缺失/冲突/覆盖率、修复记录、同源修订版本 |
| 指标 | `saas_metric_snapshot`,`saas_metric_value` | `metric_version,source_fingerprint,window_start/end,dimension,value,completeness,computed_at` |
| AI | `saas_insight`,`saas_ai_report`,`saas_insight_action` | 证据快照 ID、规则/提示词/模型版本、结构化建议、状态与复查计划 |
| 异步 | `saas_job`,`saas_outbox`,`saas_delivery` | 状态、去重键、重试次数、租户/门店作用域、事件时间、投递审计 |
| 安全运维 | `saas_audit_event`,`saas_quarantine` | 操作人、授权原因、动作对象、前后摘要、追踪号；无法归属的历史数据 |

### 5.2 重要数据库关系

```text
saas_tenant(1) ── (N) saas_store ── (0..1) t_shop（仅POS门店）
       │                   │
       ├── saas_member ─── saas_member_store
       └── saas_plan  ← saas_subscription(按 saas_store 授权)
                                  │
                    saas_billing_order ── saas_billing_payment
                                  │
saas_store ── saas_data_source ── saas_import_batch ── saas_raw_record
       │                  └────────────── 规范经营事实
       │                                     │
       └────────────────────────── saas_metric_snapshot
                                             │
                                 saas_insight / saas_ai_report
                                             │
                                      saas_insight_action
```

### 5.3 推荐的 MySQL 5.7 基础 DDL 样例

**安全提示：** 以下可作为 Flyway/Liquibase 迁移的**审阅起点**，不是与现有数据库逐表比对过的可生产直接执行脚本。上线前须按真实字符集、主键与索引命名进行检查。使用 `BIGINT` 存储新 ID；金额使用 `BIGINT *_fen`，避免 decimal/float 不同语言混算。

```sql
CREATE TABLE saas_tenant (
  id BIGINT NOT NULL AUTO_INCREMENT,
  tenant_code VARCHAR(48) NOT NULL,
  name VARCHAR(128) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id), UNIQUE KEY uk_saas_tenant_code (tenant_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE saas_store (
  id BIGINT NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT NOT NULL,
  legacy_shop_id INT NULL,
  name VARCHAR(128) NOT NULL,
  source_mode VARCHAR(16) NOT NULL COMMENT 'POS/IMPORT_ONLY/HYBRID',
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Shanghai',
  settle_time CHAR(5) NOT NULL DEFAULT '06:00',
  status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_saas_store_legacy_shop (legacy_shop_id),
  KEY idx_saas_store_tenant (tenant_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE saas_member (
  id BIGINT NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT NOT NULL,
  principal_id VARCHAR(100) NOT NULL,
  legacy_admin_id INT NULL,
  role_code VARCHAR(40) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_member_tenant_principal (tenant_id,principal_id),
  KEY idx_member_legacy_admin (legacy_admin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE saas_plan_version (
  id BIGINT NOT NULL AUTO_INCREMENT,
  plan_code VARCHAR(32) NOT NULL,
  version INT NOT NULL,
  price_fen BIGINT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'CNY',
  feature_snapshot_json LONGTEXT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_plan_version (plan_code,version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE saas_subscription (
  id BIGINT NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT NOT NULL,
  saas_store_id BIGINT NOT NULL,
  plan_version_id BIGINT NOT NULL,
  status VARCHAR(20) NOT NULL COMMENT 'ACTIVE/EXPIRED/CANCELED/REFUNDED',
  period_start DATETIME(3) NOT NULL,
  period_end DATETIME(3) NOT NULL,
  version INT NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_sub_store_status_end (saas_store_id,status,period_end),
  KEY idx_sub_tenant (tenant_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE saas_billing_order (
  id BIGINT NOT NULL AUTO_INCREMENT,
  tenant_id BIGINT NOT NULL,
  saas_store_id BIGINT NOT NULL,
  order_no VARCHAR(64) NOT NULL,
  client_idempotency_key VARCHAR(128) NOT NULL,
  plan_version_id BIGINT NOT NULL,
  amount_fen BIGINT NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'CREATED',
  payment_deadline DATETIME(3) NOT NULL,
  paid_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_billing_order_no (order_no),
  UNIQUE KEY uk_billing_idem (tenant_id,client_idempotency_key),
  KEY idx_billing_store_created (saas_store_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE saas_billing_payment (
  id BIGINT NOT NULL AUTO_INCREMENT,
  billing_order_id BIGINT NOT NULL,
  channel VARCHAR(24) NOT NULL,
  provider_txn_id VARCHAR(128) NOT NULL,
  amount_fen BIGINT NOT NULL,
  status VARCHAR(24) NOT NULL,
  provider_event_id VARCHAR(128) NULL,
  paid_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_billing_provider_txn (channel,provider_txn_id),
  UNIQUE KEY uk_billing_provider_event (channel,provider_event_id),
  KEY idx_payment_billing_order (billing_order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**补充约束：** `saas_subscription` 的“同一门店同一时刻仅有一个生效订阅”需要在业务事务中使用门店计费锁行或专用 `saas_store_billing_state` 单行 CAS 控制；**仅有上面的索引不能防止订阅区间重叠**。`saas_billing_payment` 的平台事件 ID 可能为空，具体唯一键以各渠道通知 ID 的可用性调整。开通、续期、退款都必须锁住同一门店计费状态行。

### 5.4 规范事实与幂等键

以下数据所有权字段建议统一出现：`tenant_id BIGINT NOT NULL`,`saas_store_id BIGINT NOT NULL`,`source_id BIGINT NOT NULL`,`source_record_id VARCHAR(128) NOT NULL`,`source_revision INT NOT NULL`。

- 订单：`UNIQUE (source_id,source_record_id)`，另保留跨来源的 `canonical_order_key`（不默认由金额+时间计算）。
- 明细：`UNIQUE (source_id,source_record_id,external_line_key)`，如果文件只有订单聚合没有行 ID，要用稳定业务行号+上传版本，不能仅凭产品名 dedupe。
- 支付：`UNIQUE (source_id,external_payment_id)`；订单多次分摊支付保留多条事实。
- 退款：`UNIQUE (source_id,external_refund_id)`；退款事件与退款成功状态分离。
- 导入批次：`(saas_store_id,source_id,file_sha256,mapping_version,cover_from,cover_to)` 幂等；文件 hash 不能单独代表相同业务范围。
- 指标快照：`(saas_store_id,metric_version,window_start,window_end,source_fingerprint,filter_hash)`。

**切记：** 文件可以重传，源订单可以更正，支付可以延迟成功，部分退款可能发生于以后一天。规范事实层应支持“来源修订 + 失效旧版本 + 重算受影响时窗”，绝不静默覆盖已有结算快照。

## 6. 套餐、权益与功能权限落地

### 6.1 套餐矩阵（沿用 PRD 的试点价格，不作为正式销售定价）

| 权益键 | 免费 POS | 专业 59/月 | AI 经营 149/月 | 独立 AI 99/月 |
|---|---|---|---|---|
| `pos.order.create`,`pos.checkout`,`pos.refund.approved` | 可用 | 可用 | 可用 | 不提供 POS |
| `pos.order.history.basic`,`data.export.basic` | 可用 | 可用 | 可用 | 仅本身授权数据 |
| `dashboard.business_day.view` | 可用 | 可用 | 可用 | 导入后可用 |
| `analytics.history.view`,`analytics.product.view` | 不可用 | 可用 | 可用 | 可用 |
| `analytics.cost.view` | 不可用 | 数据齐备 | 数据齐备 | 数据齐备 |
| `data.import.file` | 不开放 | 选配 | 可用 | 可用 |
| `ai.insight.read`,`ai.report.daily`,`ai.report.weekly` | 仅有证据的预览 | 不可用 | 可用 | 可用 |
| `ai.chat.use` | 不可用 | 不可用 | 配额使用 | 较小配额 |
| `data.external_api.sync`,`ai.stock.forecast` | 后续 | 后续 | 后续 | 后续 |

### 6.2 权限计算公式

```text
allow = authenticated
    AND membership.active
    AND store.tenant_id == membership.tenant_id
    AND store in effective_store_scope
    AND existing_RBAC.allow(permission, context)
    AND NOT existing_policy.explicit_deny
    AND (is_core_free_feature OR entitlement.active(feature_key))
    AND (is_unmetered OR quota.reserve_successful(feature_key,request_id))
```

- 核心 POS 免费功能的 SaaS 计费模块失败时 **不应调用该模块或阻断请求**；但原有合法权限、收款安全校验仍然严格执行。
- 高级功能的权益缓存失效/账单状态不明时 **拒绝产生新的收费分析任务**，保留合法的历史成果查看与必要查单。
- `FREE` 不是“所有数据都可以匿名查看”；免费表示可用套餐权益，不改变用户 RBAC 和数据归属。
- 对 `GET /admin/report/dashboard` 这类聚合了免费与收费内容的旧接口，建议分组投影 `freeBusinessDay`、`premiumInsight`；遗留 JSON 字段需要兼容迁移期的响应，只在后台授权成功时附带高级数据；切换前编写快照测试。

### 6.3 权益检查的 Java 伪代码

```java
public void requirePremium(StoreContext ctx, String feature, String requestKey) {
    memberGuard.requireActiveAndInStore(ctx.actorId(), ctx.tenantId(), ctx.storeId());
    rbacGuard.require(ctx.actorId(), ctx.legacyShopId(), featurePermission(feature));
    Entitlement ent = entitlementRepo.getActive(ctx.storeId(), feature, now());
    if (ent == null) throw new FeatureRequiredException("PLAN_UPGRADE_REQUIRED");
    quotaService.reserveIdempotently(ctx.storeId(), feature, requestKey);
}
// 核心 POS Controller 不调用 requirePremium；分析请求进入异步队列前校验权益。
// 配额最终核销需与任务成功/失败结算一致；失败任务按规则回退预留额度。
```

### 6.4 漏洞防护清单

前端隐藏高级入口不等于服务端授权。必须覆盖：直接请求旧分析接口、修改 `shop_id`、改写请求 `tenant_id`、切换 JWT 会员状态、过期后绕过缓存、OpenAPI 自动生成工具/WebMCP、导出任务和下载 URL、历史报告的 `reportId` 枚举、跨店 WebSocket 订阅及后台 Worker 处理错误租户等场景。

## 7. 平台订阅计费：独立账单域、幂等回调、会员生命周期

### 7.1 账单状态机

```text
CREATED → PENDING_PAYMENT → PAID → ENTITLEMENT_GRANTED
   ├── EXPIRED_UNPAID
   └── CLOSED_UNPAID
PAID → REFUND_REQUESTED → REFUNDING → REFUNDED
                              └── REFUND_FAILED（人工核对）
```

订阅以 `FREE / ACTIVE / EXPIRED / CANCELED / REFUNDED` 管理权益；**支付订单状态与订阅状态不可复用同一列**。到期可以通过数据库当前时间与 `period_end` 即时判定，同时异步维护状态作为展示/报表；不能只靠凌晨定时任务更新到期。

### 7.2 创建订单与支付回调

1. 商户老板选择当前门店和套餐，后端读 `saas_plan_version` 固定 `price_fen`、功能清单、账期、退款说明。
2. `POST /api/saas/v1/stores/{storeId}/billing/checkout` 携带 `Idempotency-Key`；服务端创建唯一平台支付订单，生成平台自有商户号的预支付参数。
3. 客户端展示支付结果仅为交互信号，**不得直接触发开通**。
4. 平台支付回调必须校验证书/签名、商户号、币种、订单号、金额、支付状态、防重放与时间窗；同一个渠道事件、交易号及内部订单只处理一次。
5. 在一个数据库事务中锁 `saas_billing_order` 和门店账期锁行，落支付流水 → 更新支付状态 → 创建/延长订阅 → 写入 `saas_outbox(EntitlementChanged)` → 提交事务。
6. 事务外消费 Outbox，清理缓存、发送站内消息；重试只保证最终投递，**业务侧必须幂等**。
7. 未到回调通过主动查单任务补偿；金额不符、订单映射不符进入人工核查，不先发放权益。

### 7.3 续费、升级、退款细则

- **同套餐续费**：`new_start = max(now,old_period_end)`；`new_end = new_start + 购买周期`，保留原周期历史记录。
- **初期跨套餐切换**：为避免退款差价与财务复杂度，建议只能到期生效，购买前清晰提示。之后可增加按剩余天数补差价。
- **退款**：以渠道实际退款成功通知/主动查询为依据撤销未来权益；保存平台退款流水及工单，已产生的历史商户业务数据绝不删除。
- **临近到期**：建议到期前 7 天/3 天/当天通过站内通知提醒；未授权不得发营销短信。
- **独立 AI 版**：无需 `t_shop`；它的账单对应 `saas_store`，不会为导入门店创建餐厅支付订单。
- **人工试用**：如未来需要赠送试用，使用单独 `grant_type=TRIAL/PROMOTION` 并记录操作者和有效期，不伪造支付单。

### 7.4 财务和支付隔离

| 内容 | 餐厅营业收款 | SaaS 平台订阅费 |
|---|---|---|
| 交易订单 | `t_order` / 实际生产收银交易账本 | `saas_billing_order` |
| 对账 | 收银渠道、钱箱/日结/Z 报表 | 平台商户号、账单、订阅、发票/退款 |
| 收款主体 | 由各餐饮商家实际合法收款配置决定 | SaaS 运营主体的商户号 |
| 收入指标 | 商户当期餐饮净实收 | 平台 SaaS ARR/MRR，不进入餐饮 BI |
| 故障影响 | 核心 POS 优先恢复 | 仅暂停升级购买/权益变更，不停用餐厅收款 |

**重点：** `t_payment_merchant_config` 中的旧 `shop_id=0` 表示原系统“全门店默认”，**绝不意味着 SaaS 平台收款账户可以让所有其他法人门店复用**；商户自有收款凭据的权限隔离需在新 POS 租户商业化前专项完成。

## 8. 第三方数据导入：与支付渠道对账单彻底区分

### 8.1 支持范围与输入路径

V1.1 支持商家手动上传 `CSV / XLSX`（建议初期单文件 ≤20MB、≤50,000 行、最多 2 个工作表；以性能测试结果调整）；支持四类数据：**订单明细、商品销售汇总、支付/退款明细、成本表**。部分导出模板仅含汇总数据，应允许“部分可分析”，不能伪造缺失的原子记录。

**现有 `/admin/reconciliation/import` 用于微信/支付宝渠道官方对账文件，不等于“第三方 POS 经营数据导入”。** 独立实现 `saas.ingestion` 与 `/api/saas/v1/imports`，数据库表、校验和错误消息独立。

### 8.2 异步导入状态机

```text
CREATED → UPLOADED → SCANNING → PARSING → NEEDS_MAPPING
  → VALIDATING → PREVIEW_READY → AWAITING_CONFIRMATION
  → COMMITTING → COMMITTED → METRICS_DIRTY → COMPLETED
       ├── QUARANTINED（病毒/无合法权限/格式异常）
       ├── CONFLICT（无法确认重复/业务范围重叠）
       ├── FAILED_RETRYABLE
       └── FAILED_FINAL
COMPLETED → REVERSAL_REQUESTED → REVERSED（规范事实版本标失效，重算）
```

“上传成功”不能等于“经营金额已经加入指标”；导入必须由商家在预览后确认。单次导入按批次提交、失败可恢复。对大表采用后台分批扫描，UI 轮询进度，不将所有数据放入 API 请求 JSON。

### 8.3 文件安全与隐私

- 浏览器先向后端申请上传会话及限定权限的预签名上传 URL；限制 `tenant_id/store_id`、文件类型、扩展名、MIME 与魔数、大小、压缩炸弹、ZIP entries、公式、外部链接和宏；后端从受控对象存储读取。
- CSV 防公式注入：当导出给用户的数据单元格以 `= + - @` 等开头时作为文本安全转义；解析导入时不执行任何公式和远程内容。
- XLSX 用流式解析（如 Java SAX 模式），不加载几十 MB 工作簿到内存；采用 CPU/内存/时间与行数上限。
- 原文件默认私有存储、短期留存（如 30 天可配置），规范事实只保存分析所必需的内容；手机号、身份证、顾客地址、支付凭据默认忽略或脱敏。
- 保存文件 `sha256`、上传人、来源、对象存储 Key、授权凭据及留存到期日；删除/撤销需记录审计，不绕过依法必要的财务留存。

### 8.4 自动字段映射和校验

| 标准字段 | 第三方可能叫法 | 必要性 | 检查 |
|---|---|---|---|
| `external_order_id` | 订单号/流水号/单号 | 订单文件必需 | 重复与跨文件稳定性 |
| `ordered_at` | 下单时间/创建时间 | 订单分析必需 | 时区与格式 |
| `paid_at` | 收款时间/支付时间 | 实收时点分析必需 | 状态成功时不得无故缺失 |
| `order_status` | 单据状态/支付状态 | 实收必需 | 取消/挂单/已结账不可混淆 |
| `external_line_id` | 明细序号/商品行号 | 行级分析推荐 | 缺失时必须可稳定推导且提示 |
| `product_name`,`quantity` | 菜品/名称、份数 | 销量必需 | 数量、套餐组件、退菜 |
| `item_amount_fen` | 商品成交额/行金额 | 商品金额分析必需 | 不强迫把总单折扣视为已分摊 |
| `paid_amount_fen` | 实收/收款金额 | 实收分析必需 | 同支付事件唯一、渠道、退款方向 |
| `refund_amount_fen` | 退款/撤销 | 净额计算必需 | 状态为成功才入账 |
| `sku_cost_fen`,`valid_from` | 成本/成本价、启用日 | 条件性毛利 | 未覆盖项目标记未知成本 |
| `shop_code` | 店铺编码/门店 | 多店文件必要 | 必须匹配该 tenant 名下的门店 |

AI 可提出字段映射建议，但**涉及营收、支付状态、金额含税/扣费、退款、金额单位的映射必须人工确认**。映射模板持久化版本号，并保存确认记录。

### 8.5 重复来源与冲突处理（严禁静默加总）

- 同一来源、同一业务原始 ID：按 `source_id + external_order_id` 幂等；新版本走修订并保留审计。
- 同一门店的 POS 与 CSV 出现相同区间：先检查是否为外卖平台/聚合渠道重复导出的同一笔交易；有确定匹配证据则关联来源，不把金额加两次。
- 无可靠跨来源关联键：输出 `POSSIBLE_DUPLICATE` 和重叠金额范围，人工选择主来源或标记“此区间仅作交叉核对”，不直接算入营收。
- “销售汇总”与“订单明细”同时到达：汇总默认作为对账检查，不与明细相加。
- 发生撤销导入时：只撤销该批次所提供的规范事实有效版本；若有后续修订依赖，阻断并引导先处理依赖。

### 8.6 V1.1 导入 API 约定

| 方法与路径 | 业务作用 | 关键返回 |
|---|---|---|
| `POST /api/saas/v1/stores/{id}/imports/upload-session` | 创建可控上传会话 | `uploadId,objectKey,uploadUrl,expiresAt` |
| `POST /api/saas/v1/stores/{id}/imports` | 根据 uploadId 创建解析任务 | `batchId,status` |
| `GET /api/saas/v1/stores/{id}/imports/{batchId}` | 任务状态/解析数/错误数 | `status,progress,coverage,missingFields` |
| `PUT /api/saas/v1/stores/{id}/imports/{batchId}/mapping` | 人工确认映射 | `mappingVersion,validationTaskId` |
| `GET /api/saas/v1/stores/{id}/imports/{batchId}/preview` | 金额对账与异常预览 | 预估新增/重复/冲突行数及金额 |
| `POST /api/saas/v1/stores/{id}/imports/{batchId}/commit` | 幂等确认导入 | `status,committedRevision` |
| `POST /api/saas/v1/stores/{id}/imports/{batchId}/reverse` | 请求撤销并重算 | `reversalJobId,status` |
| `GET /api/saas/v1/stores/{id}/data-sources` | 来源、覆盖、同步状态 | 来源列表与 `dataHealth` |

**端到端对账标准：** 抽取一份真实第三方报表，导入后的每日净实收/有效订单/退款与源平台对应口径逐项比较，差异必须能落到具体记录、舍入、跨日支付或渠道手续费等原因。不得仅通过“总金额大致接近”验收。

## 9. 统一数据模型与原系统字段映射

### 9.1 内部适配器映射（需与运行时 SQL 校验）

| 规范事实字段 | 当前表/字段 | 转换规则 | 风险/备注 |
|---|---|---|---|
| `source_order_id` | `t_order.id` 或 `order_no` | 内部优先主键+门店+来源 | `order_no` 非唯一约束，先查重 |
| `store_id` | `t_order.shop_id` | `shop_id→saas_store.legacy_shop_id` | 为 NULL 的订单隔离，不默认认领 |
| `ordered_at` | `t_order.order_time` | 按旧库时区解释，再归一 UTC | 来源 `DATETIME` 不带时区 |
| `paid_at` | `t_order.pay_time` | 实际支付成功时点 | 空支付时间的历史例外须明确数据质量 |
| `status` | `t_order.transac_status` | success/unsettled/cancelled 映射至规范枚举 | `order_receiving` 是接单/清台状态，不等于付款状态 |
| `discount` | `t_order.discount_amount` | decimal 元精确转 long 分 | 优惠券/赠送金不要重复抵扣 |
| `refunded_amount` | `t_order.refund_amount` | 成功累计退款辅助核对 | 要与退款真实台账或回调核对，避免重复记账 |
| `line_id` | `t_order_detail.id` | 按 `mId=t_order.id` 强关联 | 退菜与套餐父子项需特殊处理 |
| `product_id` | `t_order_detail.dish_id` | 优先正式菜品 ID，缺失用版本化名称映射并标低可信 | `t_dish` 是全局表，必须做租户作用域 |
| `quantity` | `t_order_detail.quantity-refunded_quantity` | 有效销量，且区分明细状态 | 套餐组件可能为成本明细，不应再算商品营业额 |
| `item_revenue` | `t_order_detail.total_price` | 必须核实是否含优惠/套餐拆分 | 避免对子项重复求和 |
| `payment` | `t_payment` 及真实新账本（待核实） | 真实成功交易；区分现金/微信/支付宝/储值本金/赠送金 | 仅 t_payment 不足以宣称完整不可变支付账本 |
| `kds_completed` | `t_kds_ticket.done_at` | 出餐事件候选 | 传菜 `served_at` 与烹饪完成 `done_at` 分开 |
| `cost` | `t_dish.cost_price`,`t_dish_material_bom`,`t_inventory_bom` | 成本按生效期/门店 SKU/BOM 选择 | 无入库单价/损耗数据时不能算真实利润 |
| `business_day` | `t_shop.settle_time` | 用统一 `BusinessCalendarService` 衍生 | 旧注释/旧 API 版本互相冲突，需金样本 |

### 9.2 规范事实建议最小字段

```text
OrderFact: tenantId,storeId,sourceId,sourceOrderId,orderId,
           orderedAtUtc,paidAtUtc,operationBusinessDate,paidBusinessDate,
           grossItemFen,discountFen,deliveryFeeFen,serviceFeeFen,
           status,canonicalRevision,qualityFlags
OrderItemFact: sourceLineId,orderId,productId,quantity,refundQuantity,
           originalItemFen,paidItemFen,allocatedDiscountFen,
           lineType,comboHeaderId,costFen,costCoverage
PaymentFact: providerPaymentId,orderId,channel,status,amountFen,paidAtUtc,
           paymentType(SALE|TOP_UP|OTHER),originSource
RefundFact: providerRefundId,orderId,paymentId,status,refundFen,
           refundedAtUtc,refundedLineIds
KdsFact: itemId,stationId,acceptedAtUtc,startedAtUtc,doneAtUtc,servedAtUtc,
         qualityFlags
```

**注意：** 为避免财务二次计数，内部账必须明确“订单层净销售额”与“支付/退款现金流”两套口径，禁止将多次支付累计值和订单实收再次相加；充值不能直接算作餐饮销售收入。

## 10. 营业日、财务口径、指标引擎与数据质量

### 10.1 统一营业日算法（新引擎强制）

根据当前 OpenAPI 较新修订，POS 报表的目标营业日 `D` 视为**起始日**，时间窗：`[D settle_time, (D+1) settle_time)`，左闭右开；不同门店按照各自时区和结算时刻换算真实 instant 再聚合。

```java
// 仅示意，生产中校验 zone/time 配置和 DST 特殊情形
LocalDate bizDate(Instant time, ZoneId zone, LocalTime settleTime) {
    ZonedDateTime z = time.atZone(zone);
    LocalDate d = z.toLocalDate();
    return z.toLocalTime().isBefore(settleTime) ? d.minusDays(1) : d;
}
// start = D @ settleTime(zone); end = D+1 @ settleTime(zone); 使用 >= start AND < end
```

**注意 API 历史变更陷阱：** 当前 OpenAPI 描述里同时出现旧版本“以结算日为截止日”、“12 小时营业窗”、“endTime 含结束秒”、以及较新“以营业日起始日为 D 的 24 小时窗口”。实际改造应以 **统一后端规范服务 + 新契约金样本测试**作为真相，不应照搬某个旧 Controller 的默认参数。对已日结的历史财务，不得无审计重新改写旧 Z 报表。

### 10.2 指标字典 v1（确定性计算）

| 指标键 | 规范算法（示意） | 排除/限制条件 |
|---|---|---|
| `gross_merchandise_fen` | 有效订单商品行优惠前金额之和 | 不含配送费/额外服务费；套餐父子行只能选一种计数口径 |
| `net_sales_fen` | 成功餐饮销售实收减成功餐饮退款 | 按实际 `paid_at/refunded_at` 现金流归属，充值及赠送充值单独计 |
| `net_order_value_fen` | 订单商品/服务口径净成交额 | 与 `net_sales_fen` 不同，跨日退款/坏账需单列差异 |
| `valid_paid_orders` | 成功已支付且非全额取消订单数 | 部分退款保留该订单，后续全额退款按选定口径是否保留订单明确标记 |
| `avg_ticket_fen` | `net_sales_fen / valid_paid_orders` | 分母 0 返回 NULL；不要强制为 0 |
| `refund_rate` | 退款订单数 / 可比有效已支付订单数 | 订单数口径与金额退款率需分别命名 |
| `item_sold_qty` | 商品行售出数减退款数 | 组合套餐组件明细不得重复计数营业额 |
| `contribution_margin_est_fen` | 有成本证据的净销售 − 对应已知商品成本 | 仅在成本覆盖度达阈值时整体展示“估算毛利” |
| `product_mix_share` | 产品有效净销售额 / 同期有效净销售总额 | 无可靠商品分摊不输出 |
| `kds_wait_p50/p90` | 合法事件的分位等待时间 | 必须声明起点（接单）与终点（制作完成/传菜），超时/缺失覆盖率 |
| `report_coverage` | 完整可计算天数/期望天数、有效订单/抽样订单 | 对完整性不足的报告给出显式告警 |

**时间维度明确选择：** 营收现金流按 `paid_at/refunded_at`，订单创建与订单量可按 `ordered_at` 的经营日展示；报告页面必须标明使用的是哪一种，且比较期严格一致。退款在后一营业日发生，应在退款日现金流中扣减，并在“原订单经营归因”视图保留单据对应关系。旧日结快照与新现金流必须支持差额桥接表。

### 10.3 数据质量门控

| 级别 | 例子 | 允许输出 |
|---|---|---|
| `COMPLETE` | 支付状态/支付时间/退款完整，来源无冲突 | 准确范围内的营收、订单、趋势及证据结论 |
| `PARTIAL` | 有订单无部分退款详情、成本覆盖 65% | 非依赖缺失字段的指标，明确标注估算与限制 |
| `INSUFFICIENT` | 只有 2 天数据、5 笔订单 | 基础事实、样本不足提示，不生成趋势性诊断 |
| `CONFLICTED` | POS 与 CSV 重叠且无法去重 | 分来源展示和冲突解决，不自动合并生成收入结论 |

利润分析建议 `cost_coverage_ratio >= 0.95` 才展示门店整体**估算毛利**；租金、工资、外卖佣金和税费未录入时绝不展示“净利润”。AI 常规趋势诊断按 PRD 首期最低建议：**至少 7 个可比营业日 + 30 笔有效订单**；不同异常规则可使用更高的样本阈值。

### 10.4 指标缓存与修订一致性

```text
POS支付成功/退款/旧单补录/导入批次COMMITTED
  → Outbox(FeatureDataChanged(storeId, businessDates, sourceRevision))
  → 标记对应日期与可比历史窗口 DIRTY
  → 后台批量更新标准事实及指标快照
  → 形成新的 sourceFingerprint + metricVersion
  → 旧报告保留生成时证据快照，UI 标识“有新数据可重算”
```

首期可每 1～5 分钟增量更新经营看板（目标当日数据 ≤60 秒则需更快轻量增量），日报使用关账后稳定窗口；指标快照以 `version` 保持可重现。窗口内跨日退款需同时失效相关经营归因、现金流视图。

## 11. AI 经营诊断：从事实到可验证行动

### 11.1 不直接“把数据库扔给大模型”

**全流程：** 数据质量门控 → SQL/规则引擎计算指标 → 统计显著变化/异常候选 → 生成结构化证据包 → 脱敏和预算检查 → 调用 LLM 解释及提出建议 → JSON Schema 验证 → 数值证据引用一致性检查 → 输出诊断卡 → 人工反馈 → 同指标口径复盘。

首期先实现 4 类确定性规则：**商品销售结构异常、客单价变化、时段波动、退款/取消异常**。KDS 出餐积压、成本与毛利、备货预测等视数据覆盖率后续开放；不要重复已经存在的 `stockPrepForecast` 算法。

### 11.2 规则引擎契约

```json
{
  "ruleCode": "PRODUCT_SHARE_DROP",
  "ruleVersion": "1.0.0",
  "storeId": 123,
  "window": {"start": "2026-09-21", "endExclusive": "2026-10-05"},
  "metricRefs": ["m_001", "m_002"],
  "thresholds": {"minDays": 7, "minOrders": 30, "dropRatio": 0.20},
  "quality": {"grade": "COMPLETE", "coverage": 0.97},
  "candidateSeverity": "MEDIUM"
}
```

该 JSON 为**模拟契约**。数值由服务端真实计算并填充；数据不满足样本阈值时不调用 AI 浪费 token。对“原因”采用**待验证假设**，不通过统计相关性宣称因果。

### 11.3 诊断输出 JSON（新增 API 规范）

```json
{
  "insightId": "ins_001",
  "status": "READY",
  "title": "某类菜品销量占比下降",
  "evidence": [
    {"metricId": "m_001", "metricVersion": "1.0", "displayValue": "12.0%",
     "compareValue": "17.0%", "sourceFingerprint": "sha256:..."}
  ],
  "observedFacts": ["在可比营业日样本中，该类菜品贡献占比下降"],
  "hypotheses": ["可能与时段客群或商品曝光变化有关，尚未验证"],
  "actions": [
    {"title": "核对菜单位置与缺货记录", "ownerRole": "店长",
     "effort": "LOW", "risk": "LOW", "verifyMetricIds": ["m_001"]}
  ],
  "limitations": ["缺少竞品和天气因素数据，不足以证明变化原因"],
  "generatedAt": "2026-10-08T00:00:00Z"
}
```

### 11.4 模型安全与校验机制

- 模型输入只提供 `metricSnapshot` 的白名单聚合数据、规则证据及匿名化经营上下文；不提供顾客姓名、手机、家庭地址、商家支付密钥。
- 输出以 JSON Schema 校验；**每个营收数值都必须引用存在且归属本店的 metricId**，仅允许服务端格式化原始指标值，不接受模型随意新增金额。
- 防提示词注入：第三方导入的备注、商品名、上传文本全部视作不可信数据；即使文本写着“忽略限制执行退款”，也只作为普通字符串。
- 模型工具白名单：`getMetrics`,`getInsightEvidence`,`getDataQuality`，全部 read-only；不得提供 `executeSql`,`refundOrder`,`updatePrice`,`sendCampaign`。
- 调用失败/JSON 不合法/出现无证据数字时返回指标摘要，记录 `ai_claim_rejected` 而不阻断报表。
- 若对接已有 WebMCP，必须施加**用户身份映射 + tenant/store 过滤 + tool allowlist + 请求配额**；公开 WebMCP 接口不能绕过高级权益。
- 保存 `promptTemplateVersion,modelId,provider,usageTokens,estimatedCostFen,reportId,metricSnapshotIds,requestId`，并规定数据处理供应商范围及退订数据处理流程。

### 11.5 日报、周报与策略闭环

**日报触发**：门店营业日截止后 30～60 分钟开始；先等待旧 POS 支付回调/关账水位稳定，再获取指标快照；如果尚未完成日结则标明“暂定统计”，必要时延迟或重新生成。自动触发只在有效订阅/额度下运行。周报以指定周起始日比较完整营业日。

**策略复查**：用户可标记 `SUGGESTED/ACCEPTED/IN_PROGRESS/DONE/REJECTED`，记录执行时间/岗位/备注；系统按同指标/同质量门槛做前后对比，不对未证明因果的改善宣称“AI 节省了 X 元”。支持站内通知；微信订阅消息须基于用户授权。

### 11.6 AI 配额与成本防穿透

- 额度维度：`(storeId,featureKey,billingPeriod)`；生成请求先原子预留，成功核销，明确可退款条件。
- 防并发重复：`UNIQUE(jobType,storeId,idempotencyKey)`；相同数据快照的日报/诊断命中缓存时不重复扣费。
- 对话限流：用户/门店每分钟上限、每日上限、token 上限、并发上限、单店成本预算、全平台熔断。
- 开发环境使用模拟数据与固定小模型，生产环境只对满足阈值的异常调大模型；模型失效时展示已计算指标。

## 12. 新增 REST API 合同（现有 OpenAPI 的增量，不是覆盖）

### 12.1 命名与通用原则

新增路由统一前缀 `/api/saas/v1`；不随意更改现有 `/admin/*`、`/cashier/*`、`/kds/v2/*` 的既有契约。考虑兼容 Web / Flutter / 小程序，原则如下：

- **身份**：`Authorization: Bearer <JWT>`；原 KDS 继续专用 `X-Kds-Device-Token`，不能拿员工 JWT 代签设备命令。
- **归属**：`storeId` 指 `saas_store.id`，`tenantId` 一律从认证主体及成员资格解析。旧 POS shop id 只在桥接层使用。
- **幂等**：所有扣费、上传提交、生成 AI 任务采用 `Idempotency-Key` 或领域唯一键；相同请求返回同一结果；不同内容复用 Key 返回冲突。
- **分页**：列表统一 `cursor + limit` 或可审计的页码/排序；所有查询在数据库层绑定归属。
- **时间**：新 API 使用 ISO-8601 带偏移或 UTC 时间字段；业务日使用 `YYYY-MM-DD` + 商户门店 `timezone/settle_time`；永远声明结束为 exclusive。
- **错误**：区分 `401 UNAUTHENTICATED`、`403 STORE_ACCESS_DENIED`、`403 FEATURE_NOT_INCLUDED`、`402/403 QUOTA_EXCEEDED`（与已有风格一致）、`409 IMPORT_CONFLICT`、`409 BILLING_ORDER_CONFLICT`、`422 DATA_INSUFFICIENT`、`503 DEPENDENCY_UNAVAILABLE`；**API 业务码映射应与现有项目统一**，不要只改写旧响应。
- **可见性**：只读查询、导出下载及异步结果都要在访问时再次校验，不可仅在创建任务时校验。

### 12.2 完整新增接口目录与版本

| 优先级 | 方法 | 新接口 | 权限/验收重点 |
|---|---|---|---|
| V1.0 | `POST` | `/auth/register` | 新商户/商家后台账户登记，防重复与手机号核验 |
| V1.0 | `GET` | `/me`、`/me/stores` | 仅显示成员可访问租户/门店；区分 POS 与独立导入 |
| V1.0 | `POST` | `/tenants` | 创建租户/owner/首店原子化；防并发重复 |
| V1.0 | `POST` | `/tenants/{tenantId}/stores` | 创建 IMPORT_ONLY 门店或受控 POS provisioning |
| V1.0 | `GET` | `/stores/{storeId}/entitlements` | 生效套餐、当前周期、按功能剩余额度 |
| V1.0 | `GET` | `/plans` | 套餐可见版本、币种、价目、退款条款 |
| V1.0 | `POST` | `/stores/{storeId}/billing/checkout` | 幂等创建平台订单，二次授权与支付参数 |
| V1.0 | `GET` | `/stores/{storeId}/billing/orders` | 查询本商户账单；不暴露商家顾客支付记录 |
| V1.0 | `GET` | `/stores/{storeId}/billing/orders/{orderNo}` | 支付确认 / 补偿查单状态 |
| V1.0 | `POST` | `/billing/provider/callback/{channel}` | 服务端验签与幂等；**不依赖商家登录** |
| V1.0 | `GET` | `/stores/{storeId}/dashboard/business-day` | 免费今日基础概览；返回 `asOf`,`quality`,`businessDate` |
| V1.1 | `GET` | `/stores/{storeId}/analytics/summary` | 专业版历史趋势/销售结构；确定性指标 |
| V1.1 | `GET` | `/stores/{storeId}/analytics/products` | 商品贡献、优惠与退款影响 |
| V1.1 | `GET` | `/stores/{storeId}/analytics/cost` | 成本覆盖率与估算毛利；不足时 422 或明确部分数据 |
| V1.1 | `POST` | `/stores/{storeId}/imports/upload-session` | 申请限制权限的私有存储上传会话 |
| V1.1 | `POST` | `/stores/{storeId}/imports` | 创建解析任务、后端校验权益与文件归属 |
| V1.1 | `PUT` | `/stores/{storeId}/imports/{batchId}/mapping` | 映射版本确认 |
| V1.1 | `GET` | `/stores/{storeId}/imports/{batchId}/preview` | 批次覆盖、冲突和金额预览 |
| V1.1 | `POST` | `/stores/{storeId}/imports/{batchId}/commit` | 幂等提交与下游重算 |
| V1.1 | `POST` | `/stores/{storeId}/imports/{batchId}/reverse` | 已导入批次撤销，保留历史追踪 |
| V1.1 | `GET` | `/stores/{storeId}/data-sources` | POS/CSV/API 来源与完整度 |
| V1.2 | `POST` | `/stores/{storeId}/insights/generate` | 创建诊断任务，返回 202 + jobId |
| V1.2 | `GET` | `/stores/{storeId}/insights` | 有证据的诊断卡，免费仅摘要、付费完整 |
| V1.2 | `GET` | `/stores/{storeId}/reports`、`/reports/{id}` | 报告列表与证据链接，按同一店铺授权 |
| V1.2 | `POST` | `/stores/{storeId}/insights/{id}/feedback` | 有用性反馈与策略执行状态 |
| V1.2 | `GET` | `/stores/{storeId}/jobs/{jobId}` | 异步进度；不可跨店猜测任务 ID |
| V1.2 | `GET` | `/stores/{storeId}/usage` | AI 次数、tokens、导入额度、下一周期恢复日 |
| V1.2 | `GET/PUT` | `/stores/{storeId}/report-schedule` | 设置日报/周报推送，默认站内 |
| V1.3 | `POST` | `/stores/{storeId}/ai/ask` | 基于白名单指标的只读问数，有额度 |
| V1.3 | `POST` | `/stores/{storeId}/integrations/{provider}/authorize` | 官方授权对接，真实供应商能力评估后开放 |

> 说明：`/api/saas/v1` 为新接口建议，不代表已存在于当前 OpenAPI。**完成每个后端接口后，必须同步修改 OpenAPI YAML、前端 SDK、权限映射、接口测试和变更日志。**

### 12.3 示例：查询门店权益

```json
GET /api/saas/v1/stores/123/entitlements
{
  "storeId": 123,
  "plan": {"code": "AI", "version": 2, "status": "ACTIVE",
           "periodEnd": "2026-11-08T00:00:00+08:00"},
  "features": {
    "pos.checkout": {"available": true, "reason": "CORE_FREE"},
    "analytics.history.view": {"available": true},
    "ai.report.daily": {"available": true, "remaining": 27, "resetAt": "2026-11-08T00:00:00+08:00"}
  }
}
```

### 12.4 示例：创建分析任务（异步 202）

```json
POST /api/saas/v1/stores/123/insights/generate
Idempotency-Key: insight-20261008-store123
{"businessDateFrom":"2026-09-08","businessDateTo":"2026-10-07","analysisTypes":["PRODUCT_MIX","REFUND"]}

HTTP 202
{"jobId":"j_8899","status":"QUEUED","snapshotPending":true}
```

异步结果查询返回 `QUEUED/RUNNING/SUCCEEDED/FAILED/RETRYING/CANCELED`；`SUCCEEDED` 包含 `reportId`,`asOf`,`coverage`，失败返回安全的 `errorCode` 及可操作提示，不向前端回显栈追踪与第三方模型私钥。

### 12.5 旧端点兼容的实施顺序

1. 所有原有 API 建立基线契约测试：路径、方法、认证、字段、默认返回及金额语义。
2. 新增服务端门店授权中间件，先 shadow 模式记录“潜在越权”，校正既有合法总部操作后切 hard-enforce。
3. 对旧 `GET /admin/report/dashboard` 采取响应字段层过滤；不破坏免费当日概览；费用类数据继续岗位授权。
4. 老 `/admin/analytics/*` 旧版本路径加分析套餐校验，但先通过白名单灰度、SDK 同步和回归；向商户解释商业版本差异。
5. `/admin/daily/*`,`/cashier/*` 的合法基本日结/收银操作禁止按会员状态限流；运营权限照旧。
6. 需要新增字段时使用向后兼容 optional 字段，老前端不识别字段仍正常工作；真正有破坏性变化单独升版本。

## 13. 前端、Flutter、微信小程序与 UI 任务矩阵

### 13.1 平台商家 Web 端新增页面

| 页面 | 关键状态 | 对应 API | 前端必须提示 |
|---|---|---|---|
| 商家注册与店铺建档 | 创建中、重复商户、纯导入/POS | `/auth/register`,`/tenants`,`/stores` | 平台商户与门店的区别 |
| 工作台 | 载入/营业中/暂无订单/数据滞后 | `/dashboard/business-day` | 营业日 D、数据更新时间、支付口径 |
| 会员套餐 | 免费/待支付/有效/到期/退款中 | `/plans`,`/entitlements`,`/billing/*` | 当前授权店铺、有效期、计费明细、手动续费 |
| 经营分析 | 有权限/无权限/数据不足/冲突 | `/analytics/*` | 价格解释 + 数据质量/来源限制 |
| 导入向导 | 上传→映射→校验→预览→确认→完成 | `/imports/*` | 错误行、重复记录、覆盖日期、影响金额 |
| AI 经营参谋 | 规则候选/任务中/可查看/已复查 | `/insights/*`,`/reports/*` | 数据发现、可能原因、措施、效果复查分开 |
| 数据源中心 | POS/CSV/API 及覆盖范围 | `/data-sources` | 撤销导入会触发重算 |
| 团队及门店授权 | Owner/店长/员工/财务 | `/me/stores` + 既有 access API | 不应展示他店/他商户的成员和报表 |

### 13.2 现有收银 Flutter / 小程序改造原则

- **收银高频入口不添加会员弹窗**：下单、开桌、结账、退款、厨房打印、KDS 实时订阅照常工作。
- **仅老板/管理员视图展示升级入口**：在工作台的经营提醒、数据中心入口、账号设置中展示非侵入式付费引导。
- Flutter API SDK 要区分 `LegacyShopId` 和 `SaasStoreId` 类型，禁止用同名 `shopId` 在收银与平台请求间隐式混传。
- 小程序扫码点餐的顾客身份由当前 C 端 Token 认证，不需要也不应获得商家 SaaS 管理端 JWT。
- 会员有效期/权益接口可缓存展示，但**付费功能按钮按后端鉴权失败提示升级**，不能用本地缓存绕过后端。
- 用户上传第三方数据时必须提供字段映射预览界面；不要让大模型自动把“优惠前流水”误判成实收。
- 自定义业务日调整应警告：历史报告与日结不自动重写；必须有确认与审计。

### 13.3 UI 原型流程（针对 AI 编程）

先输出**页面信息架构→交互流程→低保真原型→高保真组件样式规范→前端页面→接口联调**。不能跳过原型直接重构页面。每个 UI 需求需产生 `ui-spec.md`、状态矩阵、截图验收与组件复用清单；架构变更要同步更新项目 UI Design System 基线。

## 14. 事件驱动与任务调度：不影响 POS 主事务

### 14.1 核心事件

| 事件 | 触发来源 | 消费者 | 幂等唯一键 |
|---|---|---|---|
| `PosOrderPaid` | 旧 POS 支付成功事务提交 | 规范订单/支付投影、当日指标 dirty | `shopId+orderId+paymentRevision` |
| `PosOrderRefunded` | 成功退款/部分退款 | 退款规范事实、相关周期重算 | `providerRefundId+statusRevision` |
| `PosOrderChanged` | 加菜/退菜/取消 | 商品行快照/指标 dirty | `shopId+orderId+revision` |
| `KdsLineCompleted` | 云端权威 KDS 工单完成 | KDS 分析投影 | `shopId+detailId+revision` |
| `ImportBatchCommitted` | 商户确认导入 | 标准化投影/指标重算 | `batchId+revision` |
| `SubscriptionActivated` | SaaS 平台账单事务 | 权益缓存、通知、自动任务 | `billingOrderNo+entitlementVersion` |
| `SubscriptionExpired` | 当前时间与账期判定/调度 | 停止新付费任务 | `subscriptionId+periodEnd` |
| `MetricSnapshotUpdated` | 指标重算成功 | 报告提示重新生成/计划任务 | `store+snapshotFingerprint` |

### 14.2 可靠投递方案

- 新 POS 交易事务尽量使用**现有已落库可靠事件链路**；如果没有通用 Outbox，新增轻量 outbox 写事务，保证交易提交后事件不丢，但**不能在支付事务中调用 AI/文件处理**。
- Worker 每次按 `status=PENDING`、`next_retry_at<=now` 限量抓取任务；用数据库 CAS 或消息队列 consumer group 保证同一任务只有一执行者持有 lease。
- 投递允许“至少一次”，消费必须具备唯一幂等键；发生进程崩溃时 lease 到期恢复；失败指数退避+死信队列，人工处理要审计。
- 报告同一数据快照/规则版本/门店/报告类型只能生成一份生效版本；晚到退款导致新版本，旧报告保留“已过期”提示。
- 定期对账补偿扫描旧 POS 收银事实和规范层水位差异；KDS Cloud-first 的事件序列严格与源权威一致，读取增量不发命令。

### 14.3 关键时序示例

```text
POS 收银员 → 原 cashier API → t_order/交易台账 commit
                                      │
                                      └── Outbox(PosOrderPaid)
                                                    │
                                          Data Worker 规范映射
                                                    │
                                          指标增量/快照生成
                                                    │
                                          Rule Engine候选问题
                                                    │
                                         （订阅有效且过门槛）
                                                    │
                                              AI Report Worker
                                                    │
                                                站内通知
```

## 15. 安全体系、平台客服与合规验收

### 15.1 权限与安全防线

1. **鉴权分层**：C 端 `UserToken`、B/POS `BearerAuth`、KDS `XKdsDeviceToken`、配送第三方凭证、支付回调签名完全隔离。
2. **隐私最小化**：分析只用聚合数据；原始文件必要性评估、到期清理、顾客电话和地址默认不入 AI 输入。日志不得保存支付密钥、openid/手机号原文或收银屏敏感信息。
3. **平台客服授权**：只查看账户状态和任务元数据；敏感报表临时授权须商户许可、工单理由、有效期、字段脱敏，全部审计。
4. **密钥管理**：不同商家微信商户私钥不可保存在可下载的静态目录；仅使用安全配置与独立访问控制，出厂密钥不得放入 Git。
5. **文件与导出**：对象存储私有桶，短期 URL、按门店授权重签发、超期不可下载；重试不能复用过期授权。
6. **审计**：订阅开通/退款、成本查看、导入提交/撤销、跨店资源访问失败、平台后台敏感查询均保留不可篡改摘要和 trace。
7. **数据权利**：商家可导出自身原始/规范经营数据并申请删除；依法需留存的账务数据单独登记保留原因与期限。
8. **法规**：上线前让合规人员确认经营数据/顾客个人信息处理、第三方模型委托处理、短信/微信消息授权以及互联网支付商户资质；不把本方案当作法律意见。

### 15.2 需要单独做红队验证的对象

`shop_id` 横向越权、tenant membership ID 伪造、导出 job ID 猜测、已过期订阅缓存、CSV 注入、xlsx 外链与压缩炸弹、模型提示词注入、POS 下单 API 意外被加 entitlement 拦截、KDS 设备 Token 被商家后台账号冒用、支付回调重复/重放/签名错误、跨用户客户余额和优惠券泄漏、管理员强制下线后旧 Token 能否继续访问等。

## 16. 运维部署、监控、成本与灾备

### 16.1 环境隔离与部署拓扑

```text
CDN / HTTPS (TLS) / WAF
            │
       Java API Pod(s) ─── Redis（会话/幂等短缓存/限流）
            │                   │
      MySQL POS 主库      SaaS 表/独立逻辑数据域
            │                   │
     支付与KDS关键任务      Data Import/Metric/AI Worker
            │                   │
         Outbox      对象存储(私有文件/报告) / 模型API
            └──────── 可观测性平台 ────────┘
```

**建议发展顺序：** 初期租户数少可同库不同前缀且强隔离；当分析压力影响 POS 时先拆数据库连接池、读副本/异步作业、磁盘与 CPU 配额，再将分析库物理迁走。读副本延迟应显式显示 `asOf`，不得向用户展示为实时收款结果。

### 16.2 可观测性指标与告警

| 监控对象 | 指标 | 告警条件（建议值、需压测校准） |
|---|---|---|
| POS | 成功支付/结账成功率、接口 P95、退款回调、SQL 慢查 | POS 交易失败率显著上升时 P0 告警 |
| SaaS 授权 | 403 比例、跨租户拒绝数、权益缓存命中 | 突发异常或同源持续被拒告警 |
| 平台支付 | 支付单超时、回调验签失败、支付成功但权益未开通 | 任何已确认支付且 5 分钟权益未到账列紧急补偿 |
| 导入 | 批次失败率、解析耗时、队列积压、文件拒绝 | 任务积压/冲突高于阈值 |
| 指标引擎 | 源与规范对账差异、指标脏窗口数、更新延迟 | 关键实收对账差异 **不为零且无法解释** |
| AI | 模型错误、输出校验失败、单店 tokens/cost、缓存率 | 成本预算超限熔断、无证据结论阻断 |
| KDS | KDS ACK、增量追赶、命令冲突 | 沿用已有 `/kds/v2/diagnostics/metrics` 监控契约 |
| 数据安全 | IDOR 拒绝、敏感数据访问、导出量 | 同身份跨店频繁请求及异常批量下载 |

### 16.3 SLO / RPO / RTO（试点目标、发布前压测与演练）

- **POS 核心可用性目标 ≥99.9%/月**；SaaS 报表与 AI 不作为同步强依赖；支付渠道本身故障单独记账。
- **常用 POS API P95 <2 秒**（标准网络与指定负载）；V1 SaaS 看板有效数据滞后目标 ≤60 秒，异步分析以进度可追踪为主。
- **数据库 RPO 建议 ≤15 分钟，核心 POS RTO 建议 ≤60 分钟**；只是设计目标，必须通过备份/恢复/演练确认，未达成不得对外承诺。
- **备份**：数据库全量+增量/binlog、对象存储生命周期和版本控制、恢复演练记录；迁移前额外备份与回退检查。
- **灾备**：导入/AI 宕机可熔断暂停；账单后台异常仍允许 POS 收款和历史查单；若核心收银 API 故障则按既有容灾机制处理，**不宣称未验证的离线收银能力**。

### 16.4 AI 单店经济性模型

```text
月度单店毛利（平台）
= 订阅确认收入 − 模型 tokens / 模型 API 调用费用
  − 文件/对象存储 − 计算与数据库资源分摊
  − 支付手续费 − 可归属支持成本
```

套餐单价 59/149/99 元为 PRD 初始测试假设，必须配额化。运营后台显示付费商户数、ARPPU、30/60 日留存、每店 AI 成本、报告生成次数、人工支持时长与毛利，不以“自动生成报告次数”替代价值指标。

## 17. 测试方案：从 0 风险兼容到商业化放量

### 17.1 自动化测试分层

| 层级 | 建议技术/实现 | 核心目标 |
|---|---|---|
| 单元 | JUnit、Mockito、确定性时间 Clock 注入 | 营业日、订单净额、退款、套餐拆分、角色+权益逻辑 |
| 数据库 | Testcontainers MySQL 5.7/目标生产版本、迁移测试 | DDL 兼容、索引、`NULL shop_id`、并发锁 |
| 契约 | OpenAPI validation、历史 JSON golden samples | 旧 Flutter/小程序/POS API 响应不破坏 |
| 集成 | POS 付款→规范事件→指标→报告 | 对账一致性、延迟与幂等 |
| 并发 | 100+ 并发重复支付/续期/上传提交 | 不出现多开通、重复扣费、双批次金额 |
| 安全 | 多租户 IDOR、目录/文件越权、模型注入 | “猜到其他商户 ID 仍无法查询” |
| 性能 | k6/JMeter、实际门店流量回放 | AI/导入高负载不影响 POS P95 |
| 故障 | 关 Worker、断模型、延迟支付回调、DB failover | POS 关键操作照常；订阅补偿最终一致 |
| UAT | 老店真数据+第三方标准样本 | 和真实收款、Z 报表、原系统导出可逐笔对账 |

### 17.2 不可跳过的验收用例（P0–P2）

| ID | 用例 | 正确结果 |
|---|---|---|
| SEC-01 | 商户 A 请求商户 B 的 `storeId/reportId/batchId` | 拒绝，且不能推断 B 的数据是否存在 |
| SEC-02 | 修改 JWT claims、伪造 `X-Shop-Id` 和 `merchant_id` | 服务端不赋予额外租户权限 |
| SEC-03 | 商家 Owner 授予他租户员工访问自己店铺 | 必须校验合法组织协作授权，不能绕过归属 |
| SEC-04 | 仅收银员角色访问成本分析/平台账单 | 拒绝；套餐已买也不改变 RBAC |
| SUB-01 | 相同支付平台回调 10 次 | 只开通一次；支付金额和有效期正确 |
| SUB-02 | 支付通知先于前端跳转/支付订单状态更新 | 可恢复，不丢权益也不多开通 |
| SUB-03 | 付费到期时，店员正结账/退款 | POS 交易正常，付费 AI 新任务不再执行 |
| SUB-04 | 退费、失败、支付超时并发 | 有明确最终状态和账单对账，无负账期 |
| POS-01 | 自有老门店全部历史 API 原样操作 | 查单/点餐/收银/KDS/日结回归通过 |
| POS-02 | 新租户新增同名菜品 | 不关联或更改其他租户的 `t_dish` |
| POS-03 | 顾客在两家不同商户同一手机号/openid | 会员余额/优惠券不得交叉显示 |
| TIME-01 | `settle_time=06:00`，01:59/05:59/06:00 订单 | 前两者归前一营业日，06:00 归新营业日 |
| TIME-02 | 订单当晚已支付、下周退款 | 原单与本周净实收变化可追溯、不可双扣 |
| TIME-03 | 不同门店时区/settle_time 聚合 | 每店独立归日后汇总，窗口无重叠、无遗漏 |
| DATA-01 | 一文件重复上传、同映射重复提交 | 相同 batch 重放，规范金额不重复 |
| DATA-02 | POS 与第三方文件重叠相同订单 | 自动冲突门控，不静默二次计入 |
| DATA-03 | 文件只有商品销量，无支付状态 | 允许销量分析，不生成“实收营业额” |
| DATA-04 | 套餐父子项、混合支付和部分退款 | 商品销量、净实收、成本均可逐条核对 |
| DATA-05 | 异常或不合法 XLSX、公式 CSV | 拒绝/无害化处理，无 RCE/数据泄露 |
| AI-01 | 只有 2 天/5 笔订单或成本缺失 | 不给经营趋势/净利润“确定结论” |
| AI-02 | 模型生成不存在的营业额数字 | 证据引用校验失败，回退确定性摘要 |
| AI-03 | 上传商品备注恶意要求调用改价 API | AI 只读，所有可执行动作保持不可用 |
| JOB-01 | Worker 在支付权益提交后崩溃 | Outbox 恢复，最终只投递一次业务权益 |
| JOB-02 | 周报同一快照重复触发 | 同一报告实例、不会重复消耗额度/发送通知 |
| OPS-01 | 关停 AI 模型/导入 Worker/缓存服务 | POS 核心链路功能照常，后台任务可恢复 |

### 17.3 财务金样本建议

构造覆盖如下事件的同一门店连续 10 日样本：挂单、先下单后支付、混合支付、夜间跨日、赠送金、优惠券、菜品部分退款、跨日退款、外卖配送费、结账后调整、日结快照、重开日结、订单撤销、套餐父子明细及会员充值。金样本应产生精确的 `expected_<metric>.json`，**同时跑老 API、新 metrics API 与 Z 报表**，发现差异需人工定位而非直接改 SQL 抹平。

## 18. 迭代执行 WBS：可直接派发 AI 编程任务

### 18.1 必做准备（Gate 0，不可省略）

| Task ID | 依赖 | 后端/数据/前端工作 | 交付物 | 完成标准 |
|---|---|---|---|---|
| G0-01 | 无 | 获取代码仓库与生产/预发部署版本、JDK/Spring/MyBatis/ORM、CI/CD、实际 DB DDL | `PROJECT_BASELINE.md` | 记录 Git SHA/应用 build、MySQL 实际版本和关键框架 |
| G0-02 | G0-01 | 找齐所有 `db_migration_*.sql`、`t_access_policy/t_payment_ledger/t_daily_close_snapshot` 实际状态 | `SCHEMA_GAP_AUDIT.md` | 表存在/缺失/已迁移一一对应，不能以 SQL 快照猜测 |
| G0-03 | G0-01 | 生成 OpenAPI diff：元数据 1.2.272 vs 1.2.279 说明；比对线上路由实现 | `API_CONTRACT_GAP.md` | 能给出已实现/文档有但未实现/接口不一致三类 |
| G0-04 | G0-02 | 完成数据分布和跨店关系扫描、`NULL shop_id` 取证 | `TENANT_BACKFILL_AUDIT.md` | 每张高风险表可映射归属或进入隔离清单 |
| G0-05 | G0-03 | 保存 POS/Flutter/小程序/KDS 核心请求与响应的 golden 样本 | 契约回归测试 | 旧功能稳定可重复执行 |
| G0-06 | G0-02 | 统一营业日/营收/退款/套餐/会员充值口径 | `METRIC_CONTRACT_v1.md` | 产品、财务、后端共同签字，无指标冲突 |

### 18.2 V1.0 商业化底座（Gate 1）

| Task ID | 依赖 | 具体实施 | 后端接口/迁移 | 验收 |
|---|---|---|---|---|
| T1-01 | Gate 0 | 建 `saas_tenant/store/member/member_store`，旧店映射 | `Vxxx__saas_tenant_base.sql` | 不同 tenant 唯一归属，纯导入店可建立 |
| T1-02 | T1-01 | `TenantContextResolver`、平台 Owner 与 POS 账号桥接 | `/me/stores` 等 | 跨租户 IDOR 全绿 |
| T1-03 | T1-02 | 扫描 `t_dish/t_category/t_user` 等跨租户路径，安全开关和隔离 | 旧商品/会员路径适配 | 同名菜和同顾客不串店；未完成不得开放 POS 新租户 |
| T1-04 | T1-02 | `saas_plan_version/subscription`，功能权益、配额锁行 | `/plans`,`/entitlements` | 免费 POS 不依赖会员服务，收费查询服务端防绕过 |
| T1-05 | T1-04 | 平台账单/支付流水/回调验签/查单补偿 | `/billing/*` | 重复回调仅开通一次 |
| T1-06 | T1-05 | 过期降级、报表缓存失效、站内到期消息 | 定时任务 + outbox | 过期不影响任何合法收银操作 |
| T1-07 | T1-02 | 今日工作台免费接口/旧 dashboard 兼容 | `/dashboard/business-day` | 与同营业日原始收银对账一致 |
| T1-08 | T1-04 | 商家注册、店铺绑定、套餐与账单页、最小 UI 原型 | Web/Flutter 调整 | 真实支付可完成“购买→开通→查账→降级”闭环 |
| T1-09 | 全 T1 | 生产灰度、监控与 POS 断路器 | 灰度配置 | 老店关键操作零回归阻断 |

**V1.0 验收门槛：** 如果“所有 POS 租户隔离”未完成，可以先仅开放“现有内部 POS + 外部纯导入账号的租户底座”；不能以上线时间为由，把未隔离的商品/顾客/支付写路径交给陌生外部商家使用。

### 18.3 V1.1 数据增值与导入（Gate 2）

| Task ID | 依赖 | 具体实施 | 交付物 | 验收 |
|---|---|---|---|---|
| T2-01 | T1-02 + G0-06 | 内部订单/退款/支付/KDS 的规范投影适配器 | Canonical DTO/Adapter + tests | 老店金样本逐笔核对 |
| T2-02 | T2-01 | 指标字典、营业日计算、快照、数据质量 | Metric Engine v1 | 跟踪 sourceFingerprint 与 metricVersion |
| T2-03 | T1-04 | 专业版经营趋势/商品销售/条件性成本分析 | `/analytics/*` | 免费与收费权限分离，成本不足不报“净利润” |
| T2-04 | T1-02 | 对象存储 upload session、XLSX/CSV 异步解析 | `/imports` | 20MB/5万行容量验证、恶意文件隔离 |
| T2-05 | T2-04 + T2-02 | 映射 UI、预览、跨来源去重、冲突人工确认 | Mapping/Preview/Commit | 重传不重复统计，撤销可追溯 |
| T2-06 | T2-02 | POS 与第三方来源的汇总对账与质量看板 | Data Source Health | 两数据源同口径指标可解释 |
| T2-07 | 全 T2 | 不同外部厂商报表样本试点 | 数据模板包 | 至少两种真实报表格式成功导入 |

### 18.4 V1.2 AI 经营参谋（Gate 3）

| Task ID | 依赖 | 具体实施 | 交付物 | 验收 |
|---|---|---|---|---|
| T3-01 | Gate 2 | 4 类规则检测、门槛和证据快照 | Rule Engine | 无数据不输出异常结论 |
| T3-02 | T3-01 | 模型适配、脱敏、白名单工具、JSON Schema 验证 | AI Report Service | 全部数字可引用合法 metricId |
| T3-03 | T3-02 + T1-04 | 额度/成本预算/缓存/失败退额 | Usage Service | 并发与重试计费正确 |
| T3-04 | T3-02 | 日报周报/延迟任务/通知 | Scheduler + inbox | 同营业日幂等、数据过期提示 |
| T3-05 | T3-02 | 诊断卡、反馈与执行追踪 | AI 页面原型、API | 结论/假设/动作/复盘清晰区分 |
| T3-06 | 全 T3 | AI 幻觉/注入/超时/批量负载测试 | 质量报告 | 失败可回退指标摘要且 POS 无损 |

### 18.5 V1.3 候选（需要单独立项）

- 官方第三方 API 同步（按厂商协议和授权逐个验收），不进行私有接口抓取绕过。
- 自然语言问数（只读/预定义指标工具/证据校验/配额）。
- 使用现有备货预测 API 复用并验证模型准确率，补库存消耗与损耗数据。
- 跨门店对比、租户总部套餐计费与总店工作台。
- 合规自动续费（取得支付渠道授权且产品完成取消/提醒/续期争议设计）。

### 18.6 角色工时与关键依赖（粗粒度规划）

建议以 **1 名 Java 后端主程 + 1 名前端/Flutter 开发 + 兼职测试/运维/产品** 为最小团队，根据既有代码质量和历史迁移数量调整。Gate 0 和租户隔离可能比 AI 开发本身更耗时；任何工期都是估算，不能根据单份 SQL/YAML 给出真实完成日。每个任务满足“数据迁移 + 后端接口 + 前端联动 + 文档更新 + 自动测试 + 监控/回滚”六件套才算 Done。

## 19. CI/CD、变更控制与回滚预案

### 19.1 每个功能的标准交付包

- `docs/FEATURE_<id>_PRD_DIFF.md`：PRD 映射与功能开关。
- `docs/FEATURE_<id>_TECH.md`：领域模型、表/API、时序和风险。
- `migrations/Vxxx__*.sql`：新增迁移 + 干跑结果 + 回滚计划（正式 migration 往往只前进，回退靠兼容恢复）。
- `openapi.yaml`：同步请求/响应/鉴权/错误码/变更版本。
- `frontend-contract.md`：字段、空态、权限变化、Flutter/小程序联动改造清单。
- `tests/*`：单测、集成、契约、恶意输入、隔离与并发测试。
- `release-notes.md`：灰度开关、监控、数据修复和回退步骤。

### 19.2 风险变更发布门禁

1. 先预发部署、备份验证、迁移 dry-run、并发压测和收银回归。
2. 对 1 家自营门店启用指标影子计算、权限 shadow；连续至少 7 个经营日观测对账差异。
3. 开启受控内部订阅支付沙箱；真实支付回调演练与账单核对成功后才放行收费。
4. 灰度 2 家新 POS 商户与 2 家纯导入商户；如尚未完成全局菜品/顾客隔离，则新 POS 商户阶段**必须推迟**，仅试运行纯导入模式。
5. 每个灰度阶段评估失败率、客户支持量、成本和续费价值；通过后逐步扩大范围。
6. 任何付款/订单结账错误率上升触发**独立开关关闭 SaaS 分析/权限 shadow 功能**，不回滚已经成功收款的业务账务数据。

### 19.3 回滚与事故处理原则

**代码回滚可逆，事实账务不可随意反向删除。** DDL 使用 Expand/Contract 使旧版本仍能识别核心业务表；若订阅模块故障，禁止强制清空账单恢复，而应锁定受影响订单并通过查单/幂等补偿。若数据导入后发现重复，则以来源批次 `REVERSED` 标识 + 重建快照处理。若发现跨租户读权限泄漏，立即关闭对应高级 API、废止可疑下载令牌、记录受影响范围和安全事件审计。

## 20. 首批试点、业务验收与阶段结果

| 阶段 | 试点主体 | 必须产出的可量化证据 | Go/No-Go |
|---|---|---|---|
| 内测 | 自营门店 | 一周旧收银/新指标/Z 报表差额明细 | 无未解释的营收差异，POS 稳定 |
| 纯导入试点 | 2 家异构第三方 POS 商户 | 文件映射成功率、冲突率、第一份分析耗时 | 商户看得懂数据质量/问题 |
| SaaS POS 试点 | 2 家经过租户隔离验收的新 POS 商户 | 查单/收银/KDS/支付/权限/顾客余额隔离 | 所有跨租户测试通过 |
| 小规模收费 | 首批真实付款商户 | 支付→生效、续费意愿、每店毛利、客服负担 | 订单无丢失、多扣，成本合理 |
| AI 试点 | 有 ≥7 天、≥30 笔有效订单商户 | 证据完整率、人工采纳率、无证据拦截数 | 不制造虚假财务结论 |

**产品级首阶段目标**沿用 PRD：访谈不少于 10 位非关联餐饮老板、试点至少 5 家、争取至少 3 家真实付费并跟踪 2 个续费周期。上述数字用于验证假设，不代表收入保证。

## 21. 研发负责人需要补齐的真实环境信息（阻断清单）

以下并非要求商家重新描述需求，而是**工程进入生产实施前必须从仓库或环境直接核验的证据**；缺少时只能设计，不允许执行生产变更。

| 类别 | 待取得的证据 | 缺失影响 |
|---|---|---|
| 后端 | Git 仓库、编译配置、JDK 与 Spring Boot 版本、MyBatis/JPA 映射、实际 Controller | 无法确定精确改哪个类、SQL Mapper 或鉴权中间件 |
| 数据 | 真实生产 DDL、全套 migration、行数、索引、数据量、主从与备份 | 无法给出安全可直接执行的迁移脚本 |
| 时间与财务 | 典型旧订单/退款/混合支付/Z 报表实际数据脱敏样本 | 无法验证精准财务口径、订单关联/充值处理 |
| 账号/设备 | JWT claims、员工角色赋权路径、C 端 Token、KDS 设备认证代码 | 无法保证租户隔离和兼容性 |
| 支付 | SaaS 运营主体收款资质、正式可用商户号、回调沙箱环境 | 不能正式上线收费或声称自动续费 |
| 客户端 | Flutter/小程序/Web 的实际源码与发布渠道 | 无法列出每个界面的精确 Diff 与升级顺序 |
| 数据导入 | 至少两种外部 POS 导出样本、字段解释及合法数据授权 | 只能提供通用导入框架，不能保证无误识别 |
| 运维 | 腾讯云架构/域名、HTTPS、日志、告警、对象存储与备份 | 无法证明隔离/可用性/灾备目标达标 |

## 22. AI 编程 Agent 的执行规范（可直接放入项目工作流）

> **执行原则：先理解，再改动；先规范，再编码；先兼容，再切换；先证据，再 AI。**

### 22.1 每个任务的固定过程

```text
/feature <任务ID>
1) 阅读 PROJECT_BASELINE.md、PRD、TECH Blueprint、最新 OpenAPI、DB migrations。
2) 从实际后端定位当前 Controller/Service/Mapper、DTO/数据库字段。
3) 先输出：现状实现证据 / 缺口 / 涉及路径 / 风险 / 迁移建议。
4) 涉及 UI：先做原型、状态流程与复用组件规格；禁止直接重构页面。
5) 涉及 API：先更新契约并枚举所有前端、KDS、WebMCP 调用方。
6) 实现最小可回滚增量，增加 flag；不得悄悄改变旧 POST/GET 语义。
7) 完成数据库 migration、Java 自动测试和前端联动修改建议。
8) 运行兼容/财务/多租户/支付/权限/失败恢复测试。
9) 输出 Diff、未解决事项、监控与回滚方案，更新 PROJECT_STATE。
```

### 22.2 强制关联前后端变更

| 变更类型 | AI 编程必须补充的输出 |
|---|---|
| Java 新增或修改 API 字段 | `openapi.yaml` Diff、SDK/TypeScript/Dart DTO、表单/列表/缓存/空态/鉴权逻辑改动点 |
| 前端增加高级分析页 | 后端对应统计接口、权限码、套餐权益、数据质量、服务端分页/导出能力 |
| 数据表增加字段 | Migration、Entity/Mapper、旧数据回填、字段默认值、接口契约和回归样本 |
| 页面大规模重构 | 先原型，再组件规范，再实现，最后截图回归；架构性变化更新设计系统基线 |
| 经营算法改口径 | 指标版本升级、历史报表兼容、重算范围、数据对账金样本及 UI 提示 |
| 权限变更 | 确认原 RBAC 与 SaaS entitlement 双层校验、审计及越权测试 |

### 22.3 每个版本的 Done 定义

- `OpenAPI` 与代码一致、关键 API 回归通过；
- 所有新增表和索引有迁移与回填证明；
- 旧 POS 基础路径不受影响；
- 权限和租户边界经自动测试验证；
- 指标可逐笔复核，AI 报告有完整证据；
- 错误处理、日志、告警、隐私脱敏、回滚/运维手册存在；
- 前端页面状态/原型、SDK 与接口字段同步完成；
- 所有尚未完成的功能在 PRD/技术方案中标记“规划中”，不得伪装已上线。

## 23. 推荐首个实施迭代（直接进入代码前的最小执行包）

**第一个迭代只做 Gate 0 + T1-01/T1-02 的安全骨架**，暂时**不碰收银结账和 KDS 运行核心**。

1. 基于线上真实库做 Schema Gap Audit（特别是 API 文档引用而快照没有的权限、账本和日结表）。
2. 增加 `saas_tenant`,`saas_store`,`saas_member`，将自营门店作为第一个 tenant 绑定映射。
3. 实现 `TenantContextResolver` 与 `/api/saas/v1/me/stores`；用户和店铺作用域全部由服务端得出。
4. 为旧 `t_order`、`t_dish`、`t_category`、`t_user` 设计跨租户隔离集成测试，先发现问题，不立即全量改表。
5. 建立功能开关和免费核心 POS 回归用例，记录当前订单/KDS/支付链路基线。
6. 输出 `SCHEMA_GAP_AUDIT.md`,`API_CONTRACT_GAP.md`,`TENANT_BACKFILL_AUDIT.md`,`PROJECT_BASELINE.md`，评审后再进入付费底座。

**此阶段的唯一商业目标是证明“能安全服务第二个商户”，而不是抢先开发一个 AI 聊天框。**

---

## 附录 A. 文件可追溯索引

| 本方案事实 | 源文件定位 |
|---|---|
| 107 张表、MySQL 5.7、订单/商品/用户/权限/店铺 | `db_diancan.sql`：`CREATE TABLE t_order/t_order_detail/t_dish/t_category/t_user/t_shop/t_admin...`、各 `ALTER TABLE` 索引段 |
| 已有结账/退单/KDS/日结/报表/员工权限 | `openapi(1).yaml`：`/cashier/order/*`、`/kds/v2/*`、`/admin/daily/*`、`/admin/analytics/*`、`/admin/access/*` |
| KDS Cloud-first、权限 v2、营业日近期语义 | `openapi(1).yaml`：`info.description` 变更条目 `v1.2.259`、`v1.2.278`、`v1.2.258` |
| 独立第三方经营报表导入与旧渠道对账不同 | `/admin/reconciliation/import` 的既有定义，以及 PRD 第 10 节 |
| 核心功能免费、历史明细免费、高级分析付费 | PRD 第 3、7、8 节 |
| AI 证据链、至少 7 个可比营业日与 30 笔订单 | PRD 第 12 节 |
| V1.0→V1.3 分阶段、UAT 和发布门禁 | PRD 第 5、18、20 节 |

## 附录 B. 术语表

| 术语 | 定义 |
|---|---|
| Tenant / 租户 | SaaS 的商家组织数据及付费所有权主体，独立于微信/支付宝收单商户号 |
| Store / 门店 | 租户下的经营分析授权单位，可是 POS 门店或纯导入门店 |
| Legacy Shop | 原 `t_shop.id`，给现有 POS/KDS 代码使用 |
| RBAC | 岗位和用户是否有资格访问某功能/数据的权限 |
| Entitlement | 某门店当前付费/免费计划包含哪些产品能力与额度 |
| Canonical Fact | 把不同来源转换后的统一不可变/可版本化业务事实 |
| Business Day | 用门店时区和 `settle_time` 计算的经营结算日，而非自然日 |
| Source Fingerprint | 指标生成时原始来源、版本和过滤条件的可追溯指纹 |
| Outbox | 业务事务写入可恢复事件表，保证异步消费者最终收到并幂等处理 |
| Feature Flag | 允许按环境、门店、租户灰度开启或关闭新功能的发布开关 |
| Golden Sample | 已手工/财务对账确认的标准样例数据及预期输出 |

## 附录 C. 本方案中的“事实 / 设计建议 / 待验证”声明

- **已确认的文档事实：** SQL 文本中出现的表、列、索引；OpenAPI 文本中定义的路径/权限/历史描述；PRD 规定的产品原则。
- **实施设计建议：** 本文新建 `saas_*` 表、`/api/saas/v1` API、Java 模块边界、默认额度/告警、迁移阶段、示例 JSON 和样例 DDL，均**尚未执行**。
- **必须到仓库/线上核验：** 真实生产表是否已有增量迁移、实际支付台账实现、API 是否与代码一致、用户资产隔离、当前服务器部署与自动化测试。无法据此文档证明平台已经可安全对外商业化。

> **最终结论：** 先做真实 Schema/API/代码三方核验，并通过多租户隔离 + 免费核心 POS 回归；之后按“计费权益 → 指标规范层 → 文件导入 → 规则诊断 → AI 报告”迭代。任何阶段都不允许以收费或 AI 功能影响现有门店正常营业。
