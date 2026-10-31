# C009 性能与稳定性修复进度表

用户授权：2026-09-07，先拆分任务，逐一修复并验收。范围：server 与 admin_panel_flutter 两仓库的专项审计项。

## 执行约定

- 每项依次经过：TODO → IN_PROGRESS → VERIFIED_LOCAL → COMMITTED；生产验证另列，未执行不得记 PASS。
- 每项独立提交，保留测试/命令/结果和提交号；无推送、无生产数据库变更、无生产压测。
- 修复前核实审计推断。参数为可配置初始预算，不能用限额删除未同步订单、财务事件或幂等证据。
- 本地验收不等于 72 小时持续运行、生产 MySQL 锁/容量/恢复验收。
- 当前后端基线 43b9217；工作区起始干净。旧 D008 cursor 为历史待验收记录，本次不重做其业务变更。

## 顺序、依赖及验收标准

| ID | 优先级/来源 | 修复任务 | 依赖 | 本地验收标准 | 状态 |
|---|---|---|---|---|---|
| T00 | P0 验证前置 | 修复测试参数签名漂移，恢复可执行基线 | 无 | testCompile 成功；相关测试执行；记录剩余基线失败，不跳过安全断言 | COMMITTED 5aa9d3a |
| T01a | P0 B1 缓解 | 提交回调只投递到有界工作线程，解除同步嵌套取连接 | T00 | 两连接满池回调均返回且最终投影成功；回滚不触发；队列满立即拒绝；不在调用线程执行 | COMMITTED 4757330 |
| T01b | P0 B1 根治 | 持久化投影意图、重启恢复与原子确认 | T01a | 原事务记录意图；所有提交后入口改造；回滚无任务；重启恢复；投影失败可重试；成功后原子确认 | COMMITTED be74584 |
| T02 | P0 B1 | 显式绑定数据库池预算与有限等待 | T01a | 实际 bean 的 maxWait 有限且配置生效；饱和可超时退出；不降低事务完整性 | COMMITTED fefa4f0 |
| T03 | P1 B2 | 报表/归档有界执行及重启恢复 | T00 | 满队列拒绝且状态一致；按门店配额；重启可恢复 PENDING/过期 RUNNING；停机无新任务 | COMMITTED fcc0c75 |
| T04 | P1 B2 | 汇总报表 SQL 聚合、范围上限 | T03 | 旧新财务结果一致；不加载全量 Order；所有类型入队前校验范围；导出流式读取 | COMMITTED 5e0c6d5 |
| T05 | P1 B3 | Bootstrap 补投影移出长锁事务 | T01a | 请求不逐单补齐；保留 epoch fencing；不完整快照不伪报完整；大恢复可续租 | COMMITTED 755e39e |
| T06 | P1 B4 | 隔离配送/关键补偿调度，分批与时间预算 | T01a | 阻塞配送不影响补偿；并发、队列有界；游标续跑无遗漏 | COMMITTED 79e1bee |
| T07 | P1 B5 | WebSocket 有界异步广播及慢消费者退出 | T01a | 事务回调不发送网络数据；同会话串行；发送超时/超限关闭；游标可补拉 | COMMITTED cd35932 |
| T08 | P1 B6 | HTTP 短超时、并发预算、token 合并刷新 | T00 | 慢下游在期限内失败；连接可关闭；重复获取合并；不泄露凭据 | COMMITTED f8fffce |
| T09 | P2 后端线程 | 去除每单 new Thread 清理 | T00 | 清理线程数恒定；防重窗口/独立订单行为回归通过 | COMMITTED a1654e7 |
| T10 | P2 N+1 | 营业日订单批量查明细/状态 | T05 | 多订单明细查询次数有界；返回兼容、门店隔离不变 | COMMITTED 397ba29 |
| T11 | P2 保留 | 事件清理吞吐与导出文件保留 | T03 | 分批+时间预算；不删除未 ACK/未过期事件或下载中文件；历史可推进 | COMMITTED f1373fd |
| T12 | P1 日志安全 | 移除凭据日志，结构化限长 | T00 | token/secret 不进入日志；错误仍可定位，日志输入大小有界 | COMMITTED f41eb54 |
| T13 | P1 前端 H1 | 原生/Web HTTP 真取消和请求/正文预算 | T00 | 超时释放本地请求；队列满快速拒绝；大响应限额；迟到连接取消；上传兼容 | COMMITTED admin_panel_flutter:cbd31c7 |
| T14 | P1 前端 H2 | LAN WS 单设备连接与发送预算 | T13 | 重连替换、连接有界、慢消费者退出、正常补拉恢复 | COMMITTED admin_panel_flutter:3b2619f |
| T15 | P1 前端 H3 | Outbox SQL 有界批次选择 | 无 | 每轮最多4聚合×50条；队头阻塞不跳过；10万积压内存不全量增长 | COMMITTED admin_panel_flutter:fed3c86 |
| T16 | P1 前端 H4 | 启动迁移版本化、保留与备份容量 | T15 | 重启不重排历史；未 ACK 不删除；序号/幂等保留；备份不足可诊断 | COMMITTED admin_panel_flutter:3f69ceb |
| T17 | P1 前端 H5/M2 | 快照预算、续租、营业窗口缓存 | T05 | 重复token/超限不提交部分快照；恢复可续租；有效缓存允许拉取继续 | COMMITTED admin_panel_flutter:22226e2 |
| T18 | P2 前端 M3/M4 | Worker 关闭/切店竞态及重试抖动 | T13,T17 | 关闭后不写库；旧店任务不污染新店；失败退避；租约不被普通退避阻塞 | COMMITTED admin_panel_flutter:3316a95,64c5082,49197de |
| T19 | P2 前端日志 | API日志字节预算、串行轮转、启动降级 | 无 | 大正文不全量脱敏；轮转关闭旧sink；磁盘错误不递归日志；DB失败仍停止收银 | COMMITTED admin_panel_flutter:56aecd9 |
| T20 | P2 可观测性 | 池/队列/同步/磁盘指标与告警说明 | T02,T06,T11,T18 | 指标不泄密；饱和/异常可观测；告警阈值有配置与采集说明 | COMMITTED admin_panel_flutter:8922122 |
| T21 | P1 综合验收 | 前后端回归及部署产物 | T01–T20 | 相关单测/集成通过；API变更同步openapi/API并打JAR；Flutter平台构建；差异复核 | VERIFIED_LOCAL 2026-09-09 |
| T22 | 外部验收 | 生产MySQL、容量/72小时/接管恢复 | T21 | 真机慢SQL/EXPLAIN、GC/RSS、1×/2×/3×峰值、72h无持续增长、RTO/RPO | EXTERNAL_PENDING |

