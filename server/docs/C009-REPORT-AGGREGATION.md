# C009 / T04 报表导出聚合与范围预算

## 实现与验收范围

- 替换 ReportExportService 对所有成功 Order 的实体加载、Java汇总、rows累计；ReportOrderAggregate 只执行参数绑定的 COUNT/SUM，单次返回一行。
- daily 逐营业日查询并立即写CSV；最多92次聚合、92行数据。weekly/monthly整个自然日期区间只查询和输出一行。使用BufferedWriter及try-with-resources；SQL异常时关闭文件，不发放下载token，任务FAILED。
- daily/weekly/monthly入库前统一校验：yyyy-MM-dd（1000至9998年）、结束不早于开始、含首尾最多92天。daily.date优先于startDate，endDate可省略；其他两类起止必填。旧持久化任务执行前也复验，超预算旧任务FAILED，不静默截断。
- 30秒JDBC statement timeout仅用于导出聚合，不调整其他业务查询。连接获取预算仍由T02控制。每日SQL各有30秒预算，整个92日任务并非30秒截止；租约接管仍由T03控制。

## 保持的财务契约

- 成功订单按order_time双闭区间过滤；daily使用既有门店open_time/settle_time/close_time解析，weekly/monthly为自然日00:00:00至23:59:59。
- total=SUM(COALESCE(sett_amount,0)+COALESCE(service_fee,0)-COALESCE(discount_amount,0))；退款独立列，不再次扣除。COUNT(*)包含金额为空的成功订单，空集返回0。
- 源schema金额列均为两位DECIMAL；SQL精确汇总并保持BigDecimal到CSV，输出两位小数。正常金额对照旧double算法；极大累计值以数据库精确十进制结果为准。
- BOM、CSV列序、行序、下载令牌、任务状态/门店范围保持。
- 当前同步 /admin/report 已使用不同的pay_time及净收入工具口径。本项没有把导出改成该口径，也没有治理该Controller其他全量实体查询；它们仍是单独待审计范围，不能宣称整个报表模块已消除OOM风险。

## 本地验证

- ReportLogServiceTest：逆序/超限入队零写入、92日含闰日与date优先级、单次汇总、门店结算窗、历史超限恢复拒绝、第二日失败后首行已写出且文件关闭；原CSV179.00/状态机/token/停机回归。
- ReportOrderAggregateTest：实际H2 SQL验证状态/门店/闭区间边界/NULL/空集/退款独立列；10000笔金额与旧Java算法对照；mock JDBC超时异常时设置30秒预算并关闭statement/connection。
- T03有界执行/配额/恢复和OpenAPI契约一并定向回归。测试命令与最终结果记录于任务进度表。

## 生产验收与边界

无新增DDL或生产操作。先按T03完成任务恢复表迁移。既有迁移定义idx_order_shop_time(shop_id,order_time)，上线前在真实MySQL核实存在并执行：

```sql
EXPLAIN SELECT COUNT(*),
 COALESCE(SUM(COALESCE(sett_amount,0)+COALESCE(service_fee,0)-COALESCE(discount_amount,0)),0)
FROM t_order
WHERE shop_id=1 AND transac_status='success'
 AND order_time>='2025-01-01 00:00:00' AND order_time<='2025-04-02 23:59:59';
```

1. 在隔离压测库对1日/92日及10万/100万订单分别导出，对账CSV金额、门店隔离和起止边界；记录EXPLAIN实际索引、扫描行数、SQL p95、任务完成时间。
2. 对单SQL注入慢查询/网络故障，确认驱动实际取消或失败、连接归还及FAILED/RUNNING恢复状态。单测仅证明设置statement预算，不能证明生产驱动在所有网络故障下30秒硬截止。
3. 对最大任务配额施压，确认工作线程/唤醒队列保持T03上限；JFR/堆直方图不出现随订单数增长的Order列表；比较优化前后堆峰值与GC。仅有本地测试，暂不承诺吞吐提升百分比。
4. 跨实例慢任务超过租约可能重复计算，旧token不能覆盖结果；失败/过期执行产生的文件保留仍归T11。数据库自身扫描成本仍与订单数相关。
