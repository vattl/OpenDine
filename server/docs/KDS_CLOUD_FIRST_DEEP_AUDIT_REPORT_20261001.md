# KDS 云端优先、实时乐观交互与安全并发深度审计报告

日期：2026-10-01（2026-10-02 增补订单到屏延迟专项）
状态：`NEEDS_WORK`  
审计基线：三个仓库当前未提交工作树  
目标架构：KDS-CA-1.3 Cloud-first

## 1. 执行摘要

当前生产主链已经具备以下正确方向：

- 云端是设备身份、业务状态、命令终态、revision 和 event sequence 的唯一权威；
- KDS 生产模式固定 Cloud-first；
- 收银端以 `cloudAuthorityMode=true` 启动，只作为可选 LAN 透明代理；
- LAN/Cloud 使用同一云端 Token、正式业务 ID、`command_id` 和 V2 契约；
- 通道切换需要用户确认，并执行身份、游标、revision 与未决命令屏障；
- 每条划菜命令先持久化到 KDS 本地 outbox，网络不确定时不得换 ID 盲目重放。

但当前状态尚不能批准商用发布，主要原因是：

1. 云端 `bootstrap` 读取热路径包含归档写入、逐订单 N+1 查询和补偿写入；
2. 收银代理仍可能把本地 STALE bootstrap 缓存作为成功响应返回，不符合“每次请求必须由云端实时处理返回”的严格模式；
3. outbox 冲刷全局串行，连续划菜只能逐条同步；
4. UI 现有乐观逻辑主要是隐藏原队列切片，没有形成完整的目标队列乐观投影和明确的待同步状态；
5. 现有性能证据没有覆盖真实 KDS→Cloud 与 KDS→Cashier→Cloud 两条端到端链路；
6. 架构文档仍同时存在 Cloud-first、LAN-first 和“商用完成/未完成”互相冲突的结论。

结论：架构方向正确，但需要完成本报告第 8 节的执行计划和第 10 节发布门禁后，才能重新评估为 `COMMERCIAL_READY`。

## 2. 不可变业务原则

以下原则是本轮整改的硬约束：

1. 云端是唯一业务权威，收银端不得执行、批准或伪造划菜成功。
2. 正常请求由 KDS 直接访问云端；收银代理只在传输故障、代理可用且用户确认后成为活动通道。
3. 经过收银代理的请求必须继续转发到同一云端接口并返回云端结果。
4. 严格模式下，云端不可达时代理返回明确失败，不得以本地缓存伪装本次云端成功响应。
5. KDS 可以使用本地快照维持只读显示，也可以接受离线操作进入 outbox，但必须标记 `PENDING/UNKNOWN`。
6. UI 点击必须立即产生本地视觉反馈，不能等待云端响应。
7. “立即显示”不等于“显示为云端已确认”；未确认状态必须对操作者可见且可追踪。
8. 同一业务操作跨重试、重启和通道切换必须保持同一个 `command_id`。
9. 同一订单/明细的命令保持顺序；不同订单可以有界并发。
10. 任何 `UNKNOWN` 必须先查询云端账本结果，禁止跨通道盲目重放。

## 3. 当前真实链路

### 3.1 正常 Cloud-first

```text
点击划菜
  → 生成稳定 command_id
  → 写入 KDS SQLite outbox
  → UI 应用本地乐观投影
  → KDS 直接 POST 云端 /kds/v2/commands
  → 云端命令账本 + 业务变更 + event append 同事务提交
  → HTTP ACK / WebSocket 权威事件
  → 移除本地 pending overlay 和 outbox 记录
```

### 3.2 用户确认切换至 LAN 代理

```text
点击划菜
  → KDS SQLite outbox + 乐观投影
  → KDS 请求收银 LAN 地址
  → 收银透明转发同一 Token、command_id 和正文到云端
  → 云端处理并返回
  → 收银原样返回 KDS
  → KDS 确认并清理 pending
```

### 3.3 云端不可达

```text
命令保留在 KDS outbox
  → UI 显示“离线待同步”或“结果确认中”
  → 收银代理不得本地执行
  → 云端恢复后先 GET /kds/v2/commands/{command_id}
  → APPLIED：确认本地投影
  → NOT_FOUND：允许使用同一 command_id 重发
  → EXECUTING/UNKNOWN：继续等待，不推进同一聚合后续命令
```

