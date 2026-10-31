# D020 用户列表接口性能优化（分页假象消除）

* 日期：2026-09-08
* 状态：**IMPLEMENTED（索引迁移待目标库执行）**
* 类型：性能优化（SQL 重写 + 索引）
* 关联：`POST /admin/order/getUserInfo`（`pageUserListWithStats` / `countUserListWithStats`）

## 0. 问题（审计结论）

分页 `LIMIT offset, pageSize` 真实生效（默认 20/上限 100），但**计算成本与页码无关**：

1. pay 聚合子查询：`WHERE transac_status='success'` 无前缀索引 → 全表扫描 t_order（UNION ALL 两分支），每次请求重算；
2. 三个相关子查询（last_consume_time / invite_registered_count / available_coupon_count）：**每行用户各全表扫一次** t_order / t_invite_record / t_user_coupon（TRIM(列) 致索引失效、t_invite_record 无 inviter_openid 索引、t_user_coupon 无 user_openid 索引）；
3. count 与列表同量级全表聚合。

成本 ≈ `2×全表扫 t_order + pageSize×(全表扫 t_order + t_invite_record + t_user_coupon)`，与页码无关。

## 1. 方案 A（索引，幂等迁移）

`docs/db_migration_user_list_perf.sql`：

| 表 | 索引 | 用途 |
|---|---|---|
| t_order | `idx_order_status_openid_time (transac_status, openid, pay_time)` | success 过滤 + openid 分组 + MAX(pay_time) 覆盖 |
| t_order | `idx_order_status_payopenid_time (transac_status, pay_openid, pay_time)` | pay_openid 分支 |
| t_invite_record | `idx_inviter_openid (inviter_openid)` | 邀请注册数分组 |
| t_user_coupon | `idx_user_openid_status (user_openid, status)` | 可用券数过滤+分组 |

> 迁移用 `information_schema.statistics` 判断 + PREPARE 执行，已存在自动跳过（幂等）。

## 2. 方案 B（SQL 重写，UserMapper.xml 已落地）

`pageUserListWithStats`：三个相关子查询 → 三个预聚合 `LEFT JOIN`（lt / inv / cp），每行不再触发子查询：

- `lt`：t_order success 订单 openid∪pay_openid UNION ALL 预聚合 `MAX(pay_time)`（含 shop 过滤，口径同原相关子查询）
- `inv`：t_invite_record 按 `TRIM(inviter_openid)` 预聚合 `COUNT(1)`（invitee_openid 非空）
- `cp`：t_user_coupon 按 `user_openid` 预聚合可用券 `COUNT(1)`（status=0、未过期、模板存在且未结束）

TRIM 保留在**等号右侧/分组输出口径**（`lt.user_openid = TRIM(u.openid)`），WHERE 关键列不再被 TRIM 包裹，索引可用。`countUserListWithStats` 不变（WHERE 仅引用 u.* / pay，不依赖 lt/inv/cp）。

## 3. 验证

- UserMapper.xml XML well-formed 校验通过（`[xml]` 解析 OK）
- 编译通过
- **未做运行验证**：本机 MySQL `Access denied`（`DB_PASSWORD` 环境变量为空，无法连 127.0.0.1:3306/db_diancan）→ 无法 EXPLAIN/实测。**迁移 SQL 需在目标库（本机或生产部署）执行后**，建议 `EXPLAIN SELECT ...` 复核：pay/lt 分支应走 `idx_order_status_openid_time`/`idx_order_status_payopenid_time`，inv 走 `idx_inviter_openid`，cp 走 `idx_user_openid_status`。

## 4. 后续可选

- 方案 C：`t_user` 落库维护 `consume_amount/last_consume_time` 聚合字段，列表零 JOIN（改动大，涉及写路径）
- 若用户量继续增长：pay 聚合可改为按门店/时间分区物化或缓存
