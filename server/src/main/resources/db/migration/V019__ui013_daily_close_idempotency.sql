-- UI013: additive daily-close idempotency metadata.
ALTER TABLE `t_daily_close_snapshot`
  ADD COLUMN `settle_idempotency_key` VARCHAR(64) DEFAULT NULL COMMENT '日结幂等键' AFTER `snapshot_hash`;

CREATE UNIQUE INDEX `uk_daily_close_shop_idempotency`
  ON `t_daily_close_snapshot` (`shop_id`, `settle_idempotency_key`);
