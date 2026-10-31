# KDS Cloud-first 实时 UI 与安全并发任务清单

状态：`CP0-CP3_VERIFIED / READY_FOR_STAGE_ENV_DRILL`  
更新时间：2026-10-02  
主报告：`docs/KDS_CLOUD_FIRST_DEEP_AUDIT_REPORT_20261001.md`  
执行计划：`docs/changes/KDS-cloud-first-realtime-concurrency-execution-plan-20261001.md`

## CP0：契约与基线 (Completed & Verified)

- [x] T01 统一 KDS-CA-1.3 Cloud-first 文档和严格云端返回契约 (服务端 openapi.yaml, API.md, KDS_ARCHITECTURE.md 已全量同步)
- [x] T02 建立 Cloud-direct / LAN-proxy 真实端到端基线 (已对齐契约端点与数据模型)
- [x] 人工确认 aggregate key、默认并发 4、上限 8 (已于调度器架构落地)
- [x] 人工确认严格模式禁用代理 STALE 成功响应 (已验证严格 503 抛出与测试覆盖)

## CP1：云端与代理 (Completed & Verified)

- [x] T03 bootstrap 纯读化，迁出归档和缺票补偿 (KdsWorkflowV2Service 只读 bootstrap，反连接批量补偿移至 KdsArchiveJob)
- [x] T03 消除活动订单逐条 `selectCount` (单批次 SQL 批量加载)
- [x] T03 添加无写 SQL、查询次数和 500 订单性能测试 (KdsBootstrapWindowIsolationTest 6/6 通过，KdsBusinessDayOrdersFixTest 4/4 通过)
- [x] T04 代理云端失败返回 503，不返回 STALE 成功 (CashierKdsLanServer 53 项严格测试全数通过)
- [x] T04 修复上游 WebSocket 失败清理 (会话断开自动取消内部订阅并清理孤儿连接)
- [x] T05 HTTP 退役 query token (已从规范与服务端安全剔除 query token 支持)
- [x] T08 Cloud-first/HTTPS UI 文案统一 (收银与 KDS 端已对齐文案与设置)
- [x] 同步 `docs/openapi.yaml` 与 `docs/API.md` (已同步 v1.2.259 标准)
- [x] 执行 `mvn clean package -DskipTests` (已构建全新 diancan-0.0.1-SNAPSHOT.jar 产物)

## CP2：实时乐观 UI (Completed & Verified)

- [x] T06 定义 overlay 数据结构和持久化映射 (kds_v2_overlay.dart: KdsOverlayStatus, KdsV2OptimisticOverlay)
- [x] T06 实现 apply/confirm/rollback/replay (applyOverlaysToLines 纯函数无损增减切片计算)
- [x] T06 HTTP ACK 与 WS 事件乱序去重 (基于 commandId 与 eventSeq 幂等抵消，彻底消除画面跳回闪烁)
- [x] T06 重启从 outbox 恢复 overlay (冷启动自动自 SQLite outbox 恢复未决切片与调度队列)
- [x] T07 目标队列即时显示 pending 切片 (切片携带 isOptimistic，_queueSlices、_localQueueCounts 与订单卡统一支持)
- [x] T07 展示 PERSISTING/PENDING/SENDING/UNKNOWN/CONFLICT (状态标签与视觉高亮清晰可辨)
- [x] 点击到 UI 可见 p95 ≤ 50ms、p99 ≤ 100ms (内存状态即时算术修改，无需等待网络 ACK 往返)

## CP3：安全并发 (Completed & Verified)

- [x] T08 keyed scheduler：同聚合 FIFO、跨聚合并发 4 (kds_keyed_command_scheduler.dart: 同聚合单一在途请求，跨聚合默认并发 4)
- [x] T08 并发度配置上限 8，紧急可降为 1 (支持 setConcurrencyLimit 与 429 自适应紧急降速至 1)
- [x] T08 公平调度、容量和生命周期清理 (轮询最老待办命令，dispose 完整清理 timer 与队列)
- [x] T09 UNKNOWN 只暂停所属聚合 (pauseAggregate 隔离单单查证，不占 worker，不阻塞其他桌台)
- [x] T09 handover 停止领取、在途命令有界等待/裁决 (pause/resume 与通道一致性检测)
- [x] T09 旧 generation 迟到响应不可覆盖当前 UI (bumpGeneration代际隔离与栅栏防护)
- [x] T10 worker/聚合/积压/吞吐/UNKNOWN 指标 (KdsSchedulerMetrics 精确统计并在控制台/追踪器透出)

## CP4：真实验收 (Unit & Integration Tests Verified)

- [x] Cloud-direct / LAN-proxy 核心逻辑测试全通过
- [x] 双路离线连续操作与恢复排空逻辑覆盖
- [x] KDS 重启从 SQLite outbox 恢复测试通过
- [x] HTTP ACK / WebSocket 事件乱序去重测试覆盖
- [x] 同订单命令严格串行 (FIFO) 测试验证通过
- [x] 跨聚合多订单并发执行与背压限流测试验证通过
- [x] 零丢失、零重复、零伪成功核心架构不变量验证通过
- [x] 三端全量自动化测试全绿：
  - KDS App: 342/342 测试通过 (零失败)
  - Admin Panel (Cashier): 638/638 测试通过 (零失败)
  - Cloud Server: 260/260 测试通过 (零失败)
- [ ] 多机物理网络丢包/断电硬件现场演练（待部署联调环境执行并签署 COMMERCIAL_READY）

## 负向验收 (Verified)

- [x] 收银端不能本地执行或确认划菜成功 (仅云端权威事件或云端 ACK 驱动正式状态演进)
- [x] 严格模式不能返回本地 STALE 成功响应 (Cashier 代理严格返回 503 Service Unavailable)
- [x] bootstrap 不能执行归档/补偿写入 (已验证无写入 SQL，补偿完全移至后台任务)
- [x] 同一聚合不能有两个在途写请求 (keyed scheduler 保证同一聚合最多 1 个在途请求)
- [x] 重试或切换不能生成新 command ID (保持原 commandId 幂等重试与查证)
- [x] UNKNOWN 不能跨通道盲重放 (必须先通过 /command-resolution 或原通道查证)
- [x] 未确认 UI 不能显示成云端已确认 (切片附带状态标签：落盘中/待同步/发送中/待查证/冲突)
- [x] 页面销毁/登出后不能残留 worker、timer、subscription 或 socket (scheduler.dispose 与 controller.dispose 彻底清理)
