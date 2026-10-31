# WI-002 KDS 安全与一致性修复落地执行方案

## T01 — 跨门店设置与 PIN 响应边界

- RED：设备 A 传 `shop_id=B` 不得读到 B；响应不得含 `kds_pin`。
- GREEN：设置 GET 强制使用认证设备门店，返回字段白名单；移除“登录前裸读取”契约。
- DoD：控制器测试、拦截器测试、OpenAPI/API 文档通过。

## T02 — KDS 设备与 POS 财务命令隔离

- RED：设备入口的四个 POS 命令别名全部 403；管理员入口保持可调用；跨门店 detail 退款拒绝。
- GREEN：控制器 actor allowlist + 领域门店校验。
- DoD：不影响 `/cashier/order/*`，命令账本对拒绝保存稳定终态。

## T03 — 设备 workflow 与配置授权

- RED：prep-only 不能制作/传菜，cook-only 不能配菜/传菜，serve-only 不能配菜/制作/退菜；普通设备不能改门店配置。
- GREEN：集中命令授权器，复用 `KdsWorkflow`；配置写引入明确设备能力或管理员入口。
- DoD：所有命令类型有正/负授权矩阵。

## T04 — 自动清台与长期回撤一致性

- RED：开关 0 时 ALL_DONE 不清台，开关 1 时清台；完成回撤恢复 `rec_order`。
- GREEN：`KdsLegacySyncService` 使用配置开关，保持 WI-001 回撤。
- DoD：订单头、KDS 状态和 bootstrap 三者一致。

## T05 — 归档与历史完整性

- RED：未完成订单不能 archive；完成项在保留窗口内可见且可回撤；clear 不留孤立 batch。
- GREEN：拆分 completed/archived 语义或收紧 archive 命令；清理按保留策略并成对处理 ticket/batch。
- DoD：bootstrap、done、business-day、archive job、回撤回归通过。

## T06 — 聚合事务失败语义

- RED：聚合写失败时推进命令整体回滚，账本不为 APPLIED。
- GREEN：移除核心异常吞噬，仅对非关键通知采用 after-commit/best-effort。
- DoD：故障注入测试证明无半状态。

## T07 — 契约、消费者、审查与发布证据

- 同步 OpenAPI/API/架构说明与消费者 handoff。
- 运行安全静态检查、KDS 定向测试、完整 Maven 测试。
- 强制执行 `mvn clean package -DskipTests` 并记录 JAR SHA-256。
- 独立 review 后按 requirement → implementation → evidence 验收。

## 执行顺序

`T01 → T02 → T03 → T04 → T05 → T06 → T07`

每片保持可编译、可验证；任何消费者尚未同步时 Work Item 保持 PARTIAL，不宣称 DONE。