### 审计报告一致性复核（2026-09-09）
- 对齐：H1（T13 真取消、请求/响应预算）、H2（T14 单设备连接、连接/发送上限）、H3（T15 SQL 先选聚合头后限量读取）。T14使用32帧/64KiB，比报告建议的100帧/1MiB更保守；恢复游标保留。
- 部分：M1仅把调试正文降至8KiB，仍会在截断前解析/格式化，且没有100条/4MiB总预算；T19仍需处理CrashLog轮转及启动降级。
- 重新打开：T16、T17、T18。详见当前审计源 `admin_panel_flutter/docs/admin_panel_chain_frontend_tasks.md`；不得把局部提交称为报告要求的完整修复。

## 验证账本

### T01 当前→目标与分步限制
- 存在 AFTER_COMMIT listener 及加菜的 runAfterCommit→KdsOrderHook 二次回调；直接把 publishAfterCommit 改为同线程插入持久化任务可能落在已提交事务内而丢写。
- T01a先消除同步连接相互等待；采用固定2工作线程、有界128队列，拒绝不CallerRuns；已有数据库源订单对账仍保留。
- T01a不是可靠任务根治：队列满/进程退出仍依赖已有两天/500单对账窗口，不能声称零任务丢失。T01b单独改造所有入口并引入事务内持久化意图与迁移；T01整体和生产发布门槛仍未完成。

