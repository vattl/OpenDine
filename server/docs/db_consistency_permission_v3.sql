-- ============================================================
-- 权限一致性重建 v3：权限码字典 + 接口映射 + 五大角色授权全量对齐
-- 目标：t_api_permission 使用的每个权限码都存在于 t_permission，
--       且每个权限码至少被一个内置角色授予（boss 全量兜底）。
-- 幂等：可重复执行。执行前请备份 t_role_permission / t_permission。
-- 关键修复：收银员(cashier) 补授 order:operate:refund（此前缺失导致退款 403）
-- ============================================================

-- 1. 权限码字典补齐（INSERT IGNORE，已存在自动跳过）
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('access:manage', 'access:manage', 'access', '权限一致性重建 v3', 1),
('access:view', 'access:view', 'access', '权限一致性重建 v3', 2),
('admin:config', 'admin:config', 'admin', '权限一致性重建 v3', 3),
('admin:log', 'admin:log', 'admin', '权限一致性重建 v3', 4),
('admin:manage', 'admin:manage', 'admin', '权限一致性重建 v3', 5),
('admin:password', 'admin:password', 'admin', '权限一致性重建 v3', 6),
('admin:super', 'admin:super', 'admin', '仅 super_admin 角色的高权限能力', 7),
('announcement:manage', 'announcement:manage', 'announcement', '权限一致性重建 v3', 7),
('announcement:view', 'announcement:view', 'announcement', '权限一致性重建 v3', 8),
('banner:manage', 'banner:manage', 'banner', '权限一致性重建 v3', 9),
('cashier:operate', 'cashier:operate', 'cashier', '权限一致性重建 v3', 10),
('cashier:shift', 'cashier:shift', 'cashier', '权限一致性重建 v3', 11),
('coupon:manage', 'coupon:manage', 'coupon', '权限一致性重建 v3', 12),
('daily:settle', 'daily:settle', 'daily', '权限一致性重建 v3', 13),
('dish:manage', 'dish:manage', 'dish', '权限一致性重建 v3', 14),
('dish:manage:category', 'dish:manage:category', 'dish', '权限一致性重建 v3', 15),
('dish:manage:dish', 'dish:manage:dish', 'dish', '权限一致性重建 v3', 16),
('dish:manage:unit', 'dish:manage:unit', 'dish', '权限一致性重建 v3', 17),
('inventory:manage', 'inventory:manage', 'inventory', '权限一致性重建 v3', 18),
('inventory:view', 'inventory:view', 'inventory', '权限一致性重建 v3', 19),
('kds:config', 'kds:config', 'kds', '权限一致性重建 v3', 20),
('kds:operate', 'kds:operate', 'kds', '权限一致性重建 v3', 21),
('kds:view', 'kds:view', 'kds', '权限一致性重建 v3', 22),
('log:archive', 'log:archive', 'log', '权限一致性重建 v3', 23),
('log:export', 'log:export', 'log', '权限一致性重建 v3', 24),
('log:view', 'log:view', 'log', '权限一致性重建 v3', 25),
('marketing:firstorder:manage', 'marketing:firstorder:manage', 'marketing', '权限一致性重建 v3', 26),
('marketing:firstorder:view', 'marketing:firstorder:view', 'marketing', '权限一致性重建 v3', 27),
('material:manage', 'material:manage', 'material', '权限一致性重建 v3', 28),
('notifications:manage', 'notifications:manage', 'notifications', '权限一致性重建 v3', 29),
('notifications:view', 'notifications:view', 'notifications', '权限一致性重建 v3', 30),
('order:config', 'order:config', 'order', '权限一致性重建 v3', 31),
('order:config:autoAccept', 'order:config:autoAccept', 'order', '权限一致性重建 v3', 32),
('order:config:dailySettle', 'order:config:dailySettle', 'order', '权限一致性重建 v3', 33),
('order:config:paymentMethod', 'order:config:paymentMethod', 'order', '权限一致性重建 v3', 34),
('order:config:shop', 'order:config:shop', 'order', '权限一致性重建 v3', 35),
('order:operate', 'order:operate', 'order', '权限一致性重建 v3', 36),
('order:operate:accept', 'order:operate:accept', 'order', '权限一致性重建 v3', 37),
('order:operate:addDish', 'order:operate:addDish', 'order', '权限一致性重建 v3', 38),
('order:operate:changePrice', 'order:operate:changePrice', 'order', '权限一致性重建 v3', 39),
('order:operate:checkout', 'order:operate:checkout', 'order', '权限一致性重建 v3', 40),
('order:operate:deleteDish', 'order:operate:deleteDish', 'order', '权限一致性重建 v3', 41),
('order:operate:discount', 'order:operate:discount', 'order', '权限一致性重建 v3', 42),
('order:operate:hang', 'order:operate:hang', 'order', '权限一致性重建 v3', 43),
('order:operate:refund', 'order:operate:refund', 'order', '权限一致性重建 v3', 44),
('order:operate:unCheckout', 'order:operate:unCheckout', 'order', '权限一致性重建 v3', 45),
('order:view', 'order:view', 'order', '权限一致性重建 v3', 46),
('order:view:detail', 'order:view:detail', 'order', '权限一致性重建 v3', 47),
('order:view:list', 'order:view:list', 'order', '权限一致性重建 v3', 48),
('order:view:log', 'order:view:log', 'order', '权限一致性重建 v3', 49),
('payment:config', 'payment:config', 'payment', '权限一致性重建 v3', 50),
('payment:config:read', 'payment:config:read', 'payment', '权限一致性重建 v3', 51),
('payment:config:write', 'payment:config:write', 'payment', '权限一致性重建 v3', 52),
('payment:manage', 'payment:manage', 'payment', '权限一致性重建 v3', 53),
('payment:view', 'payment:view', 'payment', '权限一致性重建 v3', 54),
('printing:manage', 'printing:manage', 'printing', '权限一致性重建 v3', 55),
('printing:view', 'printing:view', 'printing', '权限一致性重建 v3', 56),
('public', 'public', 'public', '权限一致性重建 v3', 57),
('report:export', 'report:export', 'report', '权限一致性重建 v3', 58),
('report:view', 'report:view', 'report', '权限一致性重建 v3', 59),
('settings:manage', 'settings:manage', 'settings', '权限一致性重建 v3', 60),
('settings:view', 'settings:view', 'settings', '权限一致性重建 v3', 61),
('shop:manage', 'shop:manage', 'shop', '权限一致性重建 v3', 62),
('statistics:view', 'statistics:view', 'statistics', '权限一致性重建 v3', 63),
('statistics:view:cashierPerformance', 'statistics:view:cashierPerformance', 'statistics', '权限一致性重建 v3', 64),
('statistics:view:dashboard', 'statistics:view:dashboard', 'statistics', '权限一致性重建 v3', 65),
('statistics:view:dishRanking', 'statistics:view:dishRanking', 'statistics', '权限一致性重建 v3', 66),
('statistics:view:inventory', 'statistics:view:inventory', 'statistics', '权限一致性重建 v3', 67),
('statistics:view:profit', 'statistics:view:profit', 'statistics', '权限一致性重建 v3', 68),
('statistics:view:recharge', 'statistics:view:recharge', 'statistics', '权限一致性重建 v3', 69),
('statistics:view:report', 'statistics:view:report', 'statistics', '权限一致性重建 v3', 70),
('statistics:view:sales', 'statistics:view:sales', 'statistics', '权限一致性重建 v3', 71),
('table:manage', 'table:manage', 'table', '权限一致性重建 v3', 72),
('table:operate', 'table:operate', 'table', '权限一致性重建 v3', 73),
('table:operate:clear', 'table:operate:clear', 'table', '权限一致性重建 v3', 74),
('table:operate:merge', 'table:operate:merge', 'table', '权限一致性重建 v3', 75),
('table:operate:open', 'table:operate:open', 'table', '权限一致性重建 v3', 76),
('table:operate:transfer', 'table:operate:transfer', 'table', '权限一致性重建 v3', 77),
('user:operate', 'user:operate', 'user', '权限一致性重建 v3', 78),
('user:operate:points', 'user:operate:points', 'user', '权限一致性重建 v3', 79),
('user:operate:recharge', 'user:operate:recharge', 'user', '权限一致性重建 v3', 80),
('user:points', 'user:points', 'user', '权限一致性重建 v3', 81),
('user:view', 'user:view', 'user', '权限一致性重建 v3', 82);

