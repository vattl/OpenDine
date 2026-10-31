-- ============================================================
-- B端权限模块重构迁移脚本
-- 五大角色：老板/店长/服务员/厨师长/收银员
-- 细粒度权限码体系
-- 执行前请备份 t_role / t_permission / t_role_permission / t_api_permission
-- ============================================================

-- -----------------------------------------------------------
-- -----------------------------------------------------------
-- 0. 确保唯一索引存在（幂等）
-- -----------------------------------------------------------
SET @exist = (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_permission' AND index_name='uk_permission_code');
SET @sql = IF(@exist=0, 'ALTER TABLE t_permission ADD UNIQUE KEY uk_permission_code (permission_code)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exist = (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='t_role' AND index_name='uk_role_code');
SET @sql = IF(@exist=0, 'ALTER TABLE t_role ADD UNIQUE KEY uk_role_code (role_code)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 1. 细粒度权限码（插入 t_permission，已存在则跳过）
-- -----------------------------------------------------------

-- 系统管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('admin:password',          '修改密码',       '系统', '修改自己的登录密码', 1),
('admin:manage',            '管理员与角色管理', '系统', '管理员增删改、角色配置、RBAC', 2),
('admin:config',            '系统配置',       '系统', '飞鹅云、邀请海报等系统级配置', 3),
('admin:log',               '操作日志',       '系统', '查看操作审计日志', 4);

-- 订单管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('order:view',              '订单查看',       '订单', '订单列表/详情/日志（父权限）', 10),
('order:view:list',         '订单列表',       '订单', '查看订单列表', 11),
('order:view:detail',       '订单详情',       '订单', '查看订单详情', 12),
('order:view:log',          '订单日志',       '订单', '查看订单操作日志', 13),
('order:operate',           '订单操作',       '订单', '订单所有操作（父权限）', 20),
('order:operate:accept',    '接单',           '订单', '接单/拒单', 21),
('order:operate:checkout',  '结账',           '订单', '订单结账', 22),
('order:operate:refund',    '退款',           '订单', '微信退款/退菜', 23),
('order:operate:addDish',   '加菜',           '订单', '加菜/改数量', 24),
('order:operate:deleteDish','删菜',           '订单', '删除菜品明细', 25),
('order:operate:changePrice','改价',          '订单', '修改菜品价格', 26),
('order:operate:discount',  '折扣/优惠',      '订单', '订单折扣、优惠减免', 27),
('order:operate:hang',      '挂单',           '订单', '挂起订单', 28),
('order:operate:unCheckout','反结账',         '订单', '取消结账', 29),
('order:config',            '订单配置',       '订单', '订单相关配置（父权限）', 30),
('order:config:autoAccept', '自动接单配置',   '订单', '开关自动接单', 31),
('order:config:paymentMethod','支付方式配置', '订单', '支付方式管理', 32),
('order:config:dailySettle','日结',           '订单', '日结操作与查询', 33),
('order:config:shop',       '门店配置',       '订单', '门店信息管理', 34);

-- 菜品管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('dish:manage',             '菜品管理',       '菜品', '菜品/分类/单位（父权限）', 40),
('dish:manage:category',    '分类管理',       '菜品', '菜品分类增删改排序', 41),
('dish:manage:dish',        '菜品管理',       '菜品', '菜品增删改、上下架、排序', 42),
('dish:manage:unit',        '单位管理',       '菜品', '菜品单位管理', 43);

-- 桌台管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('table:manage',            '桌台管理',       '桌台', '桌台增删改（父权限）', 50),
('table:operate',           '桌台操作',       '桌台', '开台/并台/转台/清台（父权限）', 51),
('table:operate:open',      '开台',           '桌台', '开台', 52),
('table:operate:merge',     '并台',           '桌台', '合并桌台', 53),
('table:operate:transfer',  '转台',           '桌台', '转移桌台', 54),
('table:operate:clear',     '清台',           '桌台', '清理桌台', 55);

-- 营销管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('banner:manage',           '轮播图管理',     '营销', '首页轮播图增删改', 60),
('announcement:manage',     '门店公告管理',   '营销', '门店公告增删改', 61),
('coupon:manage',           '优惠券管理',     '营销', '优惠券模板与发放', 62);

-- 统计报表
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('statistics:view',         '报表查看',       '报表', '所有报表（父权限）', 70),
('statistics:view:sales',   '营业额',         '报表', '营业额/销售趋势', 71),
('statistics:view:dashboard','经营仪表盘',    '报表', '经营数据总览', 72),
('statistics:view:report',  '周期报表',       '报表', '日报/周报/月报', 73),
('statistics:view:dishRanking','菜品排行',    '报表', '菜品销量排行', 74),
('statistics:view:cashierPerformance','收银员业绩','报表','收银员个人业绩', 75),
('statistics:view:profit',  '利润分析',       '报表', '毛利/利润分析', 76),
('statistics:view:inventory','库存报表',      '报表', '物料库存报表', 77),
('statistics:view:recharge','充值报表',       '报表', '会员充值记录', 78);

-- 会员管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('user:view',               '会员查看',       '会员', '会员信息查询（父权限）', 80),
('user:operate',            '会员操作',       '会员', '会员所有操作（父权限）', 81),
('user:operate:recharge',   '会员充值',       '会员', '会员余额充值', 82),
('user:operate:points',     '积分操作',       '会员', '手动加减积分', 83);

-- KDS管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('kds:view',                'KDS查看',        'KDS', '厨显数据只读', 90),
('kds:operate',             'KDS操作',        'KDS', '划菜/催菜/工单操作', 91),
('kds:config',              'KDS配置',        'KDS', '档口/绑屏/设备/门店模式', 92);

-- 收银管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('cashier:shift',           '班次管理',       '收银', '开班/交班/当前班次', 100),
('cashier:operate',         '收银端操作',     '收银', '收银端KDS投递等操作', 101);

-- 物料管理
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('material:manage',         '物料管理',       '物料', '物料/入库/出库/预警', 110);

-- 支付配置
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('payment:config',          '支付配置',       '支付', '支付商户/证书/渠道配置', 120);

-- -----------------------------------------------------------
-- 2. 五大角色（插入 t_role，已存在则跳过）
-- -----------------------------------------------------------
INSERT IGNORE INTO t_role (role_code, role_name, remark, sort_order, version) VALUES
('boss',           '老板',     '最高权限，拥有所有功能', 1, 1),
('store_manager',  '店长',     '门店日常管理，除系统管理员外的所有权限', 2, 1),
('waiter',         '服务员',   '接单、加菜、桌台操作、KDS查看', 3, 1),
('head_chef',      '厨师长',   '菜品管理、KDS配置与操作、订单查看', 4, 1),
('cashier',        '收银员',   '结账、退款、折扣、班次、日结、会员充值', 5, 1);

-- -----------------------------------------------------------
-- 3. 角色-权限关联
--    先清除五大角色的旧关联，再重新插入（保证幂等）
-- -----------------------------------------------------------

-- 清除旧关联（仅清除本次重构的五个角色）
DELETE rp FROM t_role_permission rp
INNER JOIN t_role r ON rp.role_id = r.id
WHERE r.role_code IN ('boss','store_manager','waiter','head_chef','cashier');

-- 辅助：用角色code关联权限code插入
-- 老板：所有权限
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'boss';

-- 店长：除 admin:manage 外的所有权限
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'store_manager'
  AND p.permission_code != 'admin:manage';

-- 服务员：订单查看、接单、加菜、删菜、桌台操作、KDS查看与操作、修改密码
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'waiter'
  AND p.permission_code IN (
    'admin:password',
    'order:view','order:view:list','order:view:detail','order:view:log',
    'order:operate','order:operate:accept','order:operate:addDish','order:operate:deleteDish',
    'table:manage','table:operate','table:operate:open','table:operate:merge','table:operate:transfer','table:operate:clear',
    'kds:view','kds:operate'
  );

-- 厨师长：菜品管理、KDS配置与操作、订单查看、修改密码、物料管理
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'head_chef'
  AND p.permission_code IN (
    'admin:password',
    'order:view','order:view:list','order:view:detail','order:view:log',
    'dish:manage','dish:manage:category','dish:manage:dish','dish:manage:unit',
    'kds:view','kds:operate','kds:config',
    'material:manage'
  );

-- 收银员：收银操作、订单查看、结账/挂单/加菜、桌台操作(开台/并台/转台)、班次、会员充值、报表(个人业绩)、修改密码
INSERT INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id FROM t_role r, t_permission p
WHERE r.role_code = 'cashier'
  AND p.permission_code IN (
    'admin:password',
    'order:view','order:view:list','order:view:detail',
    'order:operate','order:operate:checkout','order:operate:hang','order:operate:addDish','order:operate:deleteDish',
    'order:config',
    'table:manage','table:operate','table:operate:open','table:operate:merge','table:operate:transfer',
    'user:view','user:operate','user:operate:recharge',
    'statistics:view','statistics:view:cashierPerformance',
    'cashier:shift','cashier:operate',
    'kds:view','kds:operate'
  );

-- -----------------------------------------------------------
-- 4. t_api_permission 接口权限码细化更新
--    将粗粒度权限码的接口更新为细粒度权限码
--    注意：只更新明确可拆分的接口，其余保持原样
-- -----------------------------------------------------------

-- 订单操作类接口细化
UPDATE t_api_permission SET permission_code = 'order:operate:accept'
WHERE path_pattern IN ('/admin/order/receiving','/admin/order/rece') AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'order:operate:checkout'
WHERE path_pattern = '/admin/order/checkout' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/admin/order/refund' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/admin/orderDetail/delete_menu' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'order:operate:addDish'
WHERE path_pattern = '/admin/orderDetail/updateQuantity' AND permission_code = 'order:operate';

-- 收银端接口细化
UPDATE t_api_permission SET permission_code = 'order:operate:checkout'
WHERE path_pattern = '/cashier/order/checkout' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/cashier/order/refundDish' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/cashier/order/updatePrice' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/cashier/order/discount' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'order:operate:addDish'
WHERE path_pattern IN ('/cashier/order/quickOrder','/cashier/order/addDishes') AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'order:operate:hang'
WHERE path_pattern = '/cashier/order/hang' AND permission_code = 'order:operate';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/cashier/order/unCheckout' AND permission_code = 'order:operate';

-- 桌台操作细化
UPDATE t_api_permission SET permission_code = 'table:operate:open'
WHERE path_pattern = '/cashier/table/open' AND permission_code = 'table:manage';

UPDATE t_api_permission SET permission_code = 'table:operate:merge'
WHERE path_pattern = '/cashier/table/merge' AND permission_code = 'table:manage';

UPDATE t_api_permission SET permission_code = 'table:operate:transfer'
WHERE path_pattern = '/cashier/table/transfer' AND permission_code = 'table:manage';

UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern = '/cashier/table/clear' AND permission_code = 'table:manage';

-- 日结细化
UPDATE t_api_permission SET permission_code = 'admin:manage'
WHERE path_pattern IN ('/admin/daily/settle','/admin/daily/summary','/admin/daily/income','/admin/daily/byChannel','/admin/daily/grossProfit')
  AND permission_code = 'order:config';

-- 班次细化
UPDATE t_api_permission SET permission_code = 'cashier:shift'
WHERE path_pattern IN ('/cashier/shift/start','/cashier/shift/handover','/cashier/shift/current')
  AND permission_code = 'order:config';

-- 会员充值细化
UPDATE t_api_permission SET permission_code = 'user:operate:recharge'
WHERE path_pattern = '/admin/member/recharge' AND permission_code = 'user:view';

-- 积分操作细化
UPDATE t_api_permission SET permission_code = 'user:operate:points'
WHERE path_pattern = '/admin/order/addPoints' AND permission_code = 'user:points';

-- 报表细化（收银员只能看自己业绩，其余报表保持 statistics:view）
-- 收银员业绩接口保持 statistics:view，由前端按角色过滤展示

-- -----------------------------------------------------------
-- 5. 验证查询（执行后可运行确认）
-- -----------------------------------------------------------
-- SELECT r.role_name, COUNT(*) AS perm_count
-- FROM t_role r
-- LEFT JOIN t_role_permission rp ON r.id = rp.role_id
-- WHERE r.role_code IN ('boss','store_manager','waiter','head_chef','cashier')
-- GROUP BY r.id, r.role_name
-- ORDER BY r.sort_order;

-- SELECT r.role_name, p.permission_code, p.permission_name
-- FROM t_role r
-- JOIN t_role_permission rp ON r.id = rp.role_id
-- JOIN t_permission p ON rp.permission_id = p.id
-- WHERE r.role_code = 'waiter'
-- ORDER BY p.sort_order;