## 4. 审计发现

### P1-01：bootstrap 不是纯读取，存在 N+1 与快照一致性风险

位置：`src/main/java/com/lanf/kds/service/KdsWorkflowV2Service.java:194-205`

当前每次 bootstrap 都会：

- 在读取快照前先取得 event cursor；
- 更新归档历史工单；
- 查询全部活动订单；
- 为每个订单单独 `selectCount`；
- 必要时补建工单；
- 随后再读取本次快照。

影响：

- 查询数随活动订单数线性增长；
- 多 KDS 冷启动、切换探测或恢复会重复触发扫描；
- GET 请求制造写锁、重复补偿和数据库竞争；
- 返回快照可能包含取得 cursor 之后才写入的数据；
- 直接拉高启动、代理探测和故障恢复延迟。

目标：bootstrap 只读；归档和缺票补偿迁移至后台投影/修复任务；缺票检测使用批量反连接或分批查询。

### P1-02：严格云端返回模式被 STALE 代理响应破坏

位置：`admin_panel_flutter/lib/src/features/kds_local/server/cashier_kds_lan_server.dart:686-735`

收银端会在云端请求异常或临时失败时返回最多 15 分钟的持久化 bootstrap 缓存，并使用 HTTP 成功状态响应。

目标：

- 严格模式中移除自动 STALE 成功响应；
- 云端不可达时返回明确 503；
- KDS 自己保存的快照只能作为本地离线只读视图，不得冒充本次云端响应；
- 如未来确需 STALE 模式，必须显式配置、人工可见，并与严格模式分离。

### P1-03：现有性能结论未覆盖目标链路

当前收银性能测试以 `cloudAuthorityMode=false` 运行，测量的是旧本地模式；服务端 100 并发报告直接执行数据库 SQL，没有覆盖 HTTP、鉴权、序列化、代理、TLS、连接池或真实 KDS 调度器。

目标：分别测量：

1. KDS → Cloud；
2. KDS → Cashier LAN TLS → Cloud；
3. 断网积压 → 恢复并发排空；
4. 多订单并发与单订单严格顺序；
5. WebSocket 事件确认和 HTTP ACK 竞态。

### P1-04：架构和验收文档互相冲突

- `docs/KDS_ARCHITECTURE.md` 仍描述 LAN-first；
- `docs/API.md` 标题和正文仍描述“收银代理优先”；
- `docs/openapi.yaml` 声明正常经收银代理；
- KDS-CA-1.3 则明确 Cloud-first、人工确认切换；
- KDS-CA-1.3 状态表写明真实三进程故障矩阵仍阻断商用；
- 商用演练报告却宣称 CP4 全部关闭。

目标：KDS-CA-1.3 成为唯一真源；其他文档同步到 Cloud-first，并撤销未经目标链路验证的商用签署。

### P1-05：自动接单同步等待网络打印，阻塞 KDS 事件提交（2026-10-02 已修复）

位置：`src/main/java/com/lanf/controller/OrderController.java` 的自动接单链路。

原链路在 `both` 模式下先同步派发后厨票和前台票，再更新接单状态、创建 KDS 工单并提交事件。云打印连接/读取超时上限可把“下单到 KDS 出菜”放大到数十秒；即使代码把打印定义为 KDS 模式的附加通道，实际执行顺序仍会阻塞数字化主链。

修复：

- KDS 启用时先完成接单状态与 KDS 权威事件事务；
- 物理打印改为事务提交后进入 2 worker、256 队列的有界异步通道；
- worker 重新读取已提交订单和本批明细，不跨线程复用事务内实体；
- `print_only` 模式保持原有同步打印成功门槛，不改变纯打印门店语义；
- 队列拒绝、订单缺失和打印失败均记录 `[kds-print]`，不反向阻塞已提交的 KDS 订单。

结果：KDS WebSocket 事件不再等待飞鹅云网络请求完成；物理打印与 KDS 展示可以并行推进。

### P1-06：订单事件持久化异常被吞，可能形成永久不可追赶订单（2026-10-02 已修复）

位置：`src/main/java/com/lanf/kds/service/KdsWorkflowV2Service.java` 的 `broadcastOrderAccepted` / `publishEnvelope`。