-- 2. 重建五大角色授权（先清旧关联，幂等）
DELETE rp FROM t_role_permission rp
INNER JOIN t_role r ON rp.role_id = r.id
WHERE r.role_code IN ('boss','store_manager','waiter','head_chef','cashier');

-- 老板：授予全部权限
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'boss' AND p.permission_code != 'admin:super';

-- 店长：除 admin:manage 外的全部权限
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'store_manager' AND p.permission_code NOT IN ('admin:manage', 'admin:super');

-- 超级管理员专属权限：不得随“全部权限”规则下放给 boss/store_manager。
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'super_admin' AND p.permission_code = 'admin:super';

-- waiter
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'waiter' AND p.permission_code IN (
    'admin:password',
    'order:view',
    'order:view:list',
    'order:view:detail',
    'order:view:log',
    'order:operate',
    'order:operate:accept',
    'order:operate:addDish',
    'order:operate:deleteDish',
    'table:manage',
    'table:operate',
    'table:operate:open',
    'table:operate:merge',
    'table:operate:transfer',
    'table:operate:clear',
    'kds:view',
    'kds:operate',
    'public');

-- head_chef
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'head_chef' AND p.permission_code IN (
    'admin:password',
    'order:view',
    'order:view:list',
    'order:view:detail',
    'order:view:log',
    'dish:manage',
    'dish:manage:category',
    'dish:manage:dish',
    'dish:manage:unit',
    'kds:view',
    'kds:operate',
    'kds:config',
    'material:manage',
    'inventory:manage',
    'public');