### T00
- 审计已发现 processPayment 新增 merchantId、today 新增 businessDate 后测试仍按旧签名调用。
- 修复：补齐 merchantId/date；mock 对齐 checkoutKeepMerchantId；today注入shopService；H2营业日fixture补settle_time并使用显式INSERT列。
- 验证：`mvn -o -Dtest=PersonalPaymentWebhookServiceTest,PersonalAlipayWebhookControllerTest,CashierOrderControllerTest,CashierKdsDeliveryServiceTest,CashierKdsProjectionPublishRetryTest,ReportLogServiceTest,RequestBodyCacheFilterTest test -q`，61 tests，0 failures/errors（2026-09-07）。生产业务代码未变。完整回归留在T21，不能把这61项称全套通过。

## 提交记录

- 规划提交：dbf1e5f，docs(stability): define sequential remediation and acceptance gates。

## 生产验收材料

缺少生产有效配置、MySQL计划/慢日志、启动参数、容器资源与真实峰值，T22 不可凭本机结果置为完成。

### T01a 验收（2026-09-08）
- 固定2线程、128队列、130总在途（包含延迟重试）；提交回调不执行JDBC，饱和拒绝不CallerRuns。关闭后拒绝新任务。
- mvn -o -Dtest=CashierKdsProjectionPoolTest,CashierKdsProjectionPublishRetryTest,CashierKdsDeliveryServiceTest test -q：13 tests，0 failures/errors；日志 .local/c009-t01-resume.log。首次旧实现满池回归失败，修复后通过。
- T01b仍TODO，现有补偿窗口不能证明重启/拒绝后零丢失。下一项T02独立消除无限等待；不以此替代T01b。

### T02 验收（2026-09-08）
- 实际Druid bean显式绑定 max-active=8/max-wait=2000ms；非法预算启动失败；自定义数据源保持退让。配置见docs/C009-DATASOURCE-BUDGET.md。
- 配置+debug隔离+T01a回归18项通过（.local/c009-t02-green.log）；补充自定义bean验收后配置测试4项通过（.local/c009-t02-final.log）。去重共19项，0 failures/errors。只验证连接获取等待，未验证生产SQL/锁超时。

- 2026-09-08提交：4757330（T01a，有界异步投影）；fefa4f0（T02，有限连接等待）。累计3/24项本地提交完成；T01b及其他任务未完成。

### T01b 验收（2026-09-08）
- 持久化任务、原事务记录/回滚、磁盘H2重新打开恢复、并发消费与同单顺序、投影与任务确认原子性、有界扫描、接单门禁、意图异常不可吞掉均有回归；详见docs/C009-PROJECTION-INTENTS.md。
- 最终命令：mvn -o -Dtest=CashierKdsProjectionIntentTest,CashierKdsProjectionIntentReadinessTest,CashierKdsProjectionPoolTest,CashierKdsProjectionPublishRetryTest,CashierKdsDeliveryServiceTest,KdsEventListenerTest,OrderAutoAcceptPrintTest,KdsOrderHookAcceptanceGateTest,KdsOrderStatusAggregatorTest,KdsOrderStatusAggregatorQuantityTest,OrderDetailRefundServiceTest,DataSourceBudgetConfigurationTest,KdsReplicationContractTest test -q；72 tests，0 failures/errors。日志.local/c009-t01b-verified.log及.local/c009-t01b-test-summary.txt。
- mvn -o clean package -DskipTests -q成功；target/diancan-0.0.1-SNAPSHOT.jar已重建；日志.local/c009-t01b-package-final.log。
- API/DATABASE/openapi同步；顺带修复HEAD已有v1.2.221说明缺缩进导致的YAML解析失败，契约测试恢复通过。
- 尚未执行生产MySQL迁移/压测/故障切换；必须先执行docs/db_migration_kds_projection_intent.sql再部署。旧实例及升级前未知漏记不由新表自动补回，打印外部副作用不具备分布式原子性。T22仍未完成。

