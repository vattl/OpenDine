# D009 稳定性治理 Structural Diff

Parent: tasks/active/C009-stability-remediation.md；CRITICAL；按任务逐步更新。

## Current → Target

提交回调同步REQUIRES_NEW、无界后台队列、客户端假超时和全量积压读取 → 请求及后台资源有界，持久化任务可靠恢复，有限等待，故障独立处理。

## 变更边界

| 范围 | 操作 | 验收 |
|---|---|---|
| 支付签名、身份认证、门店权限、营业日业务口径 | PRESERVE | 不能为修复性能弱化现有断言/契约 |
| 过时测试调用 | MODIFY T00 | 对齐新增参数并保留行为断言 |
| 投影触发与执行 | REPLACE T01 | 原事务记录可靠任务，提交回调只唤醒；禁止同步申请第二连接 |
| 持久化任务/查询索引 | ADD（如T01实证需要） | 增量DDL、启动只读校验、回滚保留未处理事实；不在线自动DDL |
| 执行器、Transport、清理和日志 | MODIFY 按C009 | 有界、可恢复、有测试证据 |

## 迁移与回滚

新增表/索引先应用并验证再切换应用；应用回滚不删除任务表。归档必须覆盖重放和幂等窗口，不直接删除未确认事实。每项独立commit；禁止用整体revert丢弃用户工作。

## 发布门槛

本地COMMITTED与生产验收分开。接口变化同步docs/openapi.yaml和docs/API.md，生成生产JAR；无生产材料不声称线上通过。

## T01a 已验证变化
MODIFY publishAfterCommit：固定工作线程执行，回调仅投递；有界队列和包括延迟重试的130在途预算。13项定向测试通过。T01b持久化任务尚未实现，REPLACE T01仍PARTIAL。

## T02 已验证变化
ADD DataSourceBudgetConfiguration：沿用spring.datasource连接配置，显式应用有限等待/容量预算；自定义数据源退让。配置与回归去重19项通过。没有生产变更。

## T01b 实施模型
ADD t_kds_projection_intent：自增主键任务、索引(next_attempt_ms,id)，源事务记录；事务失败自动回滚。消费事务锁任务、写投影/事件、删除任务一起提交，失败保留并退避。每次扫描32条，复用有界执行器；重复唤醒可幂等处理。加菜先记任务，未接单保留等待；完成事件记录移至BEFORE_COMMIT。源订单历史对账保留为升级前补偿，不能取代任务恢复。

T01b本地验证完成：72项定向测试与clean package通过；增量迁移/启动只读门禁/API及数据库文档齐备。生产T22仍待验证，详细边界见docs/C009-PROJECTION-INTENTS.md。

## T03 当前→目标
现有数据库任务+无界内存队列+无恢复执行者 → 有界单线程队列、事务化全局128/单门店4个未完成任务预算、10分钟执行租约与执行令牌、5秒扫描恢复PENDING/过期RUNNING，旧执行者不能覆盖新结果。日志同步导出不进入异步配额，T04单独治理查询体量。文件名加入执行令牌以避免旧执行者覆盖新文件。增量迁移，不清除已有任务。

- T03本地验收：41项定向测试通过，clean package -DskipTests成功；生产迁移/真实崩溃恢复未执行。具体预算、验收与剩余边界见docs/C009-REPORT-JOB-RECOVERY.md。

### T04 当前→目标（2026-09-08）
- REPLACE：ReportExportService全量Order加载/Java汇总→数据库COUNT/SUM仅返回聚合行；逐营业日查询后立即写CSV，不累计rows。保持导出原order_time闭区间、sett+service-discount及退款列，不借性能任务改变财务口径（同步报表controller现已采用不同pay_time口径，另行治理）。
- MODIFY：daily/weekly/monthly均入库前校验起止顺序及含首尾最多92日；恢复历史任务时再次校验；查询使用独立30秒statement预算。保留T03配额/令牌/门店隔离、CSV格式和token。
- 验收：先复现超范围入队；H2实际SQL核对NULL/门店/状态/时间边界及金额；CSV逐行资源关闭与异常路径；相关回归及JAR。生产EXPLAIN/真实JDBC超时留T22。

