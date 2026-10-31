-- =============================================================================
-- 历史邀请关系：补发「首单余额返现」给邀请人（与线上一致逻辑）
-- =============================================================================
-- 兼容：MySQL 5.7 / 8.x（不使用 WITH / ROW_NUMBER，避免旧实例报错 1064）
--
-- 前置条件：
--   1. 已执行 db_migration_invite_first_order_balance_reward.sql（存在 first_order_* 列）
--   2. 执行前请备份 t_invite_record、t_user
--   3. 先执行「二、预览」；确认后再执行「三、正式入账」（建议同一 mysql 会话连续执行 三）
--
-- 规则摘要：
--   - 每个 invitee_openid 只保留一条邀请记录：create_time、id 最小（无更早同行）
--   - 首单：transac_status='success' 且 openid 或 pay_openid 命中被邀请人，且无更早支付成功的订单
--   - 实付(元) = IFNULL(sett_amount,0)+IFNULL(service_fee,0)-IFNULL(discount_amount,0)
--   - 返现整数元 = ROUND(实付 * percent / 100, 0)，percent 来自 t_system_config，缺省 5
--   - first_order_reward_time 已有值的行不处理（幂等）
-- =============================================================================

-- 一、比例（与 InviteFirstOrderRewardConfigKeys 一致；可改成 SET @pct := 5;）
SET @pct := (
    SELECT CAST(IFNULL(NULLIF(TRIM(config_value), ''), '5') AS DECIMAL(10, 4))
    FROM t_system_config
    WHERE config_key = 'invite.reward.first_order.percent'
    LIMIT 1
);
SET @pct := IFNULL(@pct, 5);


-- 二、预览（只读，安全）
SELECT
    ir.id AS invite_record_id,
    ir.inviter_openid,
    ir.invitee_openid,
    o.order_no,
    ROUND(
        IFNULL(o.sett_amount, 0) + IFNULL(o.service_fee, 0) - IFNULL(o.discount_amount, 0),
        2
    ) AS payable_yuan,
    @pct AS percent_used,
    ROUND(
        (IFNULL(o.sett_amount, 0) + IFNULL(o.service_fee, 0) - IFNULL(o.discount_amount, 0)) * @pct / 100,
        0
    ) AS reward_yuan_integer,
    u.id AS inviter_user_id,
    CASE WHEN u.id IS NULL THEN 'NO_USER_SKIP_BALANCE' ELSE 'OK' END AS inviter_check
FROM t_invite_record ir
-- 同一 invitee 仅保留「最早」的一条邀请记录（无更早 create_time/id）
LEFT JOIN t_invite_record ir_earlier
    ON ir.invitee_openid = ir_earlier.invitee_openid
    AND ir_earlier.status = 1
    AND TRIM(IFNULL(ir_earlier.invitee_openid, '')) <> ''
    AND ir_earlier.first_order_reward_time IS NULL
    AND (
        ir_earlier.create_time < ir.create_time
        OR (ir_earlier.create_time = ir.create_time AND ir_earlier.id < ir.id)
    )
INNER JOIN t_order o
    ON o.transac_status = 'success'
    AND (
        TRIM(IFNULL(o.openid, '')) = ir.invitee_openid
        OR TRIM(IFNULL(o.pay_openid, '')) = ir.invitee_openid
    )
-- 该被邀请人名下「最早」一笔成功订单（无更早 pay_time/id）
LEFT JOIN t_order o_earlier
    ON o_earlier.transac_status = 'success'
    AND (
        TRIM(IFNULL(o_earlier.openid, '')) = ir.invitee_openid
        OR TRIM(IFNULL(o_earlier.pay_openid, '')) = ir.invitee_openid
    )
    AND (
        o_earlier.pay_time < o.pay_time
        OR (o_earlier.pay_time = o.pay_time AND o_earlier.id < o.id)
    )
LEFT JOIN t_user u ON u.openid = ir.inviter_openid
WHERE ir.status = 1
  AND TRIM(IFNULL(ir.invitee_openid, '')) <> ''
  AND ir.first_order_reward_time IS NULL
  AND ir_earlier.id IS NULL
  AND o_earlier.id IS NULL
ORDER BY ir.id;


