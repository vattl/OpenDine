# KDS 队列、命令账本与事件存储保留与归档策略规范 (KDS-RET-1.0)

> 适用范围：`server`（云端服务）、`admin_panel_flutter`（收银端边缘代理）、`kds_app`（厨显端）  
> 规范状态：**ACCEPTED / OPERATIONAL SPEC**  
> 关联任务：T006 (队列、账本与保留策略)  
> 遵循架构真源：`KDS_CLOUD_AUTHORITY_PROXY_ARCHITECTURE.md` (KDS-CA-1.3)

---

## 1. 核心架构原则

1. **热冷分层 (Hot / Cold Tiering)**:
   - 热表只保留活动及近期高频查证数据，保障核心事务毫秒级低延迟与高并发。
   - 历史终态数据分批沉降至归档冷表，避免单表无界膨胀与全表扫描。
2. **幂等性永不妥协 (Zero Loss Idempotency)**:
   - 即使命令已沉降至冷表，`resolve(command_id)` 与重试 `claim` 必须透明回查冷表，返回确定性结果，严禁因归档导致重复执行或将已执行命令宣告为 `NOT_FOUND`。
3. **分批提取与流控 (Bounded Batching)**:
   - 本地待决队列严格按 `next_attempt_at_ms <= now` 进行由于到期的分批查询（带 `LIMIT`），杜绝全表扫描与并发惊群。
4. **禁止静默截断 (No Silent Truncation)**:
   - 跨版本数据迁移、进程重启与清理策略中，严禁静默丢弃任何未决（`PENDING`/`UNKNOWN`）指令。

---

## 2. 云端保留与归档策略 (`server`)

### 2.1 命令账本 (`t_kds_v2_command` & `t_kds_v2_command_archive`)

| 维度 | 热表 (`t_kds_v2_command`) | 归档冷表 (`t_kds_v2_command_archive`) |
|---|---|---|
| **状态范围** | `EXECUTING`（全量）、`APPLIED`/`REJECTED`（近期） | 仅限终态：`APPLIED`、`REJECTED` |
| **保留周期** | 默认 7 ~ 30 天 | 长期归档（默认 1 年或按法规合规保留） |
| **索引设计** | `PRIMARY KEY (shop_id, command_id)`<br>`KEY (status, updated_at)` | `PRIMARY KEY (shop_id, command_id)`<br>`KEY (status, updated_at)`<br>`KEY (archived_at)` |
| **读穿透** | 优先查询热表 | 若热表未命中，透明回查冷表（返回 `archived: true`） |
| **防重放** | 热表基于 `INSERT IGNORE` 锁行 | 若热表无行但冷表存在，自动撤销热表占位并重放冷表终态结果，杜绝重复执行 |

#### 归档执行机制 (`KdsV2RetentionService.archiveTerminalCommands`)
- 由定时调度任务 `KdsArchiveJob` 周期执行（每 15 分钟触发一次各门店工单与历史命令检查）。
- 单批次限制 500 ~ 2000 条，执行 `INSERT IGNORE INTO ... SELECT ...` + `DELETE`，事务内快速提交，避免长时间锁表。

### 2.2 事件存储 (`t_kds_v2_event` & `t_kds_v2_event_archive`)

- **增量热表 (`t_kds_v2_event`)**:
  - 每家门店热区保留最新 `RETAINED_EVENTS_PER_SHOP = 500` 条事件，用于支撑客户端 `GET /kds/v2/changes?after_seq=` 单调追赶。
  - 单调全局序列由 `t_kds_v2_event_cursor` 行级锁分配。
- **历史归档 (`t_kds_v2_event_archive`)**:
  - 当事件序列推进淘汰老事件时，先 `INSERT IGNORE` 沉降至冷表，再物理清除热表。
  - 客户端请求 `after_seq` 严重落后（超出热表最小序列）时，返回 `snapshot_required = true`，引导客户端拉取完整权威快照恢复。

---

## 3. 收银端边缘保留与清理策略 (`admin_panel_flutter`)

### 3.1 待决命令本地存储 (`pending_commands`)

- **到期分批拉取 (`readDuePendingCommands`)**:
  - 依托索引 `idx_pending_due ON pending_commands(status, next_attempt_at_ms, occurred_at_ms)`。
  - 仅拉取 `status IN ('PENDING', 'UNKNOWN') AND next_attempt_at_ms <= ?`，单批默认 `limit = 50`。
- **终态清理 (`cleanupRetention`)**:
  - 清理周期：`terminalCommandRetention = 30 days`。
  - 仅物理删除终态（`APPLIED`, `REJECTED`, `ACKED`, `CONFLICT`）且 `updated_at <= cutoff` 的陈旧命令行。
  - 严格保护未完成（`PENDING`, `UNKNOWN`, `SENDING`）记录，无论时间多久均不删除。

---

## 4. 厨显端 Outbox 保护 (`kds_app`)

- **跨版本迁移零丢失**:
  - `KdsCommandOutboxStore._migrateLegacyShop` 从旧 Preferences 迁入 SQLite 时，全量写入 `t_kds_outbox`。
  - 超出建议软容量时记录预警日志，绝对禁止使用 `sublist` 截断丢弃。
- **重启恢复**:
  - 启动时自动将 `SENDING` 状态复位为 `RETRY_WAIT`，标记 `requires_resolution = 1`，通过云端命令查证接口闭环状态。

---

## 5. MySQL 8.0 大容量分区进阶实践（运维指导）

当单店日订单量 > 10,000 笔、全平台年命令量超过 50,000,000 笔时，建议对归档表实施 MySQL 8.0 RANGE 分区：

```sql
-- 示例：按月范围分区
ALTER TABLE t_kds_v2_command_archive 
PARTITION BY RANGE (YEAR(archived_at) * 100 + MONTH(archived_at)) (
    PARTITION p202609 VALUES LESS THAN (202610),
    PARTITION p202610 VALUES LESS THAN (202611),
    PARTITION p202611 VALUES LESS THAN (202612),
    PARTITION p_max VALUES LESS THAN MAXVALUE
);
```

维护脚本可按月执行 `ALTER TABLE ... DROP PARTITION` 实现毫秒级冷数据转储或清理。
