# KDS Cloud-first 实时乐观 UI 与安全并发执行计划

日期：2026-10-01  
状态：`PROPOSED`  
主报告：`docs/KDS_CLOUD_FIRST_DEEP_AUDIT_REPORT_20261001.md`

## 1. 目标

在不改变云端唯一权威、稳定 `command_id`、命令账本和人工确认切换的前提下，实现：

- 点击划菜后立即更新界面；
- 同一订单严格顺序；
- 不同订单有界并发；
- 正常 KDS 直连云端；
- LAN 代理只做可选透明转发；
- 所有在线请求由云端实时处理并返回；
- 断网操作可恢复、可裁决、零丢失、零重复。

## 2. Structural Diff

| 操作 | 当前 | 目标 | 负向验收 |
|---|---|---|---|
| REPLACE | bootstrap GET 内归档和逐订单补偿 | 纯读 bootstrap + 后台有界修复 | bootstrap 不执行 UPDATE/INSERT，不逐订单查询 |
| REMOVE | 代理自动返回 STALE bootstrap 成功 | 严格模式返回 503，KDS 本地快照独立展示 | 代理失败响应不得带成功业务正文 |
| REPLACE | `optimisticHiddenSlices` 仅隐藏旧位置 | 可重放、可逆的 optimistic overlay | 未确认操作不得写入权威 reducer |
| REPLACE | 单 while 全局串行发送 | 同聚合 FIFO、跨聚合有界并发 | 同一聚合不得存在两个在途写 |
| MODIFY | UNKNOWN 影响全局冲刷体验 | 只暂停所属聚合 | 单订单 UNKNOWN 不得阻塞其他订单 |
| MODIFY | 通道切换只关注总在途数 | worker 领取门禁 + generation fencing + resolve | 切换不得盲重发或产生新 command ID |
| REMOVE | HTTP query token | HTTP Header-only | `?device_token=` 不得通过 HTTP 鉴权 |
| MODIFY | WS 上游先连、失败路径不完整 | 全路径关闭上游和下游 | 失败升级后连接计数回到基线 |
| MODIFY | LAN-first/Cloud fallback 文案 | Cloud-first/optional LAN | 不得继续出现正常 LAN-first 描述 |

## 3. 任务

### Task 1：契约冻结与文档统一

**描述：** 冻结 Cloud-first、严格云端返回、乐观 UI 和 keyed concurrency 契约。

**验收：**

- [ ] KDS-CA-1.3 是唯一架构真源；
- [ ] API/OpenAPI/设置页不再描述 LAN-first；
- [ ] 明确 STALE 只属于 KDS 本地离线视图。

**验证：** 文档全文搜索与人工架构评审。  
**依赖：** 无。  
**可能涉及：** Server `docs/KDS_ARCHITECTURE.md`、`docs/API.md`、`docs/openapi.yaml`；Cashier/KDS 文档与文案。  
**范围：** M。

### Task 2：端到端基准测试骨架

**描述：** 建立 Cloud-direct 和 LAN-proxy 同口径三进程基准。

**验收：**

- [ ] 输出 p50/p95/p99、吞吐、错误率、积压年龄和连接数；
- [ ] 同一数据集可切换两条通道运行；
- [ ] 测试不使用 `cloudAuthorityMode=false`。

**验证：** 在真实 MySQL、TLS 和三进程环境执行基线。  
**依赖：** Task 1。  
**范围：** M。

### Task 3：bootstrap 纯读化

**描述：** 迁出归档与缺票补偿，并消除逐订单查询。

**验收：**

- [ ] bootstrap 无写 SQL；
- [ ] 查询次数不随订单数线性增加；
- [ ] snapshot cursor 与返回快照处于明确一致性边界。

**验证：** SQL 观察测试、500 订单性能测试、并发 bootstrap 测试。  
**依赖：** Task 1。  
**范围：** M。

### Task 4：代理严格模式与连接生命周期

**描述：** 移除 STALE 成功回退并修复 WS 失败清理。

**验收：**

- [ ] 云端不可达时代理返回 503；
- [ ] 收银端不执行命令；
- [ ] 下游升级失败后上游连接关闭；
- [ ] 缓存仍可用于诊断，但不作为严格模式响应。