-- =============================================================================
-- 三、正式入账（默认整段注释：请先跑「二」确认无误后，去掉下面 /* */ 再执行整文件或只执行本段）
--    务必：与「一」在同一会话执行（保证 @pct）；若新开连接，请先执行「一」两条 SET。
-- =============================================================================
/*
START TRANSACTION;

DROP TEMPORARY TABLE IF EXISTS tmp_invite_reward_backfill;

CREATE TEMPORARY TABLE tmp_invite_reward_backfill (
    invite_record_id BIGINT NOT NULL,
    inviter_openid VARCHAR(100) NOT NULL,
    order_no VARCHAR(64) NOT NULL,
    payable_yuan DECIMAL(14, 4) NOT NULL,
    reward_yuan DECIMAL(14, 4) NOT NULL
) ENGINE = MEMORY;

INSERT INTO tmp_invite_reward_backfill (
    invite_record_id,
    inviter_openid,
    order_no,
    payable_yuan,
    reward_yuan
)
SELECT
    ir.id,
    ir.inviter_openid,
    o.order_no,
    ROUND(
        IFNULL(o.sett_amount, 0) + IFNULL(o.service_fee, 0) - IFNULL(o.discount_amount, 0),
        4
    ),
    ROUND(
        (IFNULL(o.sett_amount, 0) + IFNULL(o.service_fee, 0) - IFNULL(o.discount_amount, 0)) * @pct / 100,
        0
    )
FROM t_invite_record ir
LEFT JOIN t_invite_record ir_earlier
    ON ir.invitee_openid = ir_earlier.invitee_openid
    AND ir_earlier.status = 1
    AND TRIM(IFNULL(ir_earlier.invitee_openid, '')) <> ''
    AND ir_earlier.first_order_reward_time IS NULL
    AND (
        ir_earlier.create_time < ir.create_time
        OR (ir_earlier.create_time = ir.create_time AND ir_earlier.id < ir.id)
    )
INNER JOIN t_order o
    ON o.transac_status = 'success'
    AND (
        TRIM(IFNULL(o.openid, '')) = ir.invitee_openid
        OR TRIM(IFNULL(o.pay_openid, '')) = ir.invitee_openid
    )
LEFT JOIN t_order o_earlier
    ON o_earlier.transac_status = 'success'
    AND (
        TRIM(IFNULL(o_earlier.openid, '')) = ir.invitee_openid
        OR TRIM(IFNULL(o_earlier.pay_openid, '')) = ir.invitee_openid
    )
    AND (
        o_earlier.pay_time < o.pay_time
        OR (o_earlier.pay_time = o.pay_time AND o_earlier.id < o.id)
    )
WHERE ir.status = 1
  AND TRIM(IFNULL(ir.invitee_openid, '')) <> ''
  AND ir.first_order_reward_time IS NULL
  AND ir_earlier.id IS NULL
  AND o_earlier.id IS NULL;

UPDATE t_user u
INNER JOIN tmp_invite_reward_backfill t
    ON t.inviter_openid = u.openid
    AND t.reward_yuan > 0
SET u.balance = ROUND(IFNULL(u.balance, 0) + t.reward_yuan, 2);

UPDATE t_invite_record ir
INNER JOIN tmp_invite_reward_backfill t ON ir.id = t.invite_record_id
LEFT JOIN t_user u ON u.openid = t.inviter_openid
SET
    ir.first_order_reward_amount = IF(t.reward_yuan > 0, t.reward_yuan, 0),
    ir.first_order_reward_time = NOW(),
    ir.first_order_no = t.order_no
WHERE t.reward_yuan = 0 OR u.id IS NOT NULL;

COMMIT;
*/


-- 四、无成功订单的被邀请人（可选排查；只读）
SELECT
    ir.id,
    ir.invitee_openid
FROM t_invite_record ir
LEFT JOIN t_invite_record ir_earlier
    ON ir.invitee_openid = ir_earlier.invitee_openid
    AND ir_earlier.status = 1
    AND TRIM(IFNULL(ir_earlier.invitee_openid, '')) <> ''
    AND ir_earlier.first_order_reward_time IS NULL
    AND (
        ir_earlier.create_time < ir.create_time
        OR (ir_earlier.create_time = ir.create_time AND ir_earlier.id < ir.id)
    )
WHERE ir.status = 1
  AND TRIM(IFNULL(ir.invitee_openid, '')) <> ''
  AND ir.first_order_reward_time IS NULL
  AND ir_earlier.id IS NULL
  AND NOT EXISTS (
        SELECT 1
        FROM t_order o
        WHERE o.transac_status = 'success'
          AND (
              TRIM(IFNULL(o.openid, '')) = ir.invitee_openid
              OR TRIM(IFNULL(o.pay_openid, '')) = ir.invitee_openid
          )
  );
