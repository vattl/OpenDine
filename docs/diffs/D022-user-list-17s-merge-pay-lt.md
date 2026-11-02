# D022 getUserInfo 17s 诊断与 t_order 聚合合并优化

* 日期：2026-09-08
* 状态：**IMPLEMENTED（代码）**；索引依赖目标库执行
* 类型：性能优化（SQL 结构）
* 关联：D020（预聚合 JOIN + 索引迁移）

## 0. 现象

`POST /admin/order/getUserInfo`（用户列表）耗时 **17s**。

## 1. 根因（按贡献排序）

接口主查询 = `t_user` LEFT JOIN **4 个预聚合子查询**：

| 子查询 | 扫描对象 | 每次请求成本 |
|---|---|---|
| `pay`（消费金额） | t_order 全量 success × 2 分支（openid + pay_openid，UNION ALL） | 全表/全店扫描 + GROUP BY 临时表 |
| `lt`（最近消费时间） | **与 pay 完全同构**，t_order 再扫 2 遍 | 同上（重复劳动） |
| `inv`（邀请注册数） | t_invite_record 全量 | 无索引时全表扫 + filesort |
| `cp`（可用券数） | t_user_coupon JOIN t_coupon 全量 | 无索引时全表扫 + 临时表 |

**17s 来源**：
1. **t_order 每页被全表扫 4 遍**（pay×2 + lt×2），且 `pay`/`lt` 逻辑完全同构——纯重复扫描。t_order 大时 4 遍扫描 + 临时表 GROUP BY 占大头（10s+）
2. **4 个子查询都是"全量聚合再 JOIN"**：无论查第几页、带不带过滤，都先聚合整张表。D020 已把"每行相关子查询（3N 次全表扫）"降为"4 次全表扫"，但**没有消除全表计算**（LIMIT/WHERE 只作用于外层）
3. **索引缺失**：`idx_order_status_openid_time` / `idx_order_status_payopenid_time` / `idx_inviter_openid` / `idx_user_openid_status`（D020 迁移 SQL）**若未在目标库执行**，上述全表扫全部退化为全表 + 临时表排序
4. `GROUP BY TRIM(列)` 强制临时表 + filesort（openid 可能带空格，无法避免）

## 2. 本次改动（代码，已提交）

**合并 `pay` + `lt` 为单次 t_order 聚合**（`UserMapper.xml`）：

- `userStatsFrom` 的 `pay` 子查询同时产出 `SUM(amt) AS consume_amount` + `MAX(pay_time) AS last_consume_time`（内层 SELECT 每行带 `o.pay_time`）
- 删除独立的 `lt` LEFT JOIN 块；主查询 `lt.last_consume_time` → `pay.last_consume_time`
- `countUserListWithStats` 自动受益

**效果**：t_order 扫描 **4 遍 → 2 遍**，GROUP BY 临时表减半；逻辑与原 SQL 完全等价（两个子查询 WHERE 完全一致）。

## 3. 仍需目标库执行（决定最终耗时）

**`docs/db_migration_user_list_perf.sql`**（D020，幂等）：
- `t_order` 加 `idx_order_status_openid_time(transac_status, openid, pay_time)`、`idx_order_status_payopenid_time(transac_status, pay_openid, pay_time)` —— 两个 UNION 分支变覆盖索引范围扫描
- `t_invite_record` 加 `idx_inviter_openid`
- `t_user_coupon` 加 `idx_user_openid_status(user_openid, status)`

> 若索引未建，17s 与"4 遍全表扫 + 无索引聚合"完全吻合；建齐后预计降到 **几百 ms~1s**。

执行：`mysql -u<user> -p db_diancan < db_migration_user_list_perf.sql`，用 `SHOW INDEX` 校验。

## 4. 远期建议（可选，用户量大后再做）

每日物化 `t_user_stats`（openid → consume_amount / last_consume_time / invite_count / coupon_count），接口 JOIN 物化表，彻底脱离每页全量聚合。适合 t_order 百万级后。

## 5. 校验

- XML well-formed 校验通过；`mvnw compile` 通过（MyBatis XML 启动期解析，需联调时以真实请求验证）
- 本机 MySQL 无密码不可连，未做 EXPLAIN；验证缺口：目标库 EXPLAIN 确认走新索引