**验证：** HTTP 失败矩阵、WS 失败注入和连接计数测试。  
**依赖：** Task 1。  
**范围：** M。

### Task 5：结构化 optimistic overlay

**描述：** 用可恢复 overlay 表示本地未决操作。

**验收：**

- [ ] 点击后 50ms p95 内进入目标队列；
- [ ] 状态包含 PERSISTING/PENDING/SENDING/UNKNOWN/CONFLICT；
- [ ] ACK、WS 先到、409、落盘失败均有确定行为；
- [ ] 重启可从 outbox 恢复相同可见状态。

**验证：** reducer、provider、widget 与重启恢复测试。  
**依赖：** Task 1。  
**范围：** M。

### Task 6：keyed 并发调度器

**描述：** 同聚合串行、跨聚合默认 4 并发。

**验收：**

- [ ] 同一订单严格 FIFO；
- [ ] 不同订单最多 4 个并发请求；
- [ ] UNKNOWN 仅冻结所属聚合；
- [ ] 离线、handover、session 销毁可停止领取并清理 worker；
- [ ] 并发度可运行时降为 1。

**验证：** fake transport 调度测试、100 订单压力测试、资源生命周期测试。  
**依赖：** Task 5。  
**范围：** M。

### Task 7：通道切换与 UNKNOWN 屏障

**描述：** 将 keyed scheduler 纳入现有人工切换屏障。

**验收：**

- [ ] handover 不领取新命令；
- [ ] 在途命令在超时后进入 UNKNOWN；
- [ ] 使用原通道/云端账本 resolve；
- [ ] 旧 generation 响应不修改当前 UI。

**验证：** Cloud→LAN、LAN→Cloud、ACK 丢失和迟到响应测试。  
**依赖：** Task 6。  
**范围：** M。

### Task 8：Token 边界与 UI 文案

**描述：** HTTP Header-only，并统一 Cloud-first 操作提示。

**验收：**

- [ ] HTTP query token 被拒绝；
- [ ] 原生 WS URL 不含 Token；
- [ ] 设置页标记云端为主通道、LAN 为可选代理；
- [ ] LAN 正式版示例使用 HTTPS。

**验证：** 鉴权负向测试、日志扫描、Widget 文案测试。  
**依赖：** Task 1。  
**范围：** S-M。

### Task 9：观测和自适应背压

**描述：** 增加并发 worker、聚合、延迟和积压指标。

**验收：**

- [ ] 可区分全局阻塞与单聚合阻塞；
- [ ] 429/延迟超阈值时降低并发；
- [ ] 日志关联 command ID、aggregate key、channel generation。

**验证：** 指标测试和模拟告警。  
**依赖：** Task 6。  
**范围：** M。

### Task 10：真实验收与灰度发布

**描述：** 执行真实三进程故障和负载矩阵，完成发布签署。

**验收：**

- [ ] 主报告第 7 节所有指标达标；
- [ ] 零丢失、零重复、零伪成功；
- [ ] 并发度 2→4 灰度无 409/UNKNOWN 异常增长；
- [ ] 全量测试、Maven JAR、KDS/Cashier 发布物验证完成。

**验证：** 真实环境报告与明确提交哈希。  
**依赖：** Tasks 1-9。  
**范围：** M。

## 4. 检查点

- **CP0 契约：** Tasks 1-2；人工确认后进入实现。
- **CP1 云端/代理：** Tasks 3-4、8；API 文档同步及 JAR 构建。
- **CP2 实时体验：** Task 5；即时显示、回滚和重启恢复通过。
- **CP3 并发：** Tasks 6-7、9；顺序、吞吐和资源生命周期通过。
- **CP4 发布：** Task 10；真实三端签署。

## 5. 工作流建议

- Server bootstrap、Cashier proxy、KDS overlay/scheduler 分别使用独立 worktree；
- 先冻结契约再并行开发；
- KDS overlay 和 scheduler 共用 provider/outbox，必须串行或由同一工作流负责；
- 每个任务独立提交，禁止自动提交当前三个仓库已有的未提交改动；
- API 行为变化同步 `docs/openapi.yaml` 与 `docs/API.md`，并执行完整 Maven package。