原实现捕获事件构造或持久化异常后仅写 warning，调用事务仍可提交。若 KDS 工单已创建而 durable event 未写入，15 秒 `/changes` 轮询也没有事件可补，且缺票修复任务因工单已存在不会重建，表现为订单长时间不出现在 KDS。

修复：

- durable event 写入失败向上抛出，回滚来源事务，禁止提交“有订单/工单但无事件”的不可追赶状态；
- WebSocket 仅作为低延迟快通道，推送失败单独记录 warning，不回滚已持久化事件；
- 客户端仍可通过 `/changes` 追赶 durable event。

### P2-05：客户端缺少菜品数据来源标识（2026-10-02 已修复）

KDS 文件日志和实时日志新增统一 `[DISH_SOURCE]` 记录，字段包括：

- `source`：`bootstrap_http`、`websocket_push`、`websocket_buffered`、`changes_poll`、`changes_reconnect`、`changes_gap_recovery`、`changes_conflict_recovery`、`command_response`、`business_day_snapshot`、`local_cache`；
- `transport`：`http`、`websocket`、`local_storage`；
- `channel`：`cloud`、`lan` 或 `local`；
- `seq`、`event_id`、`type`、`patches`、`lines_after`。

该日志不记录菜名、Token 或完整业务载荷。现在可直接判断某批菜品是云端 WebSocket 实时推送、HTTP 补偿、收银 LAN 代理转发，还是本地缓存恢复。

### P2-01：outbox 全局串行造成逐条同步

位置：`kds_app/lib/features/board_v2/kds_v2_board_provider.dart:697-887`

虽然调度器可以跳过被 UNKNOWN 挂起的聚合，但最终发送仍在单个 `while` 中逐条 `await controller.command(...)`，因此不同订单也无法并发。

目标：采用“按业务聚合键串行、跨聚合有界并发”的 keyed scheduler。

### P2-02：实时 UI 只有局部乐观隐藏，没有完整乐观投影

位置：`kds_app/lib/features/board_v2/kds_v2_board_provider.dart:625-683`

当前点击后先记录 `optimisticHiddenSlices`，outbox 落盘后刷新 UI。它能够在云端返回前隐藏原队列切片，但没有统一表达：

- 切片已经乐观进入哪个目标队列；
- 当前是本地待落盘、待发送、发送中、UNKNOWN 还是冲突；
- 云端事件与本地未决操作叠加时怎样避免界面回跳。

目标：以 `authoritativeState + ordered optimistic overlays` 生成可见状态，并显示待同步标识。

### P2-03：代理 WebSocket 下游升级失败可能泄漏上游连接

位置：`admin_panel_flutter/lib/src/features/kds_local/server/cashier_kds_lan_server.dart:2103-2139`

代理先建立云端 WebSocket，再升级 KDS 下游连接；如果下游升级抛错，上游尚未注册进清理映射，缺少 `finally` 关闭路径。

### P2-04：HTTP 接受 URL 查询参数设备 Token

位置：`src/main/java/com/lanf/kds/interceptor/KdsDeviceAuthInterceptor.java:90-100`

全部 KDS HTTP 路由均接受 `?device_token=`，Token 可能进入代理和访问日志。HTTP 应只接受 `X-Kds-Device-Token`；query token 仅限确有平台限制的浏览器 WebSocket。

### P3-01：KDS 设置文案仍暗示云端是备用通道

设置页把云端描述成“收银故障时的容灾直连”，LAN 示例仍使用正式版拒绝的明文 HTTP，需要与 Cloud-first 统一。

## 5. 目标实时 UI 模型

### 5.1 状态分层

```text
Authoritative State（云端最后确认）
              +
Optimistic Overlay（按 command_id 排序的本地未决操作）
              =
Visible State（操作者实时看到的界面）
```

每条 overlay 至少包含：

- `command_id`；
- aggregate key；
- 操作类型和目标；
- 创建顺序；
- 原通道；
- `PERSISTING | PENDING | SENDING | UNKNOWN | CONFLICT`；
- 乐观投影前后的最小可逆差异；
- 最后错误和重试时间。

### 5.2 UI 行为