-- cashier
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'cashier' AND p.permission_code IN (
    'admin:password',
    'order:view',
    'order:view:list',
    'order:view:detail',
    'order:view:log',
    'order:operate',
    'order:operate:checkout',
    'order:operate:hang',
    'order:operate:addDish',
    'order:operate:deleteDish',
    'order:operate:refund',
    'order:config',
    'table:manage',
    'table:operate',
    'table:operate:open',
    'table:operate:merge',
    'table:operate:transfer',
    'user:view',
    'user:operate',
    'user:operate:recharge',
    'statistics:view',
    'statistics:view:cashierPerformance',
    'cashier:shift',
    'cashier:operate',
    'kds:view',
    'kds:operate',
    'public');

-- ============================================================
-- 5. 校验（执行后应满足：缺口=0、未授权接口码=0）
-- ============================================================

-- 5.1 接口映射用了但字典没有的权限码（应为空）
SELECT DISTINCT a.permission_code FROM t_api_permission a
LEFT JOIN t_permission p ON a.permission_code = p.permission_code
WHERE p.id IS NULL;

-- 5.2 内置角色未覆盖的接口权限码（应为空；boss 全量保证）
SELECT DISTINCT a.permission_code FROM t_api_permission a
LEFT JOIN t_role_permission rp ON rp.permission_id = (SELECT id FROM t_permission WHERE permission_code = a.permission_code)
LEFT JOIN t_role r ON rp.role_id = r.id AND r.role_code = 'boss'
WHERE r.id IS NULL;

-- 5.3 五大角色授权统计（应各角色均有记录）
SELECT r.role_code, COUNT(rp.id) AS grant_cnt FROM t_role r
LEFT JOIN t_role_permission rp ON rp.role_id = r.id
WHERE r.role_code IN ('boss','store_manager','waiter','head_chef','cashier')
GROUP BY r.role_code;
