# C009 / T06 配送与投影补偿调度隔离

## 已实现的边界

配送状态同步与厨房投影补偿不再依赖共享的 Spring `@Scheduled` 工作线程。

| 作业 | 专用线程 | 初始批次/预算 | 游标行为 |
|---|---:|---:|---|
| 真省钱配送同步 | `takeout-delivery-sync` | 20 条 / 20 秒 | 按 `t_takeout_delivery.id` 递增；批满下轮续跑，尾页后归零 |
| KDS 投影补偿 | `kds-projection-compensation` | 32 单 / 10 秒 | 按 `t_order.id` 递增；批满下轮续跑，尾页后归零 |

两个执行器各固定一条守护线程。配送远端调用阻塞时，不占用厨房投影补偿线程。每次循环为 fixed-delay：前一轮结束后才开始下一轮，不堆叠同类执行。异常由各自循环捕获，后续轮次继续。

配送只查有 ZSQ open order、仍在同步状态、且 ID 大于本地游标的记录；门店关闭同步开关的记录同样推进游标，避免其永久阻塞后续订单。单轮因预算提前结束时，返回最后已尝试 ID，下轮从其后继续；未完成或失败的订单会在游标回绕后重试。KDS 补偿保留原近两天和订单状态筛选，单次最多读取32单，遇到预算停止，失败订单在后续回绕重试。

`zsq.takeout-sync-interval-ms` 保留60秒默认；新增 `zsq.takeout-sync-batch-size=20`、`zsq.takeout-sync-budget-ms=20000`。新增 `kds.projection-reconcile-interval-ms=30000`、`kds.projection-reconcile-batch-size=32`、`kds.projection-reconcile-budget-ms=10000`。预算小于1秒时按1秒保护；批次限制为1至100。关闭 `app.scheduling.enabled` 时两个作业都不启动。

## 本地验收

- `TakeoutZsqSyncSchedulerTest`：验证配送批次游标仅在批次耗尽后回绕、禁用门店同步不调用远端服务。
- `CashierKdsProjectionReconcilerTest`：40条待补订单按32+8覆盖后才回绕，未因批次切换遗漏。
- 同时回归微信退款补偿、KDS delivery、持久化投影意图和有界投影池。

验证命令与结果见任务进度表：31项测试、0 failures/errors。最初回归发现补偿 SQL 的 MySQL `DATE_SUB` 在 H2 无法执行，因此改为绑定两天前的时间参数；筛选语义不变，且本地游标测试能够真实执行。

## 尚待生产验收

单条配送 HTTP 调用未在本项强制取消，连接超时、并发预算归 T08。KDS 每单投影的数据库事务也不是整批硬截止；20秒/10秒仅控制一轮是否继续取下一条。真实 MySQL 和远端延迟下，需要在 T22 记录：

- 配送远端故意阻塞时，KDS 补偿周期与 `kds-projection-compensation` 队列是否仍按30秒运行；
- 1万条活跃配送和缺投影订单的游标回绕、失败重试、扫描行数与完成时间；
- CPU、数据库连接数、每个线程的任务积压，以及作业异常后的下一轮恢复；
- 1×/2×/3×峰值负载下，配送阻塞不使投影意图积压或订单状态丢失。
