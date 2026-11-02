# Acceptance Report — WI-021

Decision: ACCEPTED

## Outcome

Native 微信支付成功关单后，旧 attempt 的活动唯一键会实际写为数据库 NULL，同一业务订单可重新发起下单并获得新的二维码。升级前已经产生的 CLOSED 残留记录也会在下一次 create 时自动修复。

## Evidence

- 5 个场景全部 PASS。
- 专项 10 项通过；全量测试集合分为其余 1295 项与连接池隔离 4 项执行，合计 1299 项覆盖通过。
- API 文档同步到 v1.2.296。
- runnable JAR 构建成功。

## State boundary

仓库级 ACCEPTED；未部署、未用真实微信商户做生产联调。

既有连接池测试在单命令全量运行的 80ms 首次建连窗口存在环境时序抖动，已如实记录于 `TEST_REPORT.md`，与本次 Native 修复无调用关系。