- T01b提交：be74584，fix(stability): persist KDS projection intents with atomic recovery。当前累计4/24项本地提交完成，下一项T03；生产验收仍待执行。

### T03 验收（2026-09-08）
- 报表/归档各1线程+16本地唤醒；持久化共128/门店4配额；满唤醒队列保留PENDING恢复；5秒扫描每类型32条；10分钟租约及令牌条件更新阻止旧执行者覆盖。停机中断保留RUNNING。详见docs/C009-REPORT-JOB-RECOVERY.md。
- mvn -o -Dtest=ReportJobCoordinatorTest,BoundedJobExecutorTest,ReportLogServiceTest,KdsReplicationContractTest test -q：41项，0 failures/errors；.local/c009-t03-release-tests.log及.local/c009-t03-test-summary.txt。mvn -o clean package -DskipTests -q成功；.local/c009-t03-package.log。
- API/DATABASE/openapi同步，修复已有v1.2.231/229缩进以通过契约解析。迁移脚本尚未在生产执行；停旧工作线程后先迁移再部署。实际进程崩溃/MySQL验收归T22；全量查询内存风险留T04，文件保留留T11。

- T03提交：fcc0c75，fix(stability): bound report jobs and recover interrupted executions。累计5/24项本地提交完成，下一项T04；T22生产验收待执行。

### T04 验收（2026-09-08）
- SQL聚合只返回一行，BigDecimal输出，日报逐日流写，删除旧Order全量加载与rows累计；三类导出入队及恢复校验含首尾92天。保持导出order_time闭区间、退款独立列及既有财务公式。详见docs/C009-REPORT-AGGREGATION.md。
- 先复现逆序/超限入队（.local/c009-t04-red.log）。最终mvn -o -Dtest=ReportLogServiceTest,ReportOrderAggregateTest,ReportJobCoordinatorTest,BoundedJobExecutorTest,KdsReplicationContractTest test -q：49项，0 failures/errors；.local/c009-t04-final-tests.log、.local/c009-t04-test-summary.txt。包括10000笔金额对照、NULL/边界/门店、92天、失败文件关闭、statement30秒预算及资源关闭。
- mvn -o clean package -DskipTests -q成功（.local/c009-t04-package.log），API/DATABASE/openapi同步。只读独立复核无阻断项。无生产DDL/部署；同步报表及LOG_EXPORT全量查询仍属未治理范围，单条SQL30秒不等于整个任务期限，T22待MySQL/压测验收。

- T04提交：5e0c6d5，fix(stability): aggregate report SQL and stream bounded exports。累计6/24项本地提交完成；下一项T05，T22生产验收待执行。

### T05 验收（2026-09-09）
- Bootstrap补投影移至后台1线程/16排队门店/每批32单；请求缺口返回503/5030，门禁不放行。分页读取无租约事务，起止短事务校验epoch/token；部分页ACK不可解除门禁；并发RENEW可进行。详见docs/C009-BOOTSTRAP-REPAIR.md。
- 定向命令mvn -o -Dtest=CashierKdsDeliveryServiceTest,CashierKdsLeaseServiceTest,CashierKdsProjectionIntentTest,CashierKdsProjectionIntentReadinessTest,CashierKdsProjectionPoolTest,CashierKdsProjectionPublishRetryTest,KdsReplicationContractTest test -q：46项，0 failures/errors；日志.local/c009-t05-final-tests.log和.local/c009-t05-test-summary.txt。
- 生产MySQL/故障恢复/客户端持续续租联调待T17/T22；无新增DDL或部署，仍保留原近2天源订单补偿窗口，不宣称全历史零遗漏。
- T05 JAR：mvn -o clean package -DskipTests -q成功，.local/c009-t05-package.log；API/DATABASE/openapi同步，独立复核发现项已修复并测试。