1. 点击后一个渲染帧内应用 overlay，不等待云端。
2. 原队列立即减少，目标队列立即出现对应数量。
3. 未确认切片显示轻量“待同步/确认中”标识，不阻塞其他订单操作。
4. 本地落盘失败：立即撤销 overlay，并显示不可忽略的本地存储错误。
5. 云端 ACK：合并权威结果后移除 overlay，不产生视觉跳回。
6. WebSocket 先于 HTTP ACK 到达：按 `command_id/event_seq` 去重并确认 overlay。
7. 网络错误：保留投影，状态变为 `UNKNOWN`，不得显示为已确认。
8. 409：撤销冲突命令及其依赖 overlay，只刷新对应订单并提示操作者。
9. 应用重启：从 SQLite outbox 重建 overlay，恢复同一可见状态。

## 6. 安全并发模型

### 6.1 聚合键

优先级：

1. `order_id`；
2. 无订单 ID 时使用 `detail_id`；
3. 配置类命令使用独立全局配置键；
4. 无法确定聚合键的命令进入保守串行通道。

### 6.2 调度规则

- 同一 aggregate key 内严格 FIFO；
- 不同 aggregate key 最多 4 个并发 worker，配置上限为 8；
- 一个聚合最多一个在途 HTTP 写请求；
- `UNKNOWN/EXECUTING` 只暂停本聚合；
- 全局离线、通道 handover 或登录态变化暂停领取新任务；
- 已在途请求允许在有界时间内完成，之后进入 UNKNOWN 裁决；
- 429、连接池排队或 p95 超阈值时自适应降并发；
- 不允许为了并发复制或更换 command ID。

### 6.3 公平性与背压

- 调度使用轮询或最老待办优先，避免单个大订单饿死其他订单；
- outbox 保持现有容量保护，不静默丢弃；
- 暂停聚合不占用 worker；
- 必须暴露 active workers、ready aggregates、oldest pending age、drain rate 和 UNKNOWN 数量。

## 7. 性能与可靠性验收指标

| 指标 | 目标 |
|---|---:|
| 点击到乐观 UI 可见 p95 | ≤ 50 ms |
| 点击到乐观 UI 可见 p99 | ≤ 100 ms |
| SQLite outbox 落盘 p95 | ≤ 50 ms |
| Cloud-direct 命令端到端 p95 | ≤ 300 ms |
| LAN 代理链命令端到端 p95 | ≤ 400 ms |
| LAN 代理额外开销 p95 | ≤ 75 ms |
| 500 活动订单 bootstrap p95 | ≤ 500 ms，且无逐订单查询 |
| 恢复排空吞吐 | 并发 4 时 ≥ 8 commands/s |
| 同订单乱序 | 0 |
| 重复业务执行 | 0 |
| 已持久化命令丢失 | 0 |
| UNKNOWN 跨通道盲重放 | 0 |
| 严格模式本地 STALE 成功响应 | 0 |
| WebSocket 上游连接泄漏 | 0 |

以上阈值必须在真实三进程、真实 TLS、真实 MySQL 环境测量，不能用直接 SQL 或旧本地权威测试替代。

## 8. 详细执行计划

### Phase 0：契约与门禁统一

#### T01 — 固化 Cloud-first 严格模式契约

操作：`MODIFY / REPLACE`

- 把 KDS-CA-1.3 明确为唯一架构真源；
- 定义严格模式下代理不得返回 STALE 成功响应；
- 定义本地快照仅作为 KDS 离线视图；
- 统一 API、OpenAPI、设置页和运维文案。

验收：全文搜索不再把 LAN 描述为正常主通道；没有文档同时宣称“未验收”和“商用完成”。

#### T02 — 建立目标链路基准测试骨架

操作：`ADD`

- 为 Cloud-direct 与 LAN-proxy 建立相同业务数据、命令集和统计口径；
- 记录 p50/p95/p99、吞吐、错误率、积压和连接数；
- 先记录整改前基线，不以阈值失败阻断开发。

依赖：T01。

### Checkpoint CP0

- 架构和性能口径获得人工确认；
- 不开始并发实现，直到 aggregate key 和严格 STALE 策略冻结。

### Phase 1：云端与代理热路径修复

#### T03 — 将 bootstrap 改为纯只读批量路径

操作：`REPLACE / MOVE`

