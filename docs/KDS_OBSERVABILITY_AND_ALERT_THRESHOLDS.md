# KDS 商用可观测性与告警阈值规范手册 (KDS-OBS-1.0)

本文档确立 KDS 2.0 在云端（Cloud Authority）、收银端（Cashier LAN Proxy）与厨显端（KDS App）三端同构架构下的商用可观测性、链路追踪标准、度量指标与告警阈值分级规范。

---

## 1. 链路追踪标识规范 (Correlation Standard)

为了实现复杂弱网、断网重连与局域网代理转发环境下的跨端端到端问题定位，所有 HTTP 请求与响应、WebSocket 消息包及交互日志均统一遵循以下追踪标识三元组：

| Header 名称 | 作用域与定义 | 传递规范 | MDC 日志键 |
|---|---|---|---|
| `X-Request-Id` | 全局请求/链路追踪 ID（UUID v4 或带来源前缀） | 客户端生成；局域网代理透明透传；服务端响应头**强制回写** | `requestId` |
| `X-KDS-Command-Id` | 业务指令幂等唯一标识（UUID） | 伴随写指令（POST `/kds/v2/commands`、GET `/kds/v2/commands/{id}`）；全链路透传 | `commandId` |
| `X-KDS-Device-Code` | 厨显硬件设备唯一编码（如 `KDS-GRILL-01`） | 由设备发起请求时携带，或局域网代理根据绑定会话附加 | `deviceCode` |

### 响应头与日志贯穿要求：
1. **服务端响应**：每个 HTTP 响应头必须包含 `X-Request-Id: <requestId>`。
2. **收银端代理响应**：局域网 HTTP 代理向 KDS 响应时，必须将云端的 `X-Request-Id` 透传给 KDS；若缓存命中则回写代理自身生成的 `requestId`。
3. **日志排查**：在 SLF4J MDC 中自动注入 `requestId`、`commandId`、`deviceCode`，日志输出格式确保 `[%X{requestId}][%X{commandId}][%X{deviceCode}]` 便于 `grep` 和 ELK 检索。

---

## 2. 商用度量指标采集与 API 端点

云端在 `KdsMetricsService` 中线程安全地维护度量指标采样，并通过以下端点暴露：

- **端点**：`GET /kds/v2/diagnostics/metrics`
- **鉴权**：通过 `X-Kds-Device-Token` 或收银凭据访问。
- **返回结构示例**：
```json
{
  "code": 0,
  "msg": "ok",
  "data": {
    "shop_id": 1,
    "device_code": "DEV-01",
    "uptime_seconds": 86400,
    "commands": {
      "total_count": 12500,
      "success_count": 12420,
      "conflict_count": 60,
      "rejected_count": 15,
      "error_count": 5,
      "conflict_rate": 0.0048,
      "rejection_rate": 0.0012,
      "latency": {
        "avg_ms": 32.5,
        "p95_ms": 78.0,
        "max_ms": 420,
        "min_ms": 8
      }
    },
    "websocket": {
      "dispatched_frames": 45200,
      "acknowledged_frames": 44980,
      "ack_rate": 0.9951,
      "disconnect_reasons": {
        "slow_consumer": 0,
        "ack_timeout": 1,
        "send_timeout": 0
      }
    },
    "traffic": {
      "bootstrap_requests": 12,
      "business_day_requests": 25,
      "changes_requests": 8500,
      "snapshot_to_changes_ratio": 0.0044
    }
  }
}
```

---

## 3. 商用告警阈值分级规范 (Alert Thresholds Matrix)

| 指标项 (Metric) | 统计窗口 | 正常水位 (Normal) | P2 预警阈值 (Warning) | P1 严重阈值 (Critical) | 影响与可能原因 |
|---|---|---|---|---|---|
| **命令 p95 延迟** (`latency.p95_ms`) | 5 分钟 | < 300 ms | > 1,000 ms | > 2,500 ms | 数据库行锁竞争激烈、事务耗时过长或网络抖动 |
| **命令 409 冲突率** (`conflict_rate`) | 10 分钟 | < 1.0 % | > 5.0 % | > 15.0 % | 多台 KDS 并发重复划菜、高频离线重试或版本漂移 |
| **命令 400 拒绝率** (`rejection_rate`) | 10 分钟 | < 0.5 % | > 2.0 % | > 5.0 % | 菜品不存在、非法状态机跃迁或客户端数据投影不一致 |
| **WS 慢消费断开** (`slow_consumer`) | 1 小时 | 0 次 | > 0 次 | > 5 次 | 厨显硬件卡顿、UI 阻塞事件循环、WiFi 严重丢包 |
| **WS ACK 成功率** (`ack_rate`) | 10 分钟 | > 99.0 % | < 95.0 % | < 90.0 % | 厨显网络丢包、WebSocket 虚连接、ACK 序列号失序 |
| **快照/增量比率** (`snapshot_ratio`) | 1 小时 | < 1.0 % | > 5.0 % | > 20.0 % | 客户端错误退化为轮询快照、频繁断网造成全量拉取 |
| **KDS Outbox 最老待决时长** (`oldest_age`) | 实时 | < 10 秒 | > 60 秒 | > 180 秒 | 连续请求失败、断网长时间未恢复或指令死锁 |

---

## 4. 故障排查与应急预案 (Playbook)

### 4.1 收到命令 409 冲突率告警 (P2/P1)
1. 提取 MDC 日志中出现 409 的 `commandId` 与 `deviceCode`：
   `grep "409" logs/kds.log | awk -F'|' '{print $2}' | sort | uniq -c`
2. 检查收银端与厨显端是否发生多设备争抢同一菜品（正常业务竞争），或某台设备断网重连后无节制重试。
3. 检查 `t_kds_v2_command_ledger` 中该指令是否已 `APPLIED`，验证幂等返回是否生效。

### 4.2 收到 WebSocket 慢消费断开告警 (P2/P1)
1. 查看 `WebSocketOutboundDispatcher` 的 session 日志：
   `grep "slow consumer" logs/kds.log`
2. 定位断开设备的 `deviceCode` 与 `session_id`。
3. 检查对应厨显平板的硬件负载与网络 ping 延迟，避免平板因省电休眠导致 TCP 接收窗口填满。

### 4.3 收到快照拉取频率异常告警 (P2)
1. 检查客户端请求日志中 `/kds/v2/bootstrap` 与 `/kds/v2/business-day/orders` 的来源 IP 与设备码。
2. 确认厨显端 `kds_app` 是否未正常运行 `_startFallbackPoll` 增量轮询，而陷入了定时无条件全量拉取的旧版本逻辑。