- T05提交：755e39e，fix(stability): move bootstrap repair outside lease transactions。累计7/24项本地提交完成，下一项T06；生产验收待T22。

### T06 验收（2026-09-09）
- 配送与KDS投影补偿拆为独立单线程fixed-delay调度；配送20条/20秒、KDS32单/10秒，按ID游标续跑，尾页后回绕。预算到达不重置未完成游标；配送阻塞不占用补偿线程。详见docs/C009-SCHEDULING-ISOLATION.md。
- `mvn -o -Dtest=TakeoutZsqSyncSchedulerTest,CashierKdsProjectionReconcilerTest,WechatRefundQuerySchedulerTest,CashierKdsDeliveryServiceTest,CashierKdsProjectionIntentTest,CashierKdsProjectionPoolTest test -q`：31项，0 failures/errors；.local/c009-t06-final-tests.log。先发现H2无法执行补偿SQL的DATE_SUB，改为绑定两天前参数后真实游标回归通过。
- `mvn -o clean package -DskipTests -q`成功（.local/c009-t06-package.log）。未改外部API/DDL；远端HTTP硬超时留T08，MySQL扫描和隔离压测留T22。

- T06提交：79e1bee，fix(stability): isolate delivery and projection compensation schedules。累计8/24项本地提交完成，下一项T07；生产验收待T22。

- T07：KDS、菜单和收银唤醒的同步逐连接发送改为统一有界异步出站调度；每会话FIFO、32帧/64KiB，4个写线程/256待调度会话，5秒写超时或超限关闭。现有REST cursor/菜单重拉保留为恢复源。`mvn -o -Dtest=WebSocketOutboundDispatcherTest,CashierWakeRecoveryTest,KdsEventListenerTest,KdsPushPayloadBuilderTest test -q`：12项，0 failures/errors；`mvn -o clean package -DskipTests -q`成功。详见docs/C010-WEBSOCKET-OUTBOUND-BOUNDS.md。

- T07提交：cd35932，fix(stability): bound asynchronous websocket broadcasts。累计9/24项本地提交完成，下一项T08；真实慢网/峰值验证待T22。

- T08：ZSQ改为有界Apache连接池（4连接、1秒租赁、2秒连接、5秒读取），配置非法即启动失败；同一过期token并发调用只保留一次刷新，其余复用新token，保留原一次认证失败重试。`mvn -o -Dtest=ZsqAuthServiceTest,ZsqIntegrationConfigTest,ZsqRemoteClientOrderLogTest,TakeoutZsqSyncSchedulerTest,TakeoutZsqTrackingPersistenceTest,TakeoutZsqRedispatchReuseTest,TakeoutZsqCancellationFlowTest test -q`：18项，0 failures/errors；`mvn -o clean package -DskipTests -q`成功。详见docs/C011-ZSQ-HTTP-BOUNDS.md。

- T08提交：f8fffce，fix(stability): bound ZSQ HTTP and token refresh。累计10/24项本地提交完成，下一项T09；真实慢网、DNS/TLS和连接池耗尽验证待T22。

### T10 验收（2026-09-09）
- 营业日订单列表改为按页收集订单ID后一次查询明细与菜品状态并在内存分组，消除每订单的明细和进度查询；保留返回结构、门店条件与订单排序。
- `mvn -o '-Dtest=CashierKdsDeliveryServiceTest,CashierKdsProjectionIntentTest' test -q`：21项，0 failures/errors。未执行生产 `EXPLAIN` 或峰值页容量验证，留T22。
- T10提交：397ba29，fix(kds): batch business-day order reads。累计12/24项本地提交完成，下一项T11。

### T11 验收（2026-09-09）
- 已确认导出下载文件不存在定时删除路径；KDS已确认事件清理由单次无界删除改为每批最多200条、5秒时间预算，并只删除ACK游标之前且超过7天的事件。
- `mvn -o '-Dtest=CashierKdsProjectionReconcilerTest,CashierKdsDeliveryServiceTest' test -q`：相关回归通过，0 failures/errors。生产表扫描计划、历史积压推进速度待T22。
- T11提交：f1373fd，fix(stability): bound KDS event cleanup。累计13/24项本地提交完成，下一项T12。

