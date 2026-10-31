-- phpMyAdmin SQL Dump
-- version 5.0.4
-- https://www.phpmyadmin.net/
--
-- 主机： localhost
-- 生成日期： 2026-09-07 04:22:40
-- 服务器版本： 5.7.44-log
-- PHP 版本： 7.4.33

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- 数据库： `db_diancan`
--

-- --------------------------------------------------------

--
-- 表的结构 `t_permission`
--

CREATE TABLE `t_permission` (
  `id` int(11) NOT NULL,
  `permission_code` varchar(64) NOT NULL COMMENT '权限编码，如 order:view, dish:manage',
  `permission_name` varchar(64) NOT NULL COMMENT '权限名称',
  `module` varchar(32) DEFAULT NULL COMMENT '模块：order/dish/statistics等',
  `remark` varchar(255) DEFAULT NULL,
  `sort_order` int(11) DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限表' ROW_FORMAT=DYNAMIC;

--
-- 转存表中的数据 `t_permission`
--

INSERT INTO `t_permission` (`id`, `permission_code`, `permission_name`, `module`, `remark`, `sort_order`) VALUES
(1, 'admin:login', '管理员登录', '系统', NULL, 0),
(2, 'admin:password', '修改密码', '系统', NULL, 0),
(3, 'order:view', '订单查看', '订单', '订单列表、订单详情', 0),
(4, 'order:operate', '订单操作', '订单', '接单、结账、明细接单、删除明细', 0),
(5, 'order:config', '订单配置', '订单', '自动接单开关、切换商户', 0),
(6, 'dish:manage', '菜品与分类单位管理', '菜品', '菜品/分类/单位增删改查、上下架、上传', 0),
(7, 'table:manage', '桌台管理', '桌台', '桌台列表、开台、清台等', 0),
(8, 'banner:manage', '轮播图管理', '营销', '轮播图列表、新增、删除', 0),
(9, 'statistics:view', '数据分析', '数据', '营业额、分类销售、菜品销售', 0),
(10, 'user:view', '用户信息查询', '会员', '查询用户信息', 0),
(11, 'user:points', '手动加积分', '会员', '后台给用户加积分', 0),
(12, 'shop:manage', '门店管理', '门店', '多店、营业时间', 0),
(13, 'cashier:operate', '收银机操作', '收银', '开台、点餐、结账、挂单、打印、交班', 0),
(14, 'material:manage', '原材料与库存', '库存', '入库、出库、预警、进销存', 0),
(15, 'daily:settle', '日结与对账', '对账', '门店日结、收入、渠道对账', 0),
(16, 'report:view', '数据报表', '数据', '日报周报月报、销量榜、收银员业绩、门店利润', 0),
(17, 'log:view', '操作日志', 'log', '订单日志、关键操作审计', 75),
(18, 'admin:manage', '权限管理', '系统', '管理员增删改，权限分配', 0),
(19, 'finance:view', '财务', '财务', '财务', 0),
(20, 'coupon:manage', '优惠券管理', '营销', '优惠券管理', 0),
(21, 'announcement:manage', '门店公告', '公告', '门店公告', 0),
(23, 'order:delete', '订单删除', '订单', '', 0),
(24, 'statistics:manage', '分类销售查询', '数据', '分类销售查询', 0),
(25, 'kds:config', 'KDS管理', '厨房', 'KDS管理', 0),
(26, 'payment:config:read', '支付模块读取权限', '支付', '', 0),
(27, 'payment:config:write', '支付模块写入权限', '支付', '', 0),
(28, 'test:view', '测试', '测试', '测试的', 0),
(29, 'settings:view', '设置导航查看', '系统', '系统设置导航概览、门店设置详情查看', 0),
(30, 'settings:manage', '门店设置管理', '系统', '保存门店设置覆盖、恢复总部继承', 0),
(31, 'report:export', '报表导出', '数据', '创建报表导出任务（仅超级管理员）', 0),
(32, 'log:archive', '日志归档检索', 'log', '30 天至 1 年归档日志异步检索', 73),
(33, 'log:export', '日志导出', 'log', '日志导出 CSV（仅超级管理员，需 purpose）', 74),
(36, 'notifications:view', '通知规则查看', '通知', '通知规则与发送记录查看', 0),
(37, 'notifications:manage', '通知规则管理', '通知', '通知规则增删改与试发', 0),
(38, 'printing:view', '打印查看', '打印', '打印设备列表、打印规则、打印任务记录查看', 0),
(39, 'printing:manage', '打印管理', '打印', '打印设备新建/更新、打印测试、打印规则保存', 0),
(40, 'marketing:firstorder:view', '首单活动查看', '营销', '首单活动列表/资格判定/核销记录查看', 0),
(41, 'marketing:firstorder:manage', '首单活动管理', '营销', '首单活动创建与更新', 0),
(44, 'access:view', '员工与权限查看', '系统', '员工授权/角色/权限解释查看', 0),
(45, 'access:manage', '员工与权限管理', '系统', '员工角色分配、角色增删改', 0),
(46, 'inventory:view', '库存查看', '库存', '库存扩展：供应商/仓库/BOM/采购/调拨/批次查看', 0),
(47, 'inventory:manage', '库存管理', '库存', '库存扩展：供应商/仓库/BOM/采购/调拨写操作；结算字段仅此权限可见', 0),
(48, 'payment:view', '支付渠道查看', '支付', '支付渠道列表/停用影响查看', 0),
(49, 'payment:manage', '支付渠道管理', '支付', '支付渠道启停与测试交易', 0),
(73, 'admin:config', '系统配置', '系统', '飞鹅云、邀请海报等系统级配置', 0),
(74, 'admin:log', '操作日志', '系统', '查看操作审计日志', 4),
(77, 'order:view:list', '订单列表', '订单', '查看订单列表', 11),
(78, 'order:view:detail', '订单详情', '订单', '查看订单详情', 12),
(79, 'order:view:log', '订单日志', '订单', '查看订单操作日志', 13),
(80, 'order:operate:accept', '接单', '订单', '接单/拒单', 21),
(81, 'order:operate:checkout', '结账', '订单', '订单结账', 22),
(82, 'order:operate:refund', '退款', '订单', '微信退款/退菜', 23),
(83, 'order:operate:addDish', '加菜', '订单', '加菜/改数量', 24),
(84, 'order:operate:deleteDish', '删菜', '订单', '删除菜品明细', 25),
(85, 'order:operate:changePrice', '改价', '订单', '修改菜品价格', 26),
(86, 'order:operate:discount', '折扣/优惠', '订单', '订单折扣、优惠减免', 27),
(87, 'order:operate:hang', '挂单', '订单', '挂起订单', 28),
(88, 'order:operate:unCheckout', '反结账', '订单', '取消结账', 29),
(89, 'order:config:autoAccept', '自动接单配置', '订单', '开关自动接单', 0),
(90, 'order:config:paymentMethod', '支付方式配置', '订单', '支付方式管理', 32),
(91, 'order:config:dailySettle', '日结', '订单', '日结操作与查询', 33),
(92, 'order:config:shop', '门店配置', '订单', '门店信息管理', 34),
(96, 'dish:manage:category', '分类管理', '菜品', '菜品分类增删改排序', 41),
(97, 'dish:manage:dish', '菜品管理', '菜品', '菜品增删改、上下架、排序', 42),
(98, 'dish:manage:unit', '单位管理', '菜品', '菜品单位管理', 43),
(100, 'table:operate', '桌台操作', '桌台', '开台/并台/转台/清台（父权限）', 51),
(101, 'table:operate:open', '开台', '桌台', '开台', 52),
(102, 'table:operate:merge', '并台', '桌台', '合并桌台', 53),
(103, 'table:operate:transfer', '转台', '桌台', '转移桌台', 54),
(104, 'table:operate:clear', '清台', '桌台', '清理桌台', 55),
(109, 'statistics:view:sales', '营业额', '报表', '营业额/销售趋势', 71),
(110, 'statistics:view:dashboard', '经营仪表盘', '报表', '经营数据总览', 72),
(111, 'statistics:view:report', '周期报表', '报表', '日报/周报/月报', 73),
(112, 'statistics:view:dishRanking', '菜品排行', '报表', '菜品销量排行', 74),
(113, 'statistics:view:cashierPerformance', '收银员业绩', '报表', '收银员个人业绩', 75),
(114, 'statistics:view:profit', '利润分析', '报表', '毛利/利润分析', 76),
(115, 'statistics:view:inventory', '库存报表', '报表', '物料库存报表', 77),
(116, 'statistics:view:recharge', '充值报表', '报表', '会员充值记录', 78),
(118, 'user:operate', '会员操作', '会员', '会员所有操作（父权限）', 81),
(119, 'user:operate:recharge', '会员充值', '会员', '会员余额充值', 82),
(120, 'user:operate:points', '积分操作', '会员', '手动加减积分', 83),
(122, 'kds:view', 'KDS查看', 'KDS', '厨显数据只读', 90),
(123, 'kds:operate', 'KDS操作', 'KDS', '划菜/催菜/工单操作', 91),
(125, 'cashier:shift', '班次管理', '收银', '开班/交班/当前班次', 100),
(128, 'payment:config', '支付配置', '支付', '支付商户/证书/渠道配置', 120),
(186, 'public', '公开接口', '系统', '登录即可访问的接口（我的权限/我的门店/登录）', 130),
(192, 'announcement:view', '查看公告', '公告', '权限一致性重建 v3', 0);

--
-- 转储表的索引
--

--
-- 表的索引 `t_permission`
--
ALTER TABLE `t_permission`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_permission_code` (`permission_code`) USING BTREE;

--
-- 在导出的表使用AUTO_INCREMENT
--

--
-- 使用表AUTO_INCREMENT `t_permission`
--
ALTER TABLE `t_permission`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=274;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
