-- Cloud is the safe default for every new or previously unconfigured shop.
-- Explicit legacy rows are intentionally preserved: they require an operated
-- cutover after their replication queues and dead letters are reconciled.
ALTER TABLE t_kds_shop_authority
  MODIFY COLUMN authority_mode VARCHAR(16) NOT NULL DEFAULT 'cloud';

INSERT INTO t_kds_shop_authority (shop_id, authority_mode, protocol_version)
SELECT shop.id, 'cloud', 2
FROM t_shop shop
LEFT JOIN t_kds_shop_authority authority ON authority.shop_id = shop.id
WHERE authority.shop_id IS NULL;
