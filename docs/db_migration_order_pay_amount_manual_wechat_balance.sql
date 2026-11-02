-- 按支付方式修正 t_order 渠道金额（历史数据回填，执行前请备份 t_order）。
-- 依赖：已存在 pay_amount_wechat / pay_amount_balance 等列（见 db_migration_order_pay_channel_amounts.sql）。
--
-- 规则说明（与业务确认一致后再执行）：
-- 1）支付方式满足其一则写 pay_amount_wechat：
--    · 整段文案等于「人工收款」：pay_amount_wechat = sett_amount（不减优惠）
--    · 其余下列命中：pay_amount_wechat = sett_amount - discount_amount
--      -「人工结账」
--      -「人工收款和微信支付」
--      - 文案中同时含「人工收款」与「微信」且整段不等于「人工收款」（如「人工收款-微信支付」）
--      -「微信支付」
--    金额口径：不含 service_fee、refund；与当次需求一致。
-- 2）支付方式为「余额支付」：pay_amount_balance = sett_amount（同上不含其它字段）。
--
-- 若库内 payment_method 与上述字面不完全一致，请按需改写 WHERE 条件。

-- ① 人工结账 / 纯人工收款 / 人工收款+微信 / 微信支付 → 微信列
UPDATE `t_order`
SET `pay_amount_wechat` = ROUND(
        CASE
            WHEN NULLIF(TRIM(`payment_method`), '') = '人工收款'
                THEN IFNULL(`sett_amount`, 0)
            ELSE IFNULL(`sett_amount`, 0) - IFNULL(`discount_amount`, 0)
        END,
        2
    )
WHERE `transac_status` = 'success'
  AND (
        NULLIF(TRIM(`payment_method`), '') = '人工结账'
     OR NULLIF(TRIM(`payment_method`), '') = '人工收款'
     OR NULLIF(TRIM(`payment_method`), '') = '人工收款和微信支付'
     OR (
            `payment_method` LIKE '%人工收款%'
        AND `payment_method` LIKE '%微信%'
        )
     OR NULLIF(TRIM(`payment_method`), '') = '微信支付'
    );

-- ② 余额支付 → 余额列（排除名称中含「赠送」的误匹配）
UPDATE `t_order`
SET `pay_amount_balance` = ROUND(IFNULL(`sett_amount`, 0), 2)
WHERE `transac_status` = 'success'
  AND NULLIF(TRIM(`payment_method`), '') = '余额支付'
  AND `payment_method` NOT LIKE '%赠送%';
