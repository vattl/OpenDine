# KDS 云端权威服务端边界

> 架构版本：KDS-CA-1.3；状态：TARGET。跨三端完整设计见 `admin_panel_flutter/docs/KDS_CLOUD_AUTHORITY_PROXY_ARCHITECTURE.md`。本文是服务端入口，不创建第二套方案。

## 服务端职责

- 云端是设备身份、Token、权限、订单/KDS 状态、命令终态、revision 和事件序列的唯一权威。
- KDS 正常优先直连云端（Cloud-first）；收银端是边缘透明代理、缓存和可选容灾暂存节点，仅在传输故障并经用户确认后接管；收银代理不得在严格模式下伪造本地 STALE 成功响应，不得向云端上报一个已经在本地被视为成功的独立状态机。
- STALE 仅属于 KDS 本地离线只读视图，不得作为代理 HTTP 成功响应。
- KDS 经 LAN 代理或直连云端必须使用同一云端 Token、V2 路径、正式业务 ID、`command_id`、revision 和 WS 信封。
- HTTP 接口仅接受请求头 `X-Kds-Device-Token`，URL query token 强制退役拒绝（HTTP 401）。
- 所有写操作最终进入 `/kds/v2/commands` 的同一事务边界；超时通过 `/kds/v2/commands/{command_id}` 解析。
- `/ws/kds/v2` 只发布已提交的云端事件。LAN 只能转发并缓存，不得生成业务 `event_seq`。
- `GET /kds/v2/bootstrap` 必须为纯只读请求，无写 SQL，归档与缺票补偿全部迁移至后台异步任务。

## 契约与迁移真源

- 字段级契约：`docs/openapi.yaml`
- 人类可读摘要：`docs/API.md`
- 云端权威基础迁移：`src/main/resources/db/migration/V008__kds_cloud_authority.sql`

历史 replication/delivery SQL 仍被 debug 初始化或兼容测试引用时，只能视为 `LEGACY_TRANSITIONAL`。它们不能定义新架构；消费者迁出、backlog 对账且观察期完成后，才以更高版本纠正迁移退役。

## 发布阻断条件

- 云端允许收银提供或本地签发设备 Token。
- 允许 HTTP URL 查询参数携带 `device_token` 通过鉴权。
- LAN 与 Cloud 的登录/命令/WS 契约不一致。
- 代理在云端不可达时返回 STALE 200 成功响应。
- `bootstrap` 请求执行 UPDATE/INSERT 或逐单查询。
- 同一命令跨通道更换 `command_id`。
- 业务事件在事务提交前广播，或由收银端自创序列。
- V008 未在真实 MySQL 验证。