- T04验证：REPLACE/MODIFY本地PASS，旧导出List<Order>/buildDailyRows/buildSummaryRow路径不存在。49项定向回归通过，JAR打包成功；生产指标未验证。

### T05 当前→目标（2026-09-08）
- REPLACE：Bootstrap锁租约后逐单同步publish并吞异常→无外层事务的有界缺口检查与分页读取，后台1线程/16门店唤醒、每批32单、单单独立5秒事务；缺口返回503/5030，客户端续租并重试首屏。保留原近2天接单筛选。
- MOVE：租约FOR UPDATE与投递游标写入移到独立短事务，读页后重新校验epoch/token/有效期；部分页不允许ACK清除快照门禁。保持HMAC页token与基准cursor。
- 验收：复现缺口误报完整；32单批次、部分页ACK、续租、页读取无事务、读后epoch改变拒绝、既有投影/意图回归。无生产DDL。
- T05验证：46项定向回归通过、JAR打包成功；旧ensureActiveOrdersProjected已删除，bootstrap无外层事务。独立复核的503后ACK0门禁漏洞已修复。生产验证待T22。

### T06 当前→目标（2026-09-09）
- REPLACE：配送同步和KDS投影补偿共用默认`@Scheduled`线程、配送全量扫描、KDS每轮500单且无时间预算 → 两个独立固定单线程调度器，fixed-delay不重叠；配送20条/20秒、KDS32单/10秒，游标到尾页才回绕。
- MODIFY：配送按`t_takeout_delivery.id`键集扫描；KDS按`t_order.id`键集扫描。预算到期后不再取下一项，失败记录下次回绕重试；保留订单筛选、事件幂等和退款补偿行为。
- 验收：31项定向测试通过，JAR打包成功。旧KDS SQL在H2无法运行的DATE_SUB改为绑定两天前时间参数，语义不变。真实远端调用取消、MySQL计划/吞吐待T22。

### T07 当前→目标（2026-09-09）
- REPLACE：KDS、菜单、收银 wake hub 在事务 `afterCommit` 或业务调用线程逐连接同步 `sendMessage` → 统一的 `WebSocketOutboundDispatcher`。所有出站帧先进入每会话 FIFO，再由固定有界写线程发送。
- MODIFY：每会话限制 32 条/64 KiB 待发送帧；全局最多 4 个写线程和 256 个待调度会话。入队超限、调度器拒绝或 5 秒未完成的写关闭该会话，清空未发帧。处理器的 connected/pong 同样走该通道。
- PRESERVE：KDS 与收银的 REST cursor 补拉和菜单重拉仍为恢复事实来源；不新增 WebSocket API 或改变认证、分桶路由。
- 验收：同会话 FIFO、队列超限关闭、写超时关闭和收银 cursor 唤醒回归。网络栈在真实慢网下的取消效果、峰值写阻塞和容量参数留 T22。

### T08 当前→目标（2026-09-09）
- REPLACE：ZSQ `SimpleClientHttpRequestFactory` 的15秒连接/60秒读取、无池化容量 → Apache HTTP 连接池：全局/单路由4连接、1秒池租赁、2秒建连、5秒读取。非法预算启动失败。
- MODIFY：配置账号 token 同时过期时，每个调用者均使缓存失效并重新登录 → 比较失败 token 与当前缓存；只有仍为当前值的首个调用者刷新，其余复用已替换凭据。
- PRESERVE：ZSQ 业务接口、一次认证失败后重试一次的语义、配送状态补偿与 token 不写日志。未扩展自动重试，也未改通用微信、飞鹅或高德 HTTP 客户端。
- 验收：18项定向测试通过；真实DNS/TLS、连接池耗尽和峰值登录指标待T22。

