# Execution Cursor

Last Updated: 2026-10-04
Status: COMPLETE

## Active Work

Work Type: CHANGE / FINANCIAL API SAFETY / CONTRACT
Workstream: shared dirty root (pre-existing overlapping UI013 implementation)
Active Diff: `docs/UI013_BACKEND_EXECUTION_PLAN.md`
Active Task: UI013 follow-up — 收入渠道拆分微信/支付宝收款码

## Cursor

Current Step: 收款码渠道契约测试、实现与验证
Step Status: COMPLETE
Preserved UI013 Baseline:

- 已读取 UI013 后端协调文档与仓库规则；
- 已确认现有未提交商用钱箱/日结实现为可继续的部分成果；
- 已复现 `current?previewExpected=true` 的盲盘泄漏面，并确认 precheck token 未被 settle 验证；
- 已执行 CashierShiftControllerTest、DrawerSessionServiceTest、DailyCloseServiceTest：22 PASS。
- 已完成预检 token/操作人/门店/营业日/水位线复验，阻断时不签发 token；
- 已完成盲盘隔离、稳定 409 错误码、写接口幂等与财务追踪元数据；
- 已完成工作台、班次报告/现金流水历史、Z 报表历史与结构化渠道/水位字段；
- 已同步 `docs/openapi.yaml`、`docs/API.md`、`docs/DATABASE.md` 与 V019 迁移；
- 定向回归 30 PASS；全量测试 1090 项、0 失败、5 跳过；
- `clean package -DskipTests` 通过，JAR SHA-256 `8C8483FCD39BD6FCC3269101260A44E5E9FD82D5465A27E689B2E4F09205A692`；
- release policy check：0 errors、2 warnings（工作区原有未提交改动与 PROJECT_STATE 元数据）。

Last Completed Step:

- 新增 `wechat_qr` / `alipay_qr` 报表渠道与 `WECHAT_QR` / `ALIPAY_QR` 账本渠道；
- 新结账与历史回填按 `payment_method` 写入独立收款码渠道；
- 交班、日结、Z 报表和 `/admin/daily/income|byChannel` 优先按关联订单收款方式拆分历史通用账本；
- 影子核验按微信/支付宝渠道族汇总，避免拆分产生虚假差异；
- 已同步 `docs/openapi.yaml`、`docs/API.md` 及数据库建表注释；OpenAPI YAML 解析通过；
- 收款码相关定向回归通过；排除工作区外部未跟踪且自身失败的 `OrderControllerTableInfoTest` 后，其余完整测试集通过；
- `clean package -DskipTests` 通过，JAR SHA-256 `71389364266F70DCA4474C3617FC06A89089F28DF4ABA1658B9470E81F34DC90`；
- release policy check：0 errors、2 warnings（工作区原有未提交改动与 PROJECT_STATE 元数据）。

Next Step: 部署后抽取同一营业日的普通微信/支付宝与手动/自动收款码订单，核对交班、日结和收入渠道金额。

## Preserved Previous Completion Evidence

- C012 跨天营业日报已完成；其历史验证记录保留在 Git 历史与原文档中。

<!-- Previous detailed C012 evidence retained below for audit continuity. -->
- 已确认显式日期实际窗口为 `[D settle_time,D+1 settle_time)`；
- 已确认注释/OpenAPI、在线报表/导出和结束边界存在冲突；
- 已保存 `docs/CROSS_DAY_BUSINESS_REPORT_EXECUTION_PLAN.md`；
- 已创建隔离工作流 WS004；
- 已用 UTC 默认时区复现窗口偏移 8 小时；
- 已将营业窗口固定为 `Asia/Shanghai` 并修正显式营业日注释；
- `ShopBusinessWindowResolverTest` 7 项通过；
- 已用聚合测试复现结束边界重复、错误使用 `order_time` 和门店/商户过滤缺口；
- `ReportOrderAggregate` 已统一财务时间、右开边界、历史空支付时间回退和门店隔离；
- `ReportOrderAggregateTest` 3 项通过；
- 日报、周报、月报已保留原 endpoint 并改为数据库聚合；
- HQ 无单店上下文时按每店各自 `settle_time` 聚合后求和；
- `AdminReportControllerBusinessReportTest` 4 项通过；
- 日报逐日导出与周/月区间导出均使用门店营业窗口；
- 原日结窗口测试保持通过；
- `ReportLogServiceTest` 全类通过。

Next Step: 执行 `docs/db_migration_order_business_report_indexes.sql`，再按同营业日对账日报、导出与日结；生产 MySQL 执行 `EXPLAIN`。

## Verification

- `ShopBusinessWindowResolverTest`：7 PASS。
- S1 RED：默认时区 UTC 时原实现 5 项失败，其中目标断言确认偏移 8 小时。
- `ReportOrderAggregateTest`：3 PASS。
- S2 RED：原实现返回 4 单/2784.00，期望为 2 单/95.00，证明财务时间和结束边界不正确。
- `AdminReportControllerBusinessReportTest`：4 PASS。
- S3 RED：原控制器不存在聚合依赖且会加载完整订单列表；改造后定向测试通过。
- `ReportLogServiceTest`：PASS；周/月导出 RED 证明原实现仍使用自然日窗口。
- `AdminDailyControllerSettlementWindowTest`：PASS。
- 收银端营业日报请求参数测试：3 PASS；定向 `flutter analyze`：PASS。
- 已同步 `docs/openapi.yaml`、`docs/API.md`、`docs/DATABASE.md`，并增加幂等复合索引迁移。
- 后端联合定向回归：39 PASS。
- 后端全量测试：1027 项，0 失败，5 跳过；首次高负载运行的连接池 92ms 时序测试失败，单测隔离通过，串行全量重跑通过。
- 合并后 `mvnw clean package -DskipTests`：PASS；JAR SHA-256 `BDD0E257B7BC3CE06AC3C3019E9E81B048CCE49B894B72CF8D19E05FA2B70A27`。
- 收银端 Windows Release：PASS；EXE SHA-256 `C0B893A4122710EF176D57622C89F9FCAA84907E957090732CC021D97655380F`。
- 全量 Flutter analyze 仍有仓库既有 101 条 warning/info；本次 3 个变更文件定向 analyze 为 0。
- 生产 MySQL `EXPLAIN` 未执行：本地无受控生产数据连接，上线前保留为操作门槛。

## Relevant Files

- `docs/CROSS_DAY_BUSINESS_REPORT_EXECUTION_PLAN.md`
- `src/main/java/com/lanf/util/ShopBusinessWindowResolver.java`
- `src/main/java/com/lanf/controller/admin/AdminReportController.java`
- `src/main/java/com/lanf/controller/admin/AdminDailyController.java`
- `src/main/java/com/lanf/report/service/ReportOrderAggregate.java`
- `src/main/java/com/lanf/report/service/ReportExportService.java`
- `src/test/java/com/lanf/util/ShopBusinessWindowResolverTest.java`
- `src/test/java/com/lanf/report/ReportOrderAggregateTest.java`

## Invariants

- 不新增 HTTP endpoint。
- 前端只传营业日，不计算时间窗口。
- 营业日 D 固定为 `[D settle_time,D+1 settle_time)`。
- 单店查询必须由鉴权门店上下文隔离。
- 结束边界必须为右开区间。
- API 语义变化必须同步 OpenAPI/API.md，并构建完整 JAR。