### T12 验收（2026-09-09）
- 支付/退款回调、解密载荷、微信与AI错误响应、JWT解析异常不再写原文。`SafeLogValue` 仅输出总字符数、最多4096字符的摘要输入长度和SHA-256前16位；微信响应头只输出字段数。
- `mvn -o '-Dtest=SafeLogValueTest,WechatJsapiChannelTest,OrderRefundNotifyTest,PersonalPaymentWebhookServiceTest,SysInterceptorPermissionMappingSecurityTest,SysInterceptorKdsReplicationAuthTest' test -q`：28项，0 failures/errors；`.local/c013-t12-final-tests.log`。静态复核旧“完整报文”、原始响应头/正文、支付与退款解密原文路径均不存在。
- T12提交：f41eb54，fix(logging): redact payment and remote response bodies。累计14/24项本地提交完成，下一项T13；生产日志采样、外部日志平台脱敏和保留策略待T22。

### T13 验收（2026-09-09）
- Flutter IO `HttpClientRequest.abort` 与 Web `XMLHttpRequest.abort` 已绑定到客户端超时；默认全局8个在途、32个等待位、1秒排队预算，满队列即时拒绝。JSON请求上限1MiB、收款码multipart上限10MiB、响应上限2MiB；IO流式累计超限即中断，Web由progress字节数触发中断。
- `flutter test`：553项通过；核心超时、取消、队列满、请求/响应限额和小收款码上传均有回归。`flutter analyze`全仓68项既有warning/info；本任务核心文件+测试单独分析0 issue。日志`.local/c013-t13-flutter-test.log`、`.local/c013-t13-analyze.log`位于admin_panel_flutter。
- T13提交：admin_panel_flutter:cbd31c7，fix(http): bound client requests and cancel timeouts。累计15/24项本地提交完成，下一项T14；真实浏览器慢网、原生连接取消和生产响应体分布待T22。

### T14 验收（2026-09-09）
- LAN KDS WebSocket 以 `device_code` 保持单活跃连接：同设备重连时先以正常关闭替换旧连接。默认最多32个设备连接；连接满时以1008拒绝新设备，不挤掉既有终端。
- 每个设备发送通道最多32帧、64KiB待发数据、单帧写入5秒；任一预算耗尽或写入失败时以1008关闭慢消费者。KDS 客户端仍可通过既有 `/kds/v2/changes` 游标补拉恢复，广播不再成为内存堆积点。
- `flutter test test/cashier_kds_lan_server_test.dart`：19项通过；`flutter test test/cashier_kds_performance_test.dart`：2项通过，500活跃订单本机WS P95 7.135ms；相关 `flutter analyze` 0 issue。
- T14提交：admin_panel_flutter:3b2619f，fix(kds): bound LAN websocket sessions。累计16/24项本地提交完成，下一项T15；真机慢消费者、断网补拉和设备数量分布待T22。

### T15 验收（2026-09-09）
- Outbox 不再全量读取所有未完成事件到 Dart 分组；SQL 先选最多4个到期聚合头，再逐聚合最多读取50条连续事件。队头处于退避、认证暂停或死信时，后续事件保持阻塞，不会跳过。
- 增加未完成聚合序号索引，避免10万级积压下的全量对象增长。`flutter test test/cashier_cloud_outbox_worker_test.dart test/cashier_kds_local_database_test.dart test/cashier_kds_performance_test.dart`：40项通过；1万积压选择与命令基准通过；相关分析0 issue。
- T15提交：admin_panel_flutter:fed3c86，fix(outbox): bound due aggregate selection。累计17/24项本地提交完成，下一项T16；真实SQLite文件100万级积压和恢复吞吐待T22。