- 把归档迁入 `KdsArchiveJob` 或等价维护任务；
- 把缺票补偿迁入订单投影或有界修复 worker；
- 用批量 SQL 找出缺票订单，禁止逐订单 `selectCount`；
- 在一致性边界内生成 snapshot cursor；
- 添加“bootstrap 不执行 UPDATE/INSERT”负向测试。

验收：500 活动订单下查询次数为常数级；并发 bootstrap 不产生补偿竞争；p95 达标。

#### T04 — 收银代理严格云端返回与 WS 生命周期修复

操作：`MODIFY / REMOVE`

- 严格模式移除 bootstrap STALE 成功回退；
- 保留缓存写入仅供诊断或未来显式离线视图，不参与正常代理响应；
- 下游升级、鉴权复验或注册失败时关闭已建立的上游 WS；
- 增加连接计数和失败升级泄漏测试。

依赖：T01。

#### T05 — 收紧 Token 传输边界

操作：`MODIFY / REMOVE`

- HTTP KDS 路由只接受 Header Token；
- WebSocket 原生客户端只用 Header；
- 浏览器 WS query token 例外必须在握手层显式限定并脱敏日志。

验收：HTTP query token 返回 401；日志不出现原始 Token。

### Checkpoint CP1

- 云端/代理定向测试通过；
- 若 API 行为发生修改，同步 `docs/openapi.yaml`、`docs/API.md`；
- 执行 `mvn clean package -DskipTests` 并生成 JAR；
- bootstrap 与代理基线复测通过。

### Phase 2：实时乐观投影

#### T06 — 引入可恢复的 optimistic overlay 模型

操作：`REPLACE`

- 用结构化 overlay 替代仅隐藏切片的表示；
- 实现从权威状态重放全部 pending overlays；
- 定义每类命令的 apply、confirm、rollback；
- 重启后根据 SQLite outbox 重建 overlay；
- pending 状态不得写回权威 reducer。

验收：点击一个渲染帧内更新；重启后显示一致；云端事件到达不造成回跳。

#### T07 — 完成待同步状态 UI

操作：`MODIFY`

- 目标队列显示乐观切片；
- 显示 `待落盘/待同步/发送中/确认中/冲突`；
- 不使用全屏 loading 阻塞其他订单；
- 提供订单级重试/查看错误入口，禁止生成新 command ID。

依赖：T06。

### Checkpoint CP2

- Widget/Golden 测试覆盖即时移动、ACK、409、离线和重启恢复；
- 点击到渲染 p95/p99 达标；
- 无“先消失但不知道去了哪里”的卡片。

### Phase 3：按聚合安全并发

#### T08 — 实现 keyed outbox scheduler

操作：`REPLACE`

- 按 aggregate key 建立 FIFO 队列；
- 使用默认 4、上限 8 的有界 worker pool；
- 每个聚合最多一个在途写；
- worker 生命周期可停止、可等待、可在 session 切换时安全释放；
- 加入公平调度与自适应降速。

依赖：T06。

#### T09 — UNKNOWN、通道切换与并发屏障

操作：`MODIFY`

- UNKNOWN 只冻结所属聚合；
- 切换通道时停止领取任务，等待或裁决在途命令；
- 同一 ID 在目标通道先 resolve，再决定是否重发；
- 旧 generation 的迟到响应不得覆盖当前 UI。

依赖：T08。

#### T10 — 并发可观测性

操作：`ADD / MODIFY`

- 指标：worker 使用量、聚合数、发送速率、最老积压、UNKNOWN、409、429、通道和 drain 时长；
- 日志统一 request ID、command ID、aggregate key、channel generation；
- 告警区分单聚合阻塞和全局阻塞。

依赖：T08。

### Checkpoint CP3

- 同订单 100 条命令顺序完全一致；
- 100 个不同订单并发时达到吞吐目标；
- 某一订单 UNKNOWN 不阻塞其他订单；
- 反复登录、切换、销毁页面后无遗留 worker/timer/subscription。

### Phase 4：真实三端验收与发布

#### T11 — 真实故障矩阵

- Cloud-direct 正常、超时、响应丢失、进程重启；
- LAN-proxy 正常、收银重启、上游断开、下游升级失败；
- 双路不可用期间连续划菜；
- 云端恢复、命令解析、人工回切；
- HTTP ACK 与 WebSocket 事件不同到达顺序；
- KDS 在 PENDING/SENDING/UNKNOWN 各状态崩溃重启。

