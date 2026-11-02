-- ==============================================================================
-- 历史用户与数据全量归属总店 (shop_id = 1) 统一数据清洗脚本
-- 执行目标：
--   1. 将历史未分配门店的订单 (t_order) 归为总店 (shop_id = 1)，使历史消费用户在总店收银端可查
--   2. 将历史充值流水 (t_member_recharge) 统一归属总店 (shop_id = 1)
--   3. 为历史会员初始化总店会员分店钱包 (t_shop_member_wallet)，使单店余额与总店对齐
--   4. 为历史用户初始化最近访问/归属门店 (t_user_last_shop) 为总店 (shop_id = 1)
-- ==============================================================================

SET NAMES utf8mb4;

-- ------------------------------------------------------------------------------
-- 0. 前置验证：确保总店 (shop_id = 1) 记录存在
-- ------------------------------------------------------------------------------
INSERT INTO `t_shop` (`id`, `name`, `code`, `status`, `sort_order`, `remark`)
VALUES (1, '总店', 'MAIN_001', 1, 1, '系统默认总店')
ON DUPLICATE KEY UPDATE `status` = VALUES(`status`);

-- ------------------------------------------------------------------------------
-- 1. 历史订单清洗：将未标记门店或无效门店的订单统一划归总店 (shop_id = 1)
--    解决场景：收银端带 storeOnly=true 查询时，因历史订单缺少 shop_id 查不到老用户
-- ------------------------------------------------------------------------------
UPDATE `t_order`
SET `shop_id` = 1
WHERE `shop_id` IS NULL OR `shop_id` <= 0;

-- ------------------------------------------------------------------------------
-- 2. 历史充值流水清洗：将未标记门店的充值记录划归总店 (shop_id = 1)
--    解决场景：保障历史充值资金全部明确归属于总店账务
-- ------------------------------------------------------------------------------
UPDATE `t_member_recharge`
SET `shop_id` = 1
WHERE `shop_id` IS NULL OR `shop_id` <= 0;

-- ------------------------------------------------------------------------------
-- 3. 门店会员分店钱包初始化 (t_shop_member_wallet)
--    确保表结构存在（若未执行 V025 则自动建表）
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `t_shop_member_wallet` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `user_id` INT NOT NULL COMMENT '用户ID',
    `shop_id` INT NOT NULL COMMENT '归属门店ID',
    `principal_balance` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '门店本金余额',
    `gift_balance` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '门店赠送余额',
    `total_recharge_principal` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '累计充值本金',
    `total_recharge_gift` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '累计赠送金额',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_user_shop` (`user_id`, `shop_id`),
    KEY `idx_shop_id` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店会员钱包分账表';

-- 3.1 历史会员总店钱包初始化：
--     对于尚未在 t_shop_member_wallet 建立总店钱包的用户，将 t_user 余额与历史充值初始化归入总店钱包
INSERT INTO `t_shop_member_wallet` (
    `user_id`,
    `shop_id`,
    `principal_balance`,
    `gift_balance`,
    `total_recharge_principal`,
    `total_recharge_gift`,
    `created_at`,
    `updated_at`
)
SELECT 
    u.id AS user_id,
    1 AS shop_id,
    IFNULL(u.principal_balance, 0.00) AS principal_balance,
    IFNULL(u.gift_balance, 0.00) AS gift_balance,
    IFNULL(r.tot_recharge_principal, IFNULL(u.principal_balance, 0.00)) AS total_recharge_principal,
    IFNULL(r.tot_recharge_gift, IFNULL(u.gift_balance, 0.00)) AS total_recharge_gift,
    IFNULL(u.time, NOW()) AS created_at,
    NOW() AS updated_at
FROM `t_user` u
LEFT JOIN (
    SELECT 
        user_id,
        SUM(recharge_amount) AS tot_recharge_principal,
        SUM(gift_amount) AS tot_recharge_gift
    FROM `t_member_recharge`
    WHERE `status` = 'success'
    GROUP BY user_id
) r ON r.user_id = u.id
WHERE NOT EXISTS (
    SELECT 1 FROM `t_shop_member_wallet` w 
    WHERE w.user_id = u.id AND w.shop_id = 1
);

-- 3.2 历史已有总店钱包余额同步（针对建表后总店钱包余额为0但用户总余额大于0的历史记录）
UPDATE `t_shop_member_wallet` w
JOIN `t_user` u ON w.user_id = u.id
SET w.principal_balance = IFNULL(u.principal_balance, 0.00),
    w.gift_balance = IFNULL(u.gift_balance, 0.00),
    w.updated_at = NOW()
WHERE w.shop_id = 1
  AND w.principal_balance = 0.00
  AND w.gift_balance = 0.00
  AND (IFNULL(u.principal_balance, 0.00) > 0 OR IFNULL(u.gift_balance, 0.00) > 0)
  AND NOT EXISTS (
      -- 确保该用户在其他分店没有独立余额，避免多扣或重复赋值
      SELECT 1 FROM (
          SELECT user_id, SUM(principal_balance + gift_balance) AS other_bal
          FROM `t_shop_member_wallet`
          WHERE shop_id <> 1
          GROUP BY user_id
      ) o WHERE o.user_id = u.id AND o.other_bal > 0
  );

-- ------------------------------------------------------------------------------
-- 4. 历史用户最近访问门店初始化 (t_user_last_shop)
--    确保所有 openid 在常访门店表中默认关联总店 (shop_id = 1)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `t_user_last_shop` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `openid` VARCHAR(100) NOT NULL COMMENT 't_user.openid',
    `shop_id` INT NOT NULL COMMENT '门店ID',
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_openid` (`openid`),
    KEY `idx_shop_id` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户最后访问门店记录';

INSERT INTO `t_user_last_shop` (`openid`, `shop_id`, `updated_at`)
SELECT u.openid, 1, NOW()
FROM `t_user` u
WHERE u.openid IS NOT NULL AND TRIM(u.openid) <> ''
ON DUPLICATE KEY UPDATE `shop_id` = IFNULL(`shop_id`, 1);

-- ==============================================================================
-- 5. 数据校验对账 SQL（执行后用于核验数据一致性）
-- ==============================================================================
-- 5.1 核对是否还有未归属门店的历史订单 (期望结果: 0)
SELECT COUNT(*) AS unassigned_order_count 
FROM `t_order` 
WHERE `shop_id` IS NULL OR `shop_id` <= 0;

-- 5.2 核对是否还有未归属门店的历史充值流水 (期望结果: 0)
SELECT COUNT(*) AS unassigned_recharge_count 
FROM `t_member_recharge` 
WHERE `shop_id` IS NULL OR `shop_id` <= 0;

-- 5.3 核验总店钱包总余额与用户表总余额差额 (无跨店充值时两表总额应一致)
SELECT 
    (SELECT IFNULL(SUM(balance), 0) FROM `t_user`) AS user_table_total_balance,
    (SELECT IFNULL(SUM(principal_balance + gift_balance), 0) FROM `t_shop_member_wallet` WHERE `shop_id` = 1) AS main_shop_wallet_balance;