### T09 当前→目标（2026-09-09）
- REPLACE：每个堂食下单请求创建一个 `Thread`，睡眠100ms后释放防重键 → 单守护工作线程、128个有界待清理任务。
- PRESERVE：同桌防重键仍在100ms后释放；执行器满时立即释放，避免因排队失败把桌台锁到Caffeine五分钟TTL；关闭时中断清理任务。
- 验收：订单相关30项回归通过，旧的每订单 `new Thread` 路径不存在。

### T10 当前→目标（2026-09-09）
- REPLACE：营业日订单页按订单逐条读取明细和状态 → 收集当前页订单ID后各执行一次IN查询，并按订单/明细ID分组回填。
- PRESERVE：门店过滤、订单排序、输出JSON结构及无明细订单的行为。
- 验收：相关KDS服务和投影意图测试21项通过；生产执行计划、IN列表最大页容量留T22。

### T11 当前→目标（2026-09-09）
- REPLACE：KDS已确认事件单次无界清理 → 仅清理ACK游标前且超过7天的数据，每批最多200条、单次调度最多5秒。
- PRESERVE：未ACK或未到期事件不删除；导出下载文件未发现定时删除路径，故不引入未经证实的保留清理逻辑。
- 验收：reconciler与delivery相关测试通过；生产历史积压和索引扫描待T22。

### T12 当前→目标（2026-09-09）
- REPLACE：支付/退款回调、解密明文、微信及AI远端错误响应、JWT异常详情原样写日志 → 统一记录状态、业务关联字段和 `SafeLogValue` 摘要；响应头只记录数量。
- ADD：`SafeLogValue` 最多处理4096字符，输出字符数、摘要输入长度和SHA-256前16位，不包含原文。
- PRESERVE：错误响应的业务分支和返回给调用方的既有兼容行为；日志仍可按请求/订单及摘要关联。
- 验收：28项定向回归通过，静态检索不再命中旧完整报文、原始响应头/正文或解密原文日志。生产日志平台及历史保留验证待T22。

### T13 当前→目标（2026-09-09）
- REPLACE：`Future.timeout`只放弃调用方等待、IO socket和Web XHR继续执行，且请求/响应没有统一预算 → 取消令牌绑定 `HttpClientRequest.abort`/`XMLHttpRequest.abort`；超时立即中断实际传输。
- ADD：跨`AdminApiClient.copyWith`共享的8在途/32排队/1秒排队预算；JSON 1MiB、multipart 10MiB、响应2MiB上限。IO按流累计并在超限时中断；Web在progress报告超限时中断。
- PRESERVE：既有`HttpTransport`测试替身兼容，业务API、认证和收款码小文件上传契约不变。
- 验收：admin_panel_flutter 553项Flutter测试通过；核心文件静态分析0 issue。全仓68个既有warning/info未在本任务修改；真实浏览器慢网和原生连接生命周期待T22。

### T14 当前→目标（2026-09-09）
- REPLACE：LAN KDS 服务端允许同一设备多条WebSocket并直接`add`消息，无连接/发送预算 → 以`device_code`替换旧连接，发送由串行有界会话处理。
- ADD：默认32台设备、每设备32帧/64KiB待发数据、单帧5秒写预算；超限或写失败以1008仅关闭慢终端，避免其拖垮收银进程。
- PRESERVE：可见队列过滤、事件协议和既有`/kds/v2/changes`游标补拉契约不变。连接替换、容量拒绝及常规广播性能均有本地回归。

### T15 当前→目标（2026-09-09）
- REPLACE：所有未完成 outbox 行全量读入 Dart 后才分组 → SQL 聚合选出最多4个到期聚合头，再按聚合最多读取50条连续事件。
- ADD：未完成聚合序号索引；队头状态、退避和发送前置条件继续逐条判定，阻塞时不跳过后续事实。
- PRESERVE：批发送优先级、聚合内顺序、重试和死信语义不变；1万积压基准通过。
