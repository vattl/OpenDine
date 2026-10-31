# D004 — t_printing_job 业务溯源字段（KDS 划菜打印可反查）

> 日期：2026-09-05 ｜ 级别：STANDARD（局部行为增强） ｜ 状态：IMPLEMENTED

## 背景

KDS 划菜打印链路：划菜 → `KdsServePrintService`（t_kds_serve_print_job 投递）→ `PrintDispatcherService.dispatch(SERVE/EXPEDITE)` → `t_printing_job` 出票。
审计发现：`t_printing_job` 无业务关联字段（无 order_id / detail_id），无法从打印记录反查对应划菜明细，两表无法串联审计。

## Current → Target → Diff

| 元素 | 操作 | 说明 |
|---|---|---|
| `t_printing_job` | MODIFY | 新增 `biz_type varchar(20)`（业务类型：kds_serve）+ `biz_id bigint`（业务主键：t_order_detail.id）+ 索引 `idx_printing_job_biz(biz_type, biz_id)`；迁移脚本 `docs/db_migration_printing_job_biz_trace.sql`（守护式加列，幂等） |
| `PrintingJob.java` | MODIFY | 实体增加 `biz_type` / `biz_id` 字段 |
| `PrintContext.ofServe` | MODIFY | 构造 KDS 划菜上下文时向 `extra` 写入 `bizType=kds_serve`、`bizId=detail_id`、`orderId=order_id`（自动 + 手动补打两路径共用） |
| `PrintDispatcherServiceImpl.executeAndRecordJob` | MODIFY | 签名增加 `PrintContext context`；落库前从 `extra` 读取 `bizType/bizId` 写入 job；其他场景未携带时为 NULL，向后兼容 |
| `PrintingService.jobSummary` | MODIFY | `GET /admin/printing/jobs` 每项在非空时输出 `bizType` / `bizId` |

## 不变项（UNCHANGED）

- 划菜投递队列 `t_kds_serve_print_job` 结构、KDS 幂等与重试逻辑不变；
- 调度中心规则匹配、模板渲染、CLOUD/DEVICE 执行路径不变；
- 其他打印场景（厨单/结账/退款等）未携带 biz 字段，行为不变；
- 公开接口路径/方法无增删，仅 `GET /admin/printing/jobs` 响应项新增可选字段。

## 验证

- [x] 6 处代码改动回读确认
- [x] `mvn` 编译/测试通过（见构建记录）
- [x] openapi.yaml changelog v1.2.218 + jobs 响应说明同步

## 完成后可用查询

```sql
-- 按划菜明细反查全部出票记录（设备/内容/状态/补打次数）
SELECT j.id, j.device_id, j.job_type, j.status, j.executor, j.biz_type, j.biz_id,
       j.retry_count, j.error, j.created_at
FROM t_printing_job j
WHERE j.biz_type = 'kds_serve' AND j.biz_id = ?;   -- ? = t_order_detail.id
```
