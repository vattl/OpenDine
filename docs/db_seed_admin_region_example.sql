/*
  P3 示例初始化数据（按需修改后执行）
  依赖：已执行 docs/db_migration_admin_region.sql
*/

SET NAMES utf8mb4;

-- 1) 区域
INSERT INTO t_region (code, name, parent_id) VALUES
('ZJ', '浙江大区', NULL),
('HZ', '杭州区域', NULL),
('NB', '宁波区域', NULL)
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- 2) 门店归属区域（按 code 绑定，避免硬编码 id）
UPDATE t_shop s
JOIN t_region r ON r.code = 'HZ'
SET s.region_id = r.id
WHERE s.code IN ('SH001', 'SH002');

UPDATE t_shop s
JOIN t_region r ON r.code = 'NB'
SET s.region_id = r.id
WHERE s.code IN ('SH003');

-- 3) 管理员绑定区域（示例：admin_id=2 为杭州区域经理）
INSERT INTO t_admin_region (admin_id, region_id)
SELECT 2, id FROM t_region WHERE code = 'HZ'
ON DUPLICATE KEY UPDATE region_id = VALUES(region_id);

-- 4) 可选：再叠加门店绑定，形成“区域∩门店”限制（示例：admin_id=2 仅可管 SH001）
INSERT INTO t_admin_shop (admin_id, shop_id)
SELECT 2, id FROM t_shop WHERE code = 'SH001'
ON DUPLICATE KEY UPDATE shop_id = VALUES(shop_id);
