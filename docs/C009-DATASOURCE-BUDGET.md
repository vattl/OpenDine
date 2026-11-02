# C009 / T02 数据库连接预算

当前后端显式创建 Druid 数据源，绑定原有 `spring.datasource` 的 URL、用户名、密码和驱动；额外应用如下预算。仅安装普通 Druid 依赖时，不能依赖 starter 自动绑定这些字段。

```yaml
spring:
  datasource:
    druid:
      max-active: 8
      max-wait: 2000    # 毫秒，只限制获取池连接的等待
      initial-size: 0
      min-idle: 0
```

以上是代码默认值，部署方可以在现有外部配置中覆盖。max-active、max-wait 必须大于 0；initial-size、min-idle 必须在 0 到 max-active 之间，否则启动失败。未变更连接目标和凭据来源。保留空闲连接检查，验证 SQL 为 SELECT 1。

容量规划需满足：应用实例数 × max-active，加上其他客户端和维护连接，低于 MySQL 可分配连接预算。未取得生产容量前，不通过扩大连接数处理饱和。

验收：实际 Spring 数据源实例默认 maxActive=8、maxWait=2000；测试覆盖自定义 maxActive=2、maxWait=80，两连接占满时第三次申请抛出 SQLException，释放后可再次获取；非法预算启动失败。

边界：此配置不限制正在执行的 SQL/锁等待/网络读写时间，不会中断合法事务或自动回收正在使用的连接。取连接超时会使调用方失败，需要结合接口错误率、连接占用时长排查，不能据此宣布数据库故障已经根治。自定义 DataSource bean 或显式切换到其他池时本配置退让，应为替换的池建立独立验收。

发布时先核实实例数、MySQL max_connections、有效池配置、业务超时预算；观察连接等待/超时率和事务耗时。没有进行生产发布或生产压测。T01b 持久化恢复仍为独立发布门槛。