验收：零丢失、零重复、零伪成功、界面最终与云端一致。

#### T12 — 负载、灰度与签署

- 分别记录两条通道的端到端指标；
- 并发度先灰度为 2，再升到 4；
- 观察 409、UNKNOWN、p95、云端连接池和数据库锁；
- 达标后更新正式演练报告和执行游标；
- 只有全部门禁通过才重新签署 `COMMERCIAL_READY`。

依赖：T01-T11。

## 9. 任务依赖图

```text
T01 契约冻结 ──> T02 基准骨架
      │
      ├──> T03 bootstrap 纯读
      ├──> T04 代理严格模式/WS 生命周期
      └──> T05 Token 边界

T06 Overlay ──> T07 实时 UI
      │
      └──> T08 Keyed Scheduler ──> T09 切换屏障
                                  └──> T10 观测

T01-T10 ──> T11 真实故障矩阵 ──> T12 灰度与签署
```

T03-T05 在契约冻结后可以并行；T06 必须先于 T07/T08；T08-T10 与共享 provider/outbox 代码重叠，应在独立 worktree 中协调提交。

## 10. 发布门禁

以下任一项未满足，状态保持 `NEEDS_WORK`：

- [ ] 所有现行文档统一 Cloud-first；
- [ ] 严格模式不存在本地 STALE 成功响应；
- [ ] bootstrap 为纯读取且不存在逐订单查询；
- [ ] UI 在云端返回前完成乐观投影并明确显示 pending；
- [ ] 不同订单有界并发、同订单严格串行；
- [ ] UNKNOWN 仅阻塞所属聚合并先 resolve；
- [ ] 代理下游失败不会泄漏上游 WS；
- [ ] HTTP query token 已退役；
- [ ] 两条真实端到端链路达到第 7 节指标；
- [ ] 真实三进程故障矩阵通过；
- [ ] 服务端 API 文档同步并完成 Maven JAR 包构建；
- [ ] 三个仓库均在明确提交上完成全量测试和发布物校验。

## 11. 回滚策略

- keyed scheduler 使用运行时配置控制并发度，紧急回滚到 `1` 即恢复串行，不回退幂等协议；
- optimistic overlay 若出现显示错误，可关闭“目标队列投影”，但仍保留 outbox 与 pending 标识；
- 严格云端模式不得回滚到本地执行命令；
- bootstrap 修复 worker 可独立停用，不能把补偿写重新放回 GET 请求；
- 数据库、command ledger、event sequence 和 command ID 契约不因客户端回滚改变。

## 12. 本次审计验证记录

- KDS App 定向测试：54 项通过；
- 收银代理定向测试：62 项通过；
- 云端第一组定向测试：9 项通过；
- 云端 bootstrap/营业日补偿组：8 项通过、真实环境门控 1 项跳过；
- 收银性能测试输出 `bootstrap p95=64.687ms`，但使用旧 `cloudAuthorityMode=false`，不能作为目标架构验收数据；
- 2026-10-01 初次审计未修改 API 或生产代码；后续生产代码修复见下方专项增补。

### 2026-10-02 订单到屏延迟专项增补

- 修复前失败用例确认：KDS 模式仍同步调用两次打印派发；durable event 写入失败未向上抛出；
- 修复后服务端定向测试 15 项通过，覆盖自动接单、异步附加打印、事件持久化失败、WebSocket 降级和收银/KDS 解耦；
- KDS controller 定向测试 41 项通过，覆盖 bootstrap、WebSocket 与 `/changes` 轮询来源标识及诊断失败隔离；全量测试 354 项通过、1 项既有跳过；
- KDS Windows Release 与服务端 runnable JAR 均构建成功；
- 本次未增加、修改或删除 API endpoint，OpenAPI 契约不变；
- 报告整体状态仍保持 `NEEDS_WORK`，因为第 10 节其他发布门禁尚未全部关闭。

## 13. 关联执行文件

- `docs/changes/KDS-cloud-first-realtime-concurrency-execution-plan-20261001.md`
- `tasks/active/KDS-cloud-first-realtime-concurrency-20261001.md`
- 跨仓库架构真源：`admin_panel_flutter/docs/KDS_CLOUD_AUTHORITY_PROXY_ARCHITECTURE.md`

