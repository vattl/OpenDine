# C009 / T03 报表及归档任务恢复

## 已实现的资源与一致性边界

| 项目 | 初始预算/行为 |
|---|---|
| 报表执行器 | 1线程、16条本地排队唤醒 |
| 归档执行器 | 独立1线程、16条本地排队唤醒 |
| 数据库未完成任务 | REPORT_EXPORT + ARCHIVE_SEARCH 共128条、同门店4条；NULL门店作为独立总部范围 |
| 受理并发 | 单行InnoDB锁保护配额检查及插入，当前读最多129行，跨实例共用预算 |
| 超额/停机 | HTTP429 REPORT_JOB_QUOTA_EXCEEDED / HTTP503 REPORT_WORKER_CLOSED；不插入新任务 |
| 唤醒拒绝 | 已入库的PENDING保留，不CallerRuns；同实例相同任务ID不重复排队 |
| 重启恢复 | 专用恢复线程每5秒、每类型最多扫描32条；恢复PENDING及租约过期/NULL的RUNNING |
| 执行归属 | SQL条件更新领取32位随机run_token，数据库时钟计算30分钟租约 |
| 结果确认 | 只允许匹配当前run_token且仍RUNNING的执行者提交DONE/FAILED |
| 过期但未接管 | 原执行者仍可完成；租约过期提供接管资格，不自动抹掉已产生的正确结果 |
| 文件隔离 | 每次执行文件名含run_token，旧实例文件不覆盖新执行文件 |

`app.scheduling.enabled=false` 时不启用恢复扫描，仅适合隔离调试。同步 LOG_EXPORT 不属于本次异步配额或恢复范围。

## 部署与回退

先停止旧版报表/归档工作线程，核实备份和DDL锁影响，再显式执行 `docs/db_migration_report_job_recovery.sql`，然后启动新版本。该ALTER脚本只执行一次；应用启动只读检查新列、配额锁行、InnoDB引擎和恢复索引，不自动DDL。

旧版RUNNING任务没有lease_until，可以由新版本领取；PENDING保留；DONE/FAILED不自动重跑。旧版没有执行令牌保护，禁止它与新执行器同时工作。应用回退保留新列、表及未完成任务，不清空任务记录。

多实例必须使用共享 `report.export.dir` 或有明确的文件访问路由；当前代码不负责把文件复制到其他节点。导出先写同目录 `.part` 文件，再原子发布为 CSV，失败不会产生可下载的不完整 CSV。`ReportExportFileCleanupTask` 每日03:45清理超过 `report.export-retention-hours`（默认24小时）的 `report_*.csv`/`.part` 文件；不能用无条件目录删除处理。

## 本地验收依据

- `BoundedJobExecutorTest`：1运行+16排队后拒绝下一唤醒；拒绝任务不在调用线程执行；重复ID只排一次；停止后拒绝。
- `ReportJobCoordinatorTest`：单店及全局配额；8个并发受理只接受4个同店任务；终态释放配额；过期RUNNING可被接管；旧执行者不能覆盖新结果及文件名；未接管的过期执行者仍可完成。
- `ReportLogServiceTest`：报表/归档原状态与下载令牌、日志窗口/脱敏等回归；停止后创建请求不落库；停机中断查询保留RUNNING供恢复。
- `KdsReplicationContractTest`：OpenAPI解析及既有契约保持有效；两个异步入口补充429/503说明。

## 尚未覆盖的风险

30分钟租约不是SQL取消机制。单个导出聚合语句的超时预算为5秒，92日逐日导出的理论查询预算低于租约；旧SQL可能在接管后继续运行，但旧结果不能覆盖新结果。查询失败按既有语义置FAILED，自动恢复仅针对PENDING/中断RUNNING。

生产MySQL的并发领取、DDL耗时、真实崩溃重启、共享文件存储和峰值负载未在本地H2测试中得到验证，归入T22。

```sql
SELECT job_type,status,COUNT(*) AS jobs,MIN(created_at) AS oldest
FROM t_report_export_job
WHERE job_type IN ('REPORT_EXPORT','ARCHIVE_SEARCH')
GROUP BY job_type,status;

SELECT id,shop_id,job_type,status,lease_until,updated_at
FROM t_report_export_job
WHERE status='RUNNING' AND (lease_until IS NULL OR lease_until<CURRENT_TIMESTAMP)
ORDER BY id LIMIT 32;
```

验收重点：进程退出后PENDING在恢复扫描中再次投递；RUNNING最迟在其租约到期后具备接管资格；并发接管只有一个令牌生效；旧结果不改变新下载令牌；成功任务CSV与已有财务结果一致。监控429比例、最老待办时间和过期RUNNING数量，不以扩大队列代替慢查询治理。

最终本地结果（2026-09-08）：上述4个测试类共41项通过，0失败/错误；mvn -o clean package -DskipTests -q成功。定向回归日志.local/c009-t03-release-tests.log，结果摘要.local/c009-t03-test-summary.txt，打包日志.local/c009-t03-package.log。
