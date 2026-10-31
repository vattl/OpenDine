# D024 会员画像接口增加 4 个统计字段

* 日期：2026-09-08
* 状态：**IMPLEMENTED（代码）**
* 类型：接口契约扩展
* 关联：D023（列表默认轻量）、D020/D022（聚合口径）

## 0. 需求（用户原话）

> 画像接口增加返回 consume_amount、last_consume_time、invite_registered_count、available_coupon_count。

## 1. 变更

**接口**：`GET /admin/member/profile`（AdminMemberController.profile）

`profile` 顶层新增 4 字段（与 orderCount/totalAmount/avgOrderValue/lastVisit 并列）：

| 字段 | 值 | 口径 |
|---|---|---|
| `consume_amount` | 复用 `totalAmount`（round 2 位） | 实付净额汇总，与列表 `consume_amount` 一致 |
| `last_consume_time` | 复用 `lastVisit` | 最近支付时间（pay_time，回退 order_time），yyyy-MM-dd HH:mm:ss，无记录 null |
| `invite_registered_count` | `InviteRecordMapper.selectCount`：`TRIM(inviter_openid)=openid AND invitee_openid 非空` | 与列表 `invite_registered_count` 一致 |
| `available_coupon_count` | `UserCouponMapper.selectCount`：`user_openid=openid AND status=0 AND (expire_time 为空或未过期) AND coupon_id IN (t_coupon 中 end_time 为空或未过)` | 与列表 `available_coupon_count` 一致 |

- 新增注入 `InviteRecordMapper` / `UserCouponMapper`（MyBatis-Plus BaseMapper.selectCount）
- openapi 同步：description + 响应 schema 4 字段（留工作区）

## 2. 校验

- `mvnw compile` 通过（2 处类型修复：MyBatis-Plus selectCount 返回 Integer）
- 未跑单测（该接口无既有测试）；联调建议：有/无订单、有/无邀请、有/无可用券三态各验一次

## 3. 风险与说明

- 画像接口每次请求新增 2 次轻量 count（t_invite_record / t_user_coupon 单用户等值+索引），开销可忽略；两表可加索引（`idx_inviter_openid`、`idx_user_openid_status` 已在 D020 迁移 SQL 中）进一步提速
- 字段值类型：consume_amount 为 number、计数为 integer、时间为 string|null，与列表接口一致
