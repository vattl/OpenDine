# Implementation Design — WI-002

## Root Fix / Owner

在云端认证后的控制器边界完成 actor/tenant 授权，在领域服务再次校验业务对象门店；状态与归档规则由批次/聚合权威层统一维护。

## Why this location

前端隐藏按钮、代理路由和调用者自律都不是安全边界。控制器负责“谁能调用哪类命令”，领域层负责“目标资源是否属于该门店以及状态转换是否合法”。

## End-to-End Change

### Backend

1. 设置读取只使用已认证设备门店，使用字段白名单响应。
2. KDS 设备命令入口拒绝 POS 财务命令；管理员入口继续使用 JWT/门店上下文。
3. POS 退菜在领域执行前校验订单门店。
4. V2 标准命令统一校验设备 workflow 和目标队列；配置写使用明确权限能力。
5. 自动清台读取门店开关；完成回撤继续恢复接单状态。
6. 归档只接受完成订单，清理改为保留可审计/可回撤的安全策略。
7. 聚合失败向上抛出，使命令事务回滚。

### Frontend

本仓先输出消费者交接；若同步修改 KDS/Admin 仓，则移除 `123456` 预填、支持 PIN 未配置态和 403 稳定拒绝。

### Data / Persistence

优先无 DDL。默认 PIN 迁移若执行，使用独立可回滚 SQL，并在部署前完成轮换。

### Interfaces / Contracts

同步 `docs/openapi.yaml`、`docs/API.md`；权限收紧标记 ACTION_REQUIRED，不伪装为完全兼容。

### Jobs / Events / Integrations

命令仍由既有 ledger、event store 和 after-commit publish 驱动。归档调整不得生成未提交 WS 事件。

## Preserve / Compatibility

- 不改变 V2 命令信封、revision、patch 和 event_seq 结构。
- 不改变正式收银 POS 接口。
- WI-001 完成态回撤继续有效。

## API Consumer Migration / Handoff

见 `api-consumer-handoff.md`。

## Failure / Boundary Behavior

- 跨门店/越权：HTTP 403、稳定业务错误，不重试为 UNKNOWN。
- 参数错误：HTTP 400。
- 聚合/存储失败：HTTP 500，命令事务回滚，账本不得标记 APPLIED。

## Runtime / Performance / Reliability

授权检查只使用已加载设备 workflow 和已有目标查询；不得引入逐明细 N+1。归档与历史回归需覆盖大订单批量路径。

## Security / Permissions

STRIDE 重点：Spoofing（默认 PIN/自动绑定）、Information Disclosure（PIN/跨门店配置）、Elevation of Privilege（POS/配置/跨 workflow）、Tampering（归档/退菜）、Repudiation（保留 actor 与操作日志）。

## UI Design Track

当前后端切片不改 UI；PIN 消费者变更需沿现有登录/设备管理视觉模式完成，不新建设计系统。

## Vertical Slice Plan

详见 `plan.md`。

## Verification Strategy

每片先添加可稳定复现漏洞的负向测试（RED），再做最小修复（GREEN）；最后执行 KDS 定向套件、契约解析、全量测试和强制 JAR 打包。

## Rollback / Recovery

每片保持独立差异；权限收紧如需回滚只回滚对应控制器/领域检查，不回滚 WI-001。PIN 数据迁移必须先备份并提供恢复脚本。