### T16 复核后验收
- `cloud_outbox_aggregate_sequence_migrated_v1` 把历史重排序限制为一次 `BEGIN IMMEDIATE` 迁移；失败回滚且不写迁移标记。后续启动不再改写既有序号。
- 新增聚合序列高水位表，清理已送达/已丢弃事件后仍不会复用序号。清理每次最多2000条，仅删除30天前的终态 outbox、入站去重和操作幂等记录；未送达/退避/死信事件不删除。
- 保留9463e09的原子备份与512MiB容量预算。`flutter test test/cashier_kds_local_database_test.dart test/cashier_kds_retention_test.dart`：25项通过；`flutter analyze` 定向0 issue。
- T16提交：admin_panel_flutter:3f69ceb，fix(kds): version outbox migration and retention。

### T17 复核后验收
- Bootstrap 维持100页/10000订单上限，并新增30秒总时限、20MiB投影字节上限和分页 token 去重；任何预算、快照 token 或完整性失败都在写 SQLite 前终止。
- 分页间若续租时间已到，先续租再继续读取，避免长快照在本地持有已过期租约。
- 营业窗口有效时最多60秒刷新一次；刷新失败时继续使用尚未过期的缓存，不因报表窗口接口暂时失败阻断订单拉取。
- `flutter test test/cashier_kds_delivery_worker_test.dart`：7项通过；`flutter analyze` 定向0 issue。T17提交：admin_panel_flutter:22226e2，fix(kds): bound bootstrap snapshots。

### T18 当前复核
- `3316a95` 将 delivery worker 的关闭改为可等待、幂等的 Future：关闭标记先阻止配置/唤醒/新同步，停止计时器与 wake，再等待在途轮次结束；runtime 在关闭 SQLite 前 await worker。generation 防止切店/关闭后的迟到结果写入。
- 入站失败使用带±20%确定性抖动的3/6/12/30秒退避，连续5次失败进入30秒探测窗；租约续期仍绕过普通退避。`64c5082` 为出站 outbox 的同样退避增加每事件抖动；既有401/403暂停与一分钟恢复探测保留。
- `flutter test test/cashier_cloud_outbox_worker_test.dart test/cashier_kds_delivery_worker_test.dart`：24项通过；`flutter analyze` 定向0 issue。HTTP领域异常尚未携带`Retry-After`，因此T18保持PARTIAL，不将该项误记为审计闭环。
- `49197de` 已将 HTTP `Retry-After`（1..900秒）从 IO/Web transport 经 `ApiException`、云发送失败对象传递给 outbox；临时失败优先采用服务端恢复时间，否则使用带抖动退避。API/云发送/outbox回归31项通过，定向分析0 issue；T18闭环。

### T19 验收
- 调试正文在 JSON 解码/格式化前截断，单条8KiB；环形内存日志限制100条和4MiB。
- CrashLog 使用串行写队列；1MiB阈值轮转时先flush/close旧sink、再改名重开，写入/轮转异常不递归触发全局日志。日志初始化失败降级，不影响KDS数据库启动的独立致命页。
- `flutter test test/api_debug_log_test.dart test/crash_log_test.dart`：5项通过；定向分析0 issue。T19提交：admin_panel_flutter:56aecd9。

### T21 本地综合验收
- 后端：`mvn -o -DskipTests package -q` 成功，JAR可生成；各任务已在其提交边界执行对应回归。未把历史定向测试误写为全量后端测试。
- Flutter：稳定性关键套件58项通过；Windows Release `build/windows/x64/runner/Release/laofei_cashier.exe` 与 Android Release `build/app/outputs/flutter-apk/app-release.apk` 均生成。
- `flutter analyze` 完成但报告81条既有warning/info，均不属于本专项提交；不作为本次修复通过证据。工作区存在大量无关用户改动，未暂存。
- T22仍必须在真实环境完成MySQL计划、慢网/真机、容量、72小时RSS/句柄、接管恢复验证；本地构建不替代生产验收。
