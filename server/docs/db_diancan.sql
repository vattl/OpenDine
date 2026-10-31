-- phpMyAdmin SQL Dump
-- version 5.0.4
-- https://www.phpmyadmin.net/
--
-- 主机： localhost
-- 生成日期： 2026-09-07 00:30:57
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
-- 表的结构 `t_access_approval`
--

CREATE TABLE IF NOT EXISTS `t_access_approval` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `approval_no` varchar(64) NOT NULL COMMENT '审批唯一流水号',
  `permission_code` varchar(100) NOT NULL COMMENT '需要授权的目标权限码',
  `operator_id` int(11) NOT NULL COMMENT '操作人管理员ID',
  `authorizer_id` int(11) NOT NULL COMMENT '授权人(店长)管理员ID',
  `shop_id` int(11) NOT NULL COMMENT '门店ID',
  `biz_type` varchar(50) NOT NULL COMMENT '业务类型: ORDER, REFUND, CASH_DRAWER等',
  `biz_id` varchar(100) NOT NULL COMMENT '业务对象唯一标识 (如订单号)',
  `amount` decimal(12,2) DEFAULT NULL COMMENT '申请涉及的业务金额',
  `reason` varchar(500) NOT NULL COMMENT '授权原因',
  `auth_method` varchar(30) NOT NULL COMMENT '授权认证方式: PASSWORD, PIN, SESSION',
  `status` varchar(20) NOT NULL DEFAULT 'APPROVED' COMMENT '状态: PENDING, APPROVED, CONSUMED, EXPIRED, REVOKED, REJECTED',
  `token_hash` char(64) NOT NULL COMMENT '短期授权Token的SHA-256哈希值',
  `binding_version` int(11) NOT NULL DEFAULT 1 COMMENT '审批上下文绑定策略版本: 1兼容, 2严格',
  `token_value` varchar(512) DEFAULT NULL COMMENT '二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌',
  `max_amount` decimal(12,2) DEFAULT NULL COMMENT '授权允许的最大金额上限',
  `expires_at` datetime NOT NULL COMMENT 'Token有效截止时间',
  `consumed_at` datetime DEFAULT NULL COMMENT 'Token核销消费时间',
  `request_id` varchar(128) DEFAULT NULL COMMENT '客户端幂等请求标识',
  `terminal_id` varchar(100) DEFAULT NULL COMMENT '终端编号',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_approval_no` (`approval_no`),
  KEY `idx_token_hash` (`token_hash`),
  KEY `idx_operator` (`operator_id`),
  KEY `idx_biz` (`biz_type`, `biz_id`),
  KEY `idx_expire` (`status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限临时审批与授权令牌表' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_access_approval_rate_limit`
--

CREATE TABLE IF NOT EXISTS `t_access_approval_rate_limit` (
  `limit_key` char(64) NOT NULL COMMENT 'SHA-256 composite key; never contains raw account or credential',
  `limit_scope` varchar(40) NOT NULL COMMENT 'ONSITE_AUTHORIZE, QR_CREATE, QR_CONFIRM, CREDENTIAL_FAILURE',
  `window_started_at` datetime(3) NOT NULL,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `blocked_until` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`limit_key`),
  KEY `idx_approval_rate_limit_cleanup` (`updated_at`),
  KEY `idx_approval_rate_limit_blocked` (`blocked_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='审批接口与凭据失败跨实例限流状态';

-- --------------------------------------------------------

--
-- 表的结构 `t_activity_popup`
--

CREATE TABLE `t_activity_popup` (
  `id` bigint(20) NOT NULL COMMENT '活动ID',
  `name` varchar(100) NOT NULL COMMENT '活动名称',
  `popup_image` varchar(255) NOT NULL COMMENT '弹窗图片',
  `image_url` varchar(255) DEFAULT NULL COMMENT '点击跳转地址',
  `target_user` varchar(20) NOT NULL DEFAULT 'all' COMMENT '目标用户：new/member/all',
  `start_time` datetime NOT NULL COMMENT '开始时间',
  `end_time` datetime NOT NULL COMMENT '结束时间',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：1-启用 0-禁用',
  `budget_amount` decimal(12,2) DEFAULT NULL COMMENT '活动投入预算(元)，用于ROI',
  `max_show_count` int(11) NOT NULL DEFAULT '1' COMMENT '单日最大展示次数',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `sorting` int(11) NOT NULL,
  `type` enum('home_top','home_bottom','page_top','page_hor','page_activity','invite_top') NOT NULL COMMENT '轮播图：home_top/home_bottom/page_top/page_hor/page_activity/invite_top',
  `apply_shop_ids` varchar(500) DEFAULT NULL COMMENT '适用门店 JSON 数组，如 [1,5,3]；NULL/空/[]=全部门店'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='活动弹窗表（简化版）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_admin`
--

CREATE TABLE `t_admin` (
  `id` int(11) NOT NULL,
  `userName` varchar(22) CHARACTER SET utf8 DEFAULT NULL,
  `work_no` varchar(32) DEFAULT NULL COMMENT '员工工号，用于工号登录',
  `real_name` varchar(64) DEFAULT NULL COMMENT '员工真实姓名，系统各处操作人展示此姓名',
  `job_title` varchar(64) DEFAULT NULL COMMENT '员工岗位/职位',
  `password` varchar(255) DEFAULT NULL COMMENT '密码（BCrypt 或历史明文）',
  `token_version` int(11) NOT NULL DEFAULT '0' COMMENT '管理员令牌版本，递增后旧令牌立即失效'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_admin_region`
--

CREATE TABLE `t_admin_region` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT '管理员ID，t_admin.id',
  `region_id` int(11) NOT NULL COMMENT '区域ID，t_region.id'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='管理员-区域绑定';

-- --------------------------------------------------------

--
-- 表的结构 `t_admin_role`
--

CREATE TABLE `t_admin_role` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT 't_admin.id',
  `role_id` int(11) NOT NULL COMMENT 't_role.id'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='管理员-角色关联' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_admin_shop`
--

CREATE TABLE `t_admin_shop` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT 't_admin.id',
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='管理员-可管理门店';

-- --------------------------------------------------------

--
-- 表的结构 `t_announcement`
--

CREATE TABLE `t_announcement` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT 'NULL=全部门店可见；非空=仅该门店',
  `title` varchar(200) NOT NULL COMMENT '标题',
  `content` longtext NOT NULL COMMENT '正文（纯文本或富文本 HTML，由前端约定）',
  `status` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=启用 0=停用',
  `sort_order` int(11) NOT NULL DEFAULT '0' COMMENT '越小越靠前',
  `start_time` datetime DEFAULT NULL COMMENT '可见开始时间，NULL=不限制',
  `end_time` datetime DEFAULT NULL COMMENT '可见结束时间，NULL=不限制',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店公告（连锁）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_api_permission`
--

CREATE TABLE `t_api_permission` (
  `id` int(11) NOT NULL,
  `method` varchar(10) NOT NULL COMMENT 'GET/POST/PUT/DELETE',
  `path_pattern` varchar(255) NOT NULL COMMENT '路径，如 /admin/order/list',
  `permission_code` varchar(64) NOT NULL COMMENT '所需权限码',
  `remark` varchar(255) DEFAULT NULL COMMENT '接口备注'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='接口-权限映射';

-- --------------------------------------------------------

--
-- 表的结构 `t_app_schema_version`
--

CREATE TABLE `t_app_schema_version` (
  `version` varchar(32) NOT NULL,
  `checksum` varchar(64) NOT NULL,
  `applied_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- 表的结构 `t_banner`
--

CREATE TABLE `t_banner` (
  `id` int(11) NOT NULL,
  `image` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  `status` int(11) DEFAULT NULL,
  `type` varchar(10) NOT NULL COMMENT '首页：home，底部：bottom'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_cashier_collection_intent`
--

CREATE TABLE `t_cashier_collection_intent` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `session_id` varchar(64) NOT NULL,
  `channel` varchar(16) NOT NULL,
  `amount_fen` int(11) NOT NULL,
  `status` varchar(24) NOT NULL DEFAULT 'PENDING',
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- 表的结构 `t_category`
--

CREATE TABLE `t_category` (
  `id` int(11) NOT NULL,
  `label` varchar(30) DEFAULT NULL,
  `value` varchar(30) DEFAULT NULL,
  `count` int(11) DEFAULT NULL,
  `sele_quantity` int(11) DEFAULT '0',
  `cid` varchar(30) DEFAULT NULL,
  `sorting` int(11) DEFAULT NULL COMMENT '排序'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- 门店分类排序覆盖（分类主数据仍共用 t_category）
CREATE TABLE `t_category_shop` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `category_id` int(11) NOT NULL COMMENT 't_category.id',
  `sorting_override` int(11) NOT NULL COMMENT '当前门店分类顺序，1-based',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店分类排序覆盖';

-- --------------------------------------------------------

--
-- 表的结构 `t_combo`
--

CREATE TABLE `t_combo` (
  `id` bigint(20) NOT NULL,
  `dish_id` int(11) NOT NULL COMMENT '套餐头菜品 t_dish.id，唯一',
  `combo_type` varchar(16) NOT NULL DEFAULT 'groups' COMMENT 'fixed=仅固定子项; groups=含可选组',
  `status` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1启用 0停用',
  `limit_per_order` int(11) DEFAULT NULL COMMENT '单笔订单限购份数，NULL或<=0表示不限',
  `limit_per_user` int(11) DEFAULT NULL COMMENT '单用户限购份数，NULL或<=0表示不限',
  `limit_cycle` varchar(20) NOT NULL DEFAULT 'daily' COMMENT '用户限购周期：daily(每日)|lifetime(终生)',
  `start_time` datetime DEFAULT NULL COMMENT '活动生效开始时间，NULL表示不限',
  `end_time` datetime DEFAULT NULL COMMENT '活动生效截止时间，NULL表示不限',
  `available_days` varchar(32) DEFAULT NULL COMMENT '可用星期，逗号分隔，NULL表示不限',
  `time_range_start` varchar(16) DEFAULT NULL COMMENT '每日可用起始时段，如 11:00',
  `time_range_end` varchar(16) DEFAULT NULL COMMENT '每日可用截止时段，如 14:00',
  `apply_dining_type` varchar(20) NOT NULL DEFAULT 'all' COMMENT '适用就餐方式：all|dine_in|take_out',
  `allow_coupon` tinyint(4) NOT NULL DEFAULT '1' COMMENT '是否允许叠加优惠券：1允许 0禁止',
  `daily_stock` int(11) DEFAULT NULL COMMENT '每日套餐配额，NULL表示不限',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='套餐定义头';

-- --------------------------------------------------------

--
-- 表的结构 `t_combo_fixed_item`
--

CREATE TABLE `t_combo_fixed_item` (
  `id` bigint(20) NOT NULL,
  `combo_id` bigint(20) NOT NULL,
  `component_dish_id` int(11) NOT NULL COMMENT '子菜 t_dish.id',
  `qty_per_combo` int(11) NOT NULL DEFAULT '1' COMMENT '每份套餐含该子菜份数',
  `sort_order` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='套餐固定子项';

-- --------------------------------------------------------

--
-- 表的结构 `t_combo_group`
--

CREATE TABLE `t_combo_group` (
  `id` bigint(20) NOT NULL,
  `combo_id` bigint(20) NOT NULL,
  `group_key` varchar(32) NOT NULL COMMENT '与下单 combo_selections 的 key 对应',
  `title` varchar(64) DEFAULT NULL COMMENT '展示标题',
  `min_pick` int(11) NOT NULL DEFAULT '1',
  `max_pick` int(11) NOT NULL DEFAULT '1',
  `sort_order` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='套餐可选组';

-- --------------------------------------------------------

--
-- 表的结构 `t_combo_group_item`
--

CREATE TABLE `t_combo_group_item` (
  `id` bigint(20) NOT NULL,
  `group_id` bigint(20) NOT NULL,
  `component_dish_id` int(11) NOT NULL,
  `extra_price` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '相对套餐基准价的加价(元)/每份套餐',
  `sort_order` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='套餐组内可选项';

-- --------------------------------------------------------

--
-- 表的结构 `t_coupon`
--

CREATE TABLE `t_coupon` (
  `id` bigint(20) NOT NULL COMMENT '主键ID',
  `coupon_name` varchar(100) NOT NULL COMMENT '优惠券名称（如：满50减10）',
  `coupon_type` varchar(20) NOT NULL COMMENT '优惠券类型：full_reduction-满减 discount-折扣 direct_reduction-立减',
  `apply_dining_type` enum('all','dine_in','take_out') NOT NULL DEFAULT 'all' COMMENT '''适用用餐方式：all=全部，dine_in=仅限堂食，take_out=仅限打包''',
  `apply_dish_ids` varchar(1000) DEFAULT NULL COMMENT '适用菜品ID数组（JSON字符串），为空表示不限菜品，如 [1,2,3]',
  `apply_shop_ids` varchar(1000) DEFAULT NULL COMMENT '适用门店ID JSON 数组，如 [1,2]；空/NULL 不限门店',
  `discount_value` decimal(10,2) NOT NULL COMMENT '优惠值：满减/立减为金额，折扣为百分比（如80=8折）',
  `min_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '使用门槛（满X元可用），0为无门槛',
  `start_time` datetime NOT NULL COMMENT '生效时间',
  `end_time` datetime NOT NULL COMMENT '失效时间',
  `status` tinyint(4) NOT NULL DEFAULT '1' COMMENT '状态：0-未启用 1-可用 2-已下架',
  `stock` int(11) NOT NULL DEFAULT '-1' COMMENT '库存：-1为无限库存，>=0为有限库存',
  `granted_count` int(11) NOT NULL DEFAULT '0' COMMENT '已发放张数（写入 t_user_coupon 累计）',
  `description` varchar(500) DEFAULT '' COMMENT '优惠券描述',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `validity_time` bigint(20) NOT NULL COMMENT '有效期，单位小时'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='优惠券主表' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_coupon_redeem_code`
--

CREATE TABLE `t_coupon_redeem_code` (
  `id` bigint(20) NOT NULL COMMENT '主键ID',
  `coupon_id` bigint(20) NOT NULL COMMENT '关联优惠券ID（t_coupon.id）',
  `redeem_code` varchar(64) NOT NULL COMMENT '兑换码（唯一）',
  `status` tinyint(4) NOT NULL DEFAULT '0' COMMENT '状态：0-未使用 1-已使用',
  `used_openid` varchar(100) DEFAULT NULL COMMENT '使用者openid',
  `used_time` datetime DEFAULT NULL COMMENT '使用时间',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='优惠券兑换码表（一码一券）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_daily_stat`
--

CREATE TABLE `t_daily_stat` (
  `id` bigint(20) NOT NULL,
  `stat_date` date NOT NULL COMMENT '统计日期',
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，NULL表示全店',
  `total_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '营业额',
  `discount_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '优惠/折扣合计',
  `refund_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '退款合计',
  `material_cost` decimal(12,2) DEFAULT NULL COMMENT '当日原材料成本',
  `settled_at` datetime DEFAULT NULL COMMENT '日结时间',
  `operator_id` int(11) DEFAULT NULL COMMENT '日结操作员',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='日结对账';

-- --------------------------------------------------------

--
-- 表的结构 `t_dish`
--

CREATE TABLE `t_dish` (
  `id` int(11) NOT NULL,
  `name` varchar(50) DEFAULT NULL COMMENT '菜品名称',
  `image` varchar(50) DEFAULT NULL COMMENT '菜品图片',
  `typeId` int(11) DEFAULT NULL COMMENT '类别ID',
  `monthlysale` int(11) DEFAULT '0' COMMENT '商品销售量',
  `unitprice` decimal(6,2) DEFAULT NULL COMMENT '商品单价',
  `cost_price` decimal(10,2) DEFAULT NULL COMMENT '成本价(元)，用于毛利分析',
  `unit` varchar(10) DEFAULT NULL COMMENT '商品单位',
  `quantity` int(11) DEFAULT '0' COMMENT '商品数量',
  `stock` int(11) DEFAULT NULL COMMENT '可售库存份数；NULL 表示不限量；与 quantity 解耦，下单扣减仅更新本列',
  `time` datetime DEFAULT NULL COMMENT '上架时间',
  `onsale` bit(1) DEFAULT NULL COMMENT 'true：上架 false：下架',
  `sold_out` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否已售罄：0-否 1-是',
  `specification` varchar(255) DEFAULT NULL COMMENT '产品规格',
  `serving_duration_minutes` int(11) NOT NULL DEFAULT '10' COMMENT '出餐时长（分钟），用于 KDS 单品超时判断',
  `sorting` int(11) DEFAULT NULL COMMENT '排序'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_dish_material_bom`
--

CREATE TABLE `t_dish_material_bom` (
  `id` bigint(20) NOT NULL COMMENT '配比ID',
  `shop_id` int(11) NOT NULL COMMENT '门店ID(t_shop.id)',
  `dish_id` int(11) NOT NULL COMMENT '菜品ID(t_dish.id)',
  `material_id` int(11) NOT NULL COMMENT '原材料ID(t_material.id)',
  `dosage` decimal(10,3) NOT NULL DEFAULT '0.000' COMMENT '单份菜品消耗原材料数量',
  `unit` varchar(16) NOT NULL DEFAULT '斤' COMMENT '单位：斤/克/袋/瓶',
  `loss_rate` decimal(5,2) NOT NULL DEFAULT '0.05' COMMENT '损耗率小数，如0.05=5%；消耗=销量×用量×(1+loss_rate)',
  `is_enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1启用 0禁用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='菜品-原材料配比表(BOM)';

-- --------------------------------------------------------

--
-- 表的结构 `t_dish_shop`
--

CREATE TABLE `t_dish_shop` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `dish_id` int(11) NOT NULL COMMENT 't_dish.id',
  `unitprice` decimal(10,2) DEFAULT NULL COMMENT '门店覆盖价；NULL 则用 t_dish.unitprice',
  `stock` int(11) NOT NULL DEFAULT '-1' COMMENT '门店可售库存；-1 不限量；>=0 为有限库存',
  `stock_enabled` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否启用库存跟踪（持久标志，不随库存值变化）：1 跟踪（扣减/回退）；0 不限量或未启用',
  `sold_out` tinyint(4) NOT NULL DEFAULT '0' COMMENT 'shop sold-out flag: 0 available, 1 sold out',
  `onsale_override` tinyint(4) DEFAULT NULL COMMENT 'NULL 跟随总部；0 强制下架；1 强制上架',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店菜品覆盖（价/库存/上下架）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_first_order_campaign`
--

CREATE TABLE `t_first_order_campaign` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `name` varchar(128) NOT NULL COMMENT '活动名称',
  `campaign_type` varchar(32) NOT NULL COMMENT 'DISCOUNT=立减 / GIFT=赠品 / FREEBIE=首单免费',
  `threshold_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '门槛金额（元）',
  `discount_value` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '优惠金额/折让（元）',
  `discount_desc` varchar(255) DEFAULT NULL COMMENT '优惠描述',
  `start_time` datetime NOT NULL COMMENT '生效时间',
  `end_time` datetime NOT NULL COMMENT '失效时间',
  `status` varchar(16) NOT NULL DEFAULT 'DRAFT' COMMENT 'DRAFT/ACTIVE/PAUSED/EXPIRED',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='首单活动';

-- --------------------------------------------------------

--
-- 表的结构 `t_first_order_redemption`
--

CREATE TABLE `t_first_order_redemption` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `campaign_id` bigint(20) NOT NULL COMMENT 't_first_order_campaign.id',
  `customer_id` varchar(128) NOT NULL COMMENT '客户标识（openid 或手机号）',
  `order_no` varchar(64) DEFAULT NULL,
  `order_id` int(11) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '实享优惠金额（元）',
  `status` varchar(16) NOT NULL DEFAULT 'USED' COMMENT 'USED=已核销 / RESTORED=已恢复',
  `restored_reason` varchar(32) DEFAULT NULL COMMENT 'cancel/full_refund/manual',
  `restored_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='首单核销记录';

-- --------------------------------------------------------

--
-- 表的结构 `t_hq_settings`
--

CREATE TABLE `t_hq_settings` (
  `module` varchar(64) NOT NULL COMMENT '模块标识：store/printing/payment/notifications…',
  `payload_json` longtext COMMENT '模块配置 JSON',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本',
  `updated_by` int(11) DEFAULT NULL COMMENT '最后更新管理员 t_admin.id',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='总部设置默认值';

-- --------------------------------------------------------

--
-- 表的结构 `t_inventory_batch`
--

CREATE TABLE `t_inventory_batch` (
  `id` bigint(20) NOT NULL COMMENT '主键自增',
  `shop_id` int(11) NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `material_id` int(11) NOT NULL COMMENT '原材料 t_material.id',
  `warehouse_id` bigint(20) NOT NULL COMMENT '所属仓库 t_inventory_warehouse.id',
  `batch_no` varchar(64) NOT NULL COMMENT '批次号（同一仓库内建议唯一，用于追溯）',
  `qty` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '剩余可用数量（>=0，出库扣减）',
  `expiry_date` date DEFAULT NULL COMMENT '到期日（FEFO 按其升序；NULL 排最后）',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存扩展-批次';

-- --------------------------------------------------------

--
-- 表的结构 `t_inventory_bom`
--

CREATE TABLE `t_inventory_bom` (
  `id` bigint(20) NOT NULL COMMENT '主键自增',
  `shop_id` int(11) NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `dish_id` int(11) NOT NULL COMMENT '菜品 t_dish.id',
  `version_no` int(11) NOT NULL COMMENT '版本号，同 (shop_id,dish_id) 内自 1 递增',
  `status` varchar(16) NOT NULL DEFAULT 'HISTORY' COMMENT '版本状态：ACTIVE 有效（同店同菜唯一）/ HISTORY 历史',
  `items_json` longtext COMMENT 'BOM 明细 JSON [{materialId,qty,unit,alternates:[materialId…]}]',
  `effective_from` datetime DEFAULT NULL COMMENT '生效时间',
  `created_by` int(11) DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存扩展-BOM版本';

-- --------------------------------------------------------

--
-- 表的结构 `t_inventory_purchase`
--

CREATE TABLE `t_inventory_purchase` (
  `id` bigint(20) NOT NULL COMMENT '主键自增',
  `shop_id` int(11) NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `supplier_id` bigint(20) NOT NULL COMMENT '供应商 t_inventory_supplier.id',
  `warehouse_id` bigint(20) NOT NULL COMMENT '收货仓库 t_inventory_warehouse.id',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING_REVIEW' COMMENT '状态：DRAFT 草稿 / PENDING_REVIEW 待审核 / APPROVED 已审核 / REJECTED 已驳回 / RECEIVED 已收货',
  `items_json` longtext COMMENT '明细 JSON [{materialId,qty,unit,price,remark}]',
  `audit_json` longtext COMMENT '审核记录 JSON [{action,fromStatus,toStatus,adminId,at,reason}]',
  `created_by` int(11) DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存扩展-采购单';

-- --------------------------------------------------------

--
-- 表的结构 `t_inventory_supplier`
--

CREATE TABLE `t_inventory_supplier` (
  `id` bigint(20) NOT NULL COMMENT '主键自增',
  `shop_id` int(11) NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `name` varchar(128) NOT NULL COMMENT '供应商名称',
  `contact_name` varchar(64) DEFAULT NULL COMMENT '联系人姓名',
  `contact_phone` varchar(32) DEFAULT NULL COMMENT '联系电话',
  `supply_scope` varchar(512) DEFAULT NULL COMMENT '供货范围（原料品类/品牌等描述）',
  `settlement_info` varchar(512) DEFAULT NULL COMMENT '结算信息（结算方式/账期/账户摘要），仅 inventory:manage 权限可见',
  `status` varchar(16) NOT NULL DEFAULT 'ENABLED' COMMENT '状态：ENABLED 启用 / DISABLED 停用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存扩展-供应商';

-- --------------------------------------------------------

--
-- 表的结构 `t_inventory_transfer`
--

CREATE TABLE `t_inventory_transfer` (
  `id` bigint(20) NOT NULL COMMENT '主键自增',
  `shop_id` int(11) NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `from_warehouse_id` bigint(20) NOT NULL COMMENT '调出仓库 t_inventory_warehouse.id',
  `to_warehouse_id` bigint(20) NOT NULL COMMENT '调入仓库 t_inventory_warehouse.id',
  `status` varchar(16) NOT NULL DEFAULT 'OUTBOUND' COMMENT '状态：OUTBOUND 已出库 / IN_TRANSIT 在途 / RECEIVED 已收货',
  `items_json` longtext COMMENT '明细 JSON [{batchId,materialId,qty,fefoOverrideReason}]，fefoOverrideReason 为人工跳过 FEFO 的原因',
  `created_by` int(11) DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存扩展-调拨单';

-- --------------------------------------------------------

--
-- 表的结构 `t_inventory_warehouse`
--

CREATE TABLE `t_inventory_warehouse` (
  `id` bigint(20) NOT NULL COMMENT '主键自增',
  `shop_id` int(11) NOT NULL COMMENT '门店 t_shop.id，数据隔离维度',
  `name` varchar(128) NOT NULL COMMENT '仓库名称',
  `legal_entity` varchar(128) NOT NULL COMMENT '经营主体（调拨仅允许同主体之间进行）',
  `address` varchar(256) DEFAULT NULL COMMENT '仓库地址',
  `status` varchar(16) NOT NULL DEFAULT 'ENABLED' COMMENT '状态：ENABLED 启用 / DISABLED 停用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='库存扩展-仓库';

-- --------------------------------------------------------

--
-- 表的结构 `t_invite_record`
--

CREATE TABLE `t_invite_record` (
  `id` bigint(20) NOT NULL COMMENT '主键ID',
  `inviter_openid` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '邀请者微信openid',
  `invitee_openid` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '被邀请者微信openid（未注册时为NULL）',
  `invite_code` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '邀请码（邀请人维度唯一）',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '邀请时间',
  `status` tinyint(4) NOT NULL DEFAULT '0' COMMENT '状态：0-未注册 1-已注册',
  `reward_type` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT 'coupon' COMMENT '奖励类型：coupon-优惠券 point-积分',
  `reward_id` bigint(20) DEFAULT NULL COMMENT '奖励优惠券ID（reward_type=coupon时）/积分值（reward_type=point时）',
  `reward_time` datetime DEFAULT NULL COMMENT '奖励发放时间',
  `first_order_reward_amount` decimal(12,2) DEFAULT NULL COMMENT '首单余额奖励金额(元)',
  `first_order_reward_time` datetime DEFAULT NULL COMMENT '首单余额奖励发放时间',
  `first_order_no` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '触发首单奖励的订单号'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='邀请关系记录表' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_invite_reward_clawback`
--

CREATE TABLE `t_invite_reward_clawback` (
  `id` bigint(20) NOT NULL,
  `invite_record_id` bigint(20) NOT NULL,
  `inviter_user_id` int(11) NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `outstanding_amount` decimal(12,2) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'PENDING',
  `attempts` int(11) NOT NULL DEFAULT '0',
  `last_error` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_authority_config_version`
--

CREATE TABLE `t_kds_authority_config_version` (
  `shop_id` int(11) NOT NULL,
  `version` bigint(20) NOT NULL DEFAULT '1',
  `cashier_device_code` varchar(64) DEFAULT NULL COMMENT 'Cashier authority identity; not a t_kds_device display device',
  `snapshot_hash` char(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Cashier-authoritative KDS configuration generation';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_delivery_consumer`
--

CREATE TABLE `t_kds_delivery_consumer` (
  `shop_id` int(11) NOT NULL,
  `device_code` varchar(64) DEFAULT NULL,
  `authority_epoch` bigint(20) NOT NULL DEFAULT '0',
  `lease_token_hash` char(64) DEFAULT NULL,
  `lease_until` datetime DEFAULT NULL,
  `ack_cursor` bigint(20) NOT NULL DEFAULT '0',
  `last_delivered_cursor` bigint(20) NOT NULL DEFAULT '0',
  `bootstrap_base_cursor` bigint(20) NOT NULL DEFAULT '0',
  `bootstrap_required` tinyint(1) NOT NULL DEFAULT '1',
  `client_version` varchar(64) DEFAULT NULL,
  `last_seen_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='每门店唯一收银 KDS 消费者租约与 ACK';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_delivery_event`
--

CREATE TABLE `t_kds_delivery_event` (
  `id` bigint(20) NOT NULL COMMENT '全局持久游标；门店内递增但不保证连续',
  `event_id` char(36) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `projection_version` bigint(20) NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `origin_channel` varchar(24) NOT NULL,
  `origin_device_code` varchar(64) DEFAULT NULL,
  `changed_detail_ids_json` text,
  `payload_json` longtext NOT NULL COMMENT '完整订单厨房投影，消费者无需拼 patch',
  `occurred_at_ms` bigint(20) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收银本地 KDS 可靠投递事件日志';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_device`
--

CREATE TABLE `t_kds_device` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `station_id` bigint(20) DEFAULT NULL,
  `screen_tag` varchar(32) NOT NULL,
  `device_code` varchar(64) NOT NULL,
  `device_name` varchar(64) DEFAULT NULL,
  `device_token` varchar(128) DEFAULT NULL,
  `workflows_json` varchar(64) DEFAULT NULL COMMENT 'prep,cook,serve 逗号分隔',
  `last_heartbeat_at` datetime DEFAULT NULL,
  `enabled` tinyint(4) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 厨显设备';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_device_workflow`
--

CREATE TABLE `t_kds_device_workflow` (
  `device_id` bigint(20) NOT NULL,
  `workflows` varchar(64) NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- 表的结构 `t_kds_device_screen`
--

CREATE TABLE `t_kds_device_screen` (
  `device_id` bigint(20) NOT NULL COMMENT 't_kds_device.id',
  `screen_tags` varchar(128) NOT NULL COMMENT '可见烤制岗，逗号分隔：meat_grill,veg_grill,seafood_special',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 设备可见岗';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_dish_screen`
--

CREATE TABLE `t_kds_dish_screen` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `dish_id` int(11) NOT NULL COMMENT 't_dish.id',
  `screen_tag` varchar(32) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 菜品绑屏';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_flow_batch`
--

CREATE TABLE `t_kds_flow_batch` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `ticket_id` bigint(20) NOT NULL COMMENT 't_kds_ticket.id',
  `detail_id` int(11) NOT NULL COMMENT 't_order_detail.id',
  `order_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT '1' COMMENT '本批次份数',
  `dining_channel` varchar(16) DEFAULT NULL COMMENT 'dine_in/pack/takeout',
  `queue_status` varchar(24) NOT NULL DEFAULT 'pending_prep' COMMENT 'pending_prep/pending_cook/ready_serve/done/void',
  `order_time` datetime DEFAULT NULL COMMENT '下单时间（FCFS）',
  `prep_at` datetime DEFAULT NULL COMMENT '配菜完成时间',
  `cooked_at` datetime DEFAULT NULL COMMENT '制作完成时间',
  `served_at` datetime DEFAULT NULL COMMENT '传菜完成时间',
  `void_reason` varchar(32) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 流转批次（分批配菜/划菜/传菜 FCFS）';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_operation_log`
--

CREATE TABLE `t_kds_operation_log` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `device_id` bigint(20) DEFAULT NULL,
  `order_id` int(11) NOT NULL,
  `detail_id` int(11) DEFAULT NULL,
  `ticket_id` bigint(20) DEFAULT NULL,
  `operation_type` varchar(32) NOT NULL COMMENT 'advance/revoke/rush/refund/lack/hold/release',
  `from_queue` varchar(32) DEFAULT NULL,
  `to_queue` varchar(32) DEFAULT NULL,
  `quantity` int(11) NOT NULL DEFAULT '0',
  `request_id` varchar(64) DEFAULT NULL,
  `operator_type` varchar(16) NOT NULL DEFAULT 'device' COMMENT 'device/admin/pos',
  `operator_id` bigint(20) DEFAULT NULL,
  `result_code` varchar(32) NOT NULL DEFAULT '0',
  `result_msg` varchar(255) DEFAULT NULL,
  `payload_json` json DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS操作审计日志';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_order`
--

CREATE TABLE `t_kds_order` (
  `order_id` int(11) NOT NULL COMMENT 't_order.id',
  `shop_id` int(11) NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `kds_order_status` tinyint(4) NOT NULL DEFAULT '10' COMMENT '10/20/30/40/90',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 整单厨显状态';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_order_projection`
--

CREATE TABLE `t_kds_order_projection` (
  `order_id` int(11) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `projection_version` bigint(20) NOT NULL,
  `state` varchar(16) NOT NULL,
  `source_channel` varchar(24) NOT NULL,
  `payload_json` longtext NOT NULL,
  `payload_hash` char(64) NOT NULL,
  `last_event_cursor` bigint(20) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='云端订单厨房完整投影';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_aggregate`
--

CREATE TABLE `t_kds_replication_aggregate` (
  `shop_id` int(11) NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `order_created_applied` tinyint(4) NOT NULL DEFAULT '0',
  `last_occurred_at_ms` bigint(20) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_order_revision` bigint(20) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Per-order replication serialization lock';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_dead_letter_audit`
--

CREATE TABLE `t_kds_replication_dead_letter_audit` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `event_id` varchar(128) NOT NULL,
  `action` varchar(20) NOT NULL COMMENT 'retry/replace/discard',
  `reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `operator_admin_id` int(11) DEFAULT NULL,
  `operator_subject` varchar(128) NOT NULL,
  `trace_id` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Auditable dead-letter operator actions';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_detail_map`
--

CREATE TABLE `t_kds_replication_detail_map` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `local_order_id` bigint(20) NOT NULL,
  `local_detail_id` bigint(20) NOT NULL,
  `cloud_order_id` int(11) NOT NULL,
  `cloud_detail_id` int(11) NOT NULL,
  `last_local_revision` bigint(20) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Cashier local detail to cloud detail mapping';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_event`
--

CREATE TABLE `t_kds_replication_event` (
  `id` bigint(20) NOT NULL,
  `event_id` varchar(128) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `event_type` varchar(40) NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `occurred_at_ms` bigint(20) NOT NULL,
  `operation_id` varchar(128) DEFAULT NULL,
  `local_revision` bigint(20) DEFAULT NULL,
  `payload_json` longtext NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'received' COMMENT 'received/pending/applied/ignored/failed',
  `result_json` longtext,
  `error_code` int(11) DEFAULT NULL,
  `error_message` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `applied_at` datetime DEFAULT NULL,
  `retry_count` int(11) NOT NULL DEFAULT '0',
  `dead_lettered_at` datetime DEFAULT NULL,
  `resolution_action` varchar(20) DEFAULT NULL,
  `resolution_reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `resolved_at` datetime DEFAULT NULL,
  `request_fingerprint` char(64) DEFAULT NULL COMMENT 'SHA-256 canonical semantic request; excludes idempotency IDs',
  `publisher_device_code` varchar(64) DEFAULT NULL COMMENT 'Authenticated X-Cashier-Device-Code'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Cashier-to-cloud durable event inbox';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_inventory_state`
--

CREATE TABLE `t_kds_replication_inventory_state` (
  `shop_id` int(11) NOT NULL,
  `dish_id` int(11) NOT NULL,
  `availability_revision` bigint(20) NOT NULL,
  `stock` int(11) DEFAULT NULL,
  `sold_out` tinyint(4) DEFAULT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Latest cashier-authoritative dish availability';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_line_state`
--

CREATE TABLE `t_kds_replication_line_state` (
  `shop_id` int(11) NOT NULL,
  `local_order_id` bigint(20) NOT NULL,
  `local_detail_id` bigint(20) NOT NULL,
  `cloud_order_id` int(11) NOT NULL,
  `cloud_detail_id` int(11) NOT NULL,
  `workflow_queue` varchar(40) DEFAULT NULL,
  `prep_remaining` int(11) DEFAULT NULL,
  `cook_remaining` int(11) DEFAULT NULL,
  `ready_remaining` int(11) DEFAULT NULL,
  `remaining_quantity` int(11) DEFAULT NULL,
  `local_revision` bigint(20) NOT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Latest cashier-authoritative KDS line projection';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_order_map`
--

CREATE TABLE `t_kds_replication_order_map` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `local_order_id` bigint(20) NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `local_order_no` varchar(100) DEFAULT NULL,
  `cloud_order_id` int(11) NOT NULL,
  `cloud_order_no` varchar(100) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Cashier local order to cloud order mapping';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_replication_order_state`
--

CREATE TABLE `t_kds_replication_order_state` (
  `shop_id` int(11) NOT NULL,
  `local_order_id` bigint(20) NOT NULL,
  `order_revision` bigint(20) NOT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Latest cashier-authoritative order snapshot';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_serve_print_job`
--

CREATE TABLE `t_kds_serve_print_job` (
  `id` bigint(20) NOT NULL,
  `job_key` varchar(160) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `detail_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `status` varchar(20) NOT NULL,
  `attempts` int(11) NOT NULL DEFAULT '0',
  `next_attempt_at` datetime DEFAULT NULL,
  `last_error` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_shop_config`
--

CREATE TABLE `t_kds_shop_config` (
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `kds_mode` varchar(16) NOT NULL DEFAULT 'print_only' COMMENT 'print_only|kds_only|both',
  `sync_legacy_rece` tinyint(4) NOT NULL DEFAULT '1' COMMENT '划菜是否回写 order_rece',
  `auto_off_order_on_kds_done` tinyint(4) NOT NULL DEFAULT '0' COMMENT '1=厨显整单完成时自动置 order_receiving=off_order（清台） 0=不联动',
  `serve_print_enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=待传菜划单后打印传菜单 0=不打印',
  `auto_push_on_create` tinyint(4) NOT NULL DEFAULT '1' COMMENT '下单即推厨显',
  `skewer_gate` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1先抓串再分流烤制屏 0直连烤制屏',
  `prep_enabled` tinyint(4) DEFAULT NULL COMMENT '1=有待配菜环节 0=跳过待配菜直进待制作 NULL=跟随skewer_gate',
  `default_screen_tag` varchar(32) DEFAULT 'meat_grill',
  `sla_minutes` int(11) NOT NULL DEFAULT '10',
  `archive_hours` int(11) NOT NULL DEFAULT '2' COMMENT '已完成归档小时数',
  `lack_sets_sold_out` tinyint(4) NOT NULL DEFAULT '0' COMMENT '缺货上报是否置 sold_out',
  `merge_same_dish` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=合并相同菜品（跨订单/跨桌汇总）',
  `pack_inline_merge` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=堂食与打包内嵌同一行；0=按渠道拆行',
  `combo_merge` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=套餐子菜与散点同菜合并；0=套餐独立成行',
  `enable_prep_workflow` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1启用待配菜环节 0跳过待配菜直接进入待制作',
  `add_dish_timeout_independent` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=加菜超时按加菜明细自身时间计算；0=跟随订单首单时间',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 门店配置';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_skewer_pick`
--

CREATE TABLE `t_kds_skewer_pick` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `dish_name` varchar(100) NOT NULL,
  `quantity_picked` int(11) NOT NULL DEFAULT '0',
  `unit` varchar(11) DEFAULT NULL,
  `picked_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 抓串已抓记录';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_station`
--

CREATE TABLE `t_kds_station` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `name` varchar(64) NOT NULL COMMENT '显示名',
  `code` varchar(32) NOT NULL COMMENT '同店唯一编码，如 MEAT',
  `screen_tag` varchar(32) NOT NULL COMMENT 'skewer_aggregate|meat_grill|veg_grill|seafood_special|expedition',
  `sort` int(11) NOT NULL DEFAULT '0',
  `enabled` tinyint(4) NOT NULL DEFAULT '1',
  `enable_prep_workflow` tinyint(4) DEFAULT NULL COMMENT '1启用待配菜环节 0跳过待配菜 NULL继承门店配置',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 档口/分屏';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_station_category`
--

CREATE TABLE `t_kds_station_category` (
  `id` bigint(20) NOT NULL,
  `station_id` bigint(20) NOT NULL,
  `cid` varchar(64) NOT NULL COMMENT 't_category 主键字符串',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 分类绑档口';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_sync_dedup`
--

CREATE TABLE `t_kds_sync_dedup` (
  `client_id` varchar(64) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 客户端幂等键';

-- --------------------------------------------------------

--
-- 表的结构 `t_kds_ticket`
--

CREATE TABLE `t_kds_ticket` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `station_id` bigint(20) NOT NULL,
  `screen_tag` varchar(32) NOT NULL,
  `order_id` int(11) NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `detail_id` int(11) NOT NULL COMMENT 't_order_detail.id',
  `item_status` tinyint(4) NOT NULL DEFAULT '0' COMMENT '0待制作 1制作中 2已完成 3已退菜',
  `skewer_picked` tinyint(4) NOT NULL DEFAULT '0' COMMENT '0待抓串 1已抓串可上烤制屏',
  `skewer_picked_at` datetime DEFAULT NULL COMMENT '抓串完成时间',
  `rush_flag` tinyint(4) NOT NULL DEFAULT '0',
  `add_dish_flag` tinyint(4) NOT NULL DEFAULT '0' COMMENT '加菜标记 0/1',
  `overdue_flag` tinyint(4) NOT NULL DEFAULT '0' COMMENT '超时标记 0/1（待做且超 SLA）',
  `overdue_at` datetime DEFAULT NULL COMMENT '首次标记超时时间',
  `rush_at` datetime DEFAULT NULL COMMENT '催菜时间',
  `order_number_snapshot` int(11) DEFAULT NULL,
  `archived` tinyint(4) NOT NULL DEFAULT '0',
  `served_quantity` int(11) NOT NULL DEFAULT '0' COMMENT '已传菜确认数量（分批出餐）',
  `prep_quantity` int(11) NOT NULL DEFAULT '0' COMMENT '已配菜数量（进入待制作池）',
  `cooked_quantity` int(11) NOT NULL DEFAULT '0' COMMENT '已制作完成数量（进入待传菜池）',
  `prep_completed_at` datetime DEFAULT NULL COMMENT '配菜完成时刻',
  `void_reason` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `accepted_at` datetime DEFAULT NULL,
  `done_at` datetime DEFAULT NULL,
  `served_at` datetime DEFAULT NULL COMMENT '传菜完成时刻',
  `archived_at` datetime DEFAULT NULL COMMENT '归档进入已完成 Tab 时刻',
  `completed_wait_seconds` int(11) DEFAULT NULL COMMENT '最近一次队列完成时的冻结等待秒数',
  `row_version` int(11) NOT NULL DEFAULT '0' COMMENT '乐观锁版本',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='KDS 厨显工单';

-- --------------------------------------------------------

--
-- 表的结构 `t_material`
--

CREATE TABLE `t_material` (
  `id` int(11) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，关联 t_shop.id；NULL=未分门店的旧数据',
  `name` varchar(64) NOT NULL COMMENT '原材料名称',
  `unit` varchar(16) NOT NULL DEFAULT '斤' COMMENT '单位',
  `stock` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '当前库存',
  `alert_threshold` decimal(12,3) DEFAULT NULL COMMENT '库存预警阈值',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='原材料库';

-- --------------------------------------------------------

--
-- 表的结构 `t_member_recharge`
--

CREATE TABLE `t_member_recharge` (
  `id` bigint(20) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 't_user.id',
  `openid` varchar(64) NOT NULL,
  `order_no` varchar(64) DEFAULT NULL COMMENT '微信充值商户单号（与 t_order 无关）；后台渠道可为空',
  `shop_id` int(11) DEFAULT NULL,
  `operator_id` int(11) DEFAULT NULL COMMENT '后台人工充值操作员ID',
  `drawer_session_id` bigint(20) DEFAULT NULL COMMENT '后台人工充值归属钱箱会话ID',
  `channel` varchar(20) NOT NULL COMMENT 'wechat | admin',
  `status` varchar(20) NOT NULL DEFAULT 'pending' COMMENT 'pending|success|cancelled',
  `recharge_amount` decimal(12,2) NOT NULL COMMENT '充值本金（元）',
  `gift_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '赠送（元）',
  `total_amount` decimal(12,2) NOT NULL COMMENT '入账合计（元）=本金+赠送',
  `transaction_id` varchar(128) DEFAULT NULL,
  `pay_time` datetime DEFAULT NULL,
  `remark` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会员充值流水';

-- --------------------------------------------------------

--
-- 表的结构 `t_notification_delivery`
--

CREATE TABLE `t_notification_delivery` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `rule_id` bigint(20) DEFAULT NULL COMMENT 't_notification_rule.id',
  `event_type` varchar(64) NOT NULL,
  `channel` varchar(16) NOT NULL COMMENT 'app/sms/printer…',
  `recipient_masked` varchar(64) DEFAULT NULL COMMENT '接收人（脱敏存储）',
  `title` varchar(255) DEFAULT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/SENT/FAILED',
  `error` varchar(500) DEFAULT NULL,
  `retry_count` int(11) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='通知发送记录';

-- --------------------------------------------------------

--
-- 表的结构 `t_notification_rule`
--

CREATE TABLE `t_notification_rule` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `name` varchar(128) NOT NULL COMMENT '规则名称',
  `event_type` varchar(64) NOT NULL COMMENT '事件类型：order_new/order_refund/stock_low/shift_close…',
  `channels_json` text COMMENT '通知渠道 JSON 数组，如 ["app","sms","printer"]',
  `recipients_json` text COMMENT '接收人 JSON 数组：[{"name":..,"phone":..,"role":..}]',
  `time_window_json` text COMMENT '生效时段 JSON：{"start":"08:00","end":"22:00","days":[1,2,3]}',
  `frequency_control_json` text COMMENT '频控 JSON：{"minIntervalMinutes":5,"dailyCap":50}',
  `enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1 启用 0 停用',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='通知规则';

-- --------------------------------------------------------

--
-- 表的结构 `t_operation_log`
--

CREATE TABLE `t_operation_log` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，审计隔离',
  `module` varchar(32) NOT NULL COMMENT 'order/dish/price/daily等',
  `action` varchar(64) NOT NULL COMMENT 'delete_order/change_price/un_checkout等',
  `target_id` varchar(64) DEFAULT NULL COMMENT '订单号或ID',
  `admin_id` int(11) DEFAULT NULL,
  `ip` varchar(64) DEFAULT NULL,
  `request_snapshot` text COMMENT '请求关键参数',
  `source_table` varchar(50) DEFAULT NULL COMMENT '源桌号',
  `target_table` varchar(50) DEFAULT NULL COMMENT '目标桌号；非并台为空',
  `order_nos` text COMMENT '涉及订单号 JSON 数组',
  `before_state` text COMMENT '操作前桌台/订单状态 JSON',
  `after_state` text COMMENT '操作后桌台/订单状态 JSON',
  `result_status` varchar(16) DEFAULT NULL COMMENT 'SUCCESS/REJECTED/ROLLED_BACK',
  `result_code` int(11) DEFAULT NULL COMMENT '接口业务码',
  `reason` varchar(255) DEFAULT NULL COMMENT '成功说明或拒绝/回滚原因（不含敏感信息）',
  `request_key` varchar(128) DEFAULT NULL COMMENT 'Idempotency-Key/X-Request-ID/trace 标识',
  `request_fingerprint` char(64) DEFAULT NULL COMMENT '动作和桌号参数 SHA-256，用于防止幂等键误复用',
  `trace_id` varchar(128) DEFAULT NULL COMMENT '链路追踪标识',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='关键操作日志';

-- --------------------------------------------------------

--
-- 表的结构 `t_order`
--

CREATE TABLE `t_order` (
  `id` int(11) NOT NULL,
  `order_no` varchar(100) NOT NULL COMMENT '订单号',
  `master_order_no` varchar(100) DEFAULT NULL COMMENT '并台主单号：若该单作为从单被并入主单所属桌台，则记录主单号；非从单为NULL',
  `table_number` varchar(50) DEFAULT NULL COMMENT '桌号',
  `number_of_diners` int(11) DEFAULT NULL COMMENT '用餐人数',
  `sett_amount` decimal(6,2) NOT NULL COMMENT '计算总价',
  `transac_status` enum('success','unsettled','cancelled') NOT NULL COMMENT '结账状态：success/unsettled/cancelled',
  `order_receiving` enum('mis_order','rec_order','off_order','cancelled') NOT NULL COMMENT '接单状态：mis_order/rec_order/off_order/cancelled',
  `order_time` datetime NOT NULL COMMENT '下单时间',
  `dineInOrTakeOut` varchar(255) NOT NULL COMMENT '订单类型',
  `orderNumber` int(11) NOT NULL COMMENT '下单次数\r\n',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `openid` varchar(255) NOT NULL COMMENT '创建者',
  `prepay_id` varchar(255) DEFAULT NULL COMMENT 'prepay_id',
  `transaction_id` varchar(255) DEFAULT NULL,
  `pay_time` datetime DEFAULT NULL COMMENT '支付时间',
  `payment_method` varchar(255) DEFAULT NULL COMMENT '支付方式',
  `pay_amount_wechat` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '微信支付金额(元)',
  `pay_amount_alipay` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '支付宝支付金额(元)',
  `pay_amount_balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '余额支付金额(元)',
  `balance_pay_principal` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '余额支付从本金扣(元)',
  `balance_pay_gift_wallet` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '余额支付从赠送金账户扣(元)',
  `pay_amount_gift` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '赠送金支付金额(元)',
  `pay_amount_cash` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '现金支付金额(元)',
  `checkout_cash_tender` decimal(12,2) DEFAULT NULL COMMENT '结账客人付现金额(元)，可大于 pay_amount_cash',
  `checkout_change_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '找零金额(元)',
  `checkout_change_channel` varchar(16) DEFAULT NULL COMMENT '找零渠道: wechat/cash/alipay',
  `merchantId` varchar(255) DEFAULT '1',
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，关联 t_shop.id',
  order_channel varchar(20) DEFAULT NULL COMMENT '下单渠道（服务端写入，不采信客户端）：mini_program=C端小程序 / cashier=收银台 / takeout=小程序外卖 / ai=AI助手',
  order_admin_id int(11) DEFAULT NULL COMMENT '下单管理员ID（B端JWT解析，收银/后台开单记录操作人；C端/AI为NULL），关联 t_admin.id',
  cashier_id int(11) DEFAULT NULL COMMENT '当班收银员ID，关联 t_admin.id',
  `notice` int(11) DEFAULT NULL COMMENT '通知取餐',
  `pay_openid` varbinary(255) DEFAULT NULL COMMENT '支付者',
  `discount_amount` decimal(8,2) DEFAULT NULL COMMENT '优惠金额',
  `off_time` datetime DEFAULT NULL COMMENT '订单完成时间',
  `service_fee` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '新年服务费/额外服务费',
  `refund_amount` decimal(10,2) DEFAULT NULL COMMENT '累计成功退款金额（元），由微信 /order/refund/notify 退款成功(SUCCESS)回调累加'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_order_client_request`
--

CREATE TABLE `t_order_client_request` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `admin_id` int(11) DEFAULT NULL,
  `client_request_id` varchar(128) NOT NULL,
  `request_path` varchar(128) NOT NULL,
  `request_fingerprint` char(64) DEFAULT NULL COMMENT 'SHA-256 of the canonical request body',
  `status` varchar(16) NOT NULL DEFAULT 'PROCESSING',
  `response_snapshot` longtext,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收银APP写请求24小时幂等账本' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_order_detail`
--

CREATE TABLE `t_order_detail` (
  `id` int(11) NOT NULL COMMENT '编号',
  `mId` int(11) DEFAULT NULL COMMENT '订单主表ID',
  `name` varchar(100) DEFAULT NULL COMMENT '菜品名称',
  `quantity` int(11) DEFAULT NULL COMMENT '数量',
  `refunded_quantity` int(11) NOT NULL DEFAULT '0' COMMENT 'Cumulative refunded quantity',
  `unit` varchar(11) DEFAULT NULL COMMENT '单位',
  `image` varchar(100) DEFAULT NULL COMMENT '菜品图片',
  `total_price` decimal(6,2) DEFAULT NULL COMMENT '总价',
  `Morder_no` varchar(100) DEFAULT NULL,
  `Morder_num` int(11) DEFAULT NULL,
  `order_rece` varchar(255) DEFAULT NULL,
  `line_status` varchar(16) NOT NULL DEFAULT 'normal' COMMENT 'normal|refunded',
  `remark` varchar(255) DEFAULT NULL,
  `selectedSpicy` varchar(255) DEFAULT NULL,
  `cid` varchar(255) DEFAULT NULL,
  `client_line_id` varchar(64) DEFAULT NULL COMMENT 'Cashier client line correlation ID',
  `dish_id` int(11) DEFAULT NULL COMMENT 't_dish.id，下单时写入；历史数据按 name 回填',
  `line_type` varchar(20) DEFAULT NULL COMMENT 'normal/combo_header/combo_component',
  `combo_id` bigint(20) DEFAULT NULL COMMENT 't_combo.id',
  `combo_instance_id` varchar(40) DEFAULT NULL COMMENT '同一单同一套餐实例 UUID',
  `parent_detail_id` int(11) DEFAULT NULL COMMENT 'combo 子行指向头行 t_order_detail.id',
  `combo_selection_json` varchar(2000) DEFAULT NULL COMMENT '套餐头行：用户选择(JSON)，便于复算与客服'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_order_log`
--

CREATE TABLE `t_order_log` (
  `id` bigint(20) NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '冗余门店，便于按店筛选',
  `action` varchar(32) NOT NULL COMMENT 'create/add_dish/refund/change_price/checkout/cancel等',
  `operator_type` varchar(16) DEFAULT NULL COMMENT 'openid/admin_id',
  `operator_id` varchar(64) DEFAULT NULL COMMENT 'openid 或 admin_id',
  `remark` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单操作日志';

-- --------------------------------------------------------

--
-- 表的结构 `t_parking_plate`
--

CREATE TABLE `t_parking_plate` (
  `id` bigint(20) UNSIGNED NOT NULL COMMENT '记录唯一ID（主键）',
  `plate_number` varchar(20) NOT NULL COMMENT '完整车牌号（如：粤A12345）',
  `plate_type` tinyint(4) NOT NULL COMMENT '车牌类型 1-燃油车 2-新能源车',
  `user_id` int(11) NOT NULL COMMENT '关联用户ID（外键，用户删除时同步删除车牌）',
  `province` varchar(10) NOT NULL COMMENT '车牌省份（如：粤）',
  `is_default` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否默认车牌 0-否 1-是',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `is_delete` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否删除 0-未删 1-已删'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='车牌信息表（用户-车牌关联）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_payment`
--

CREATE TABLE `t_payment` (
  `id` bigint(20) NOT NULL,
  `order_no` varchar(100) NOT NULL COMMENT '订单号',
  `payment_method` varchar(32) NOT NULL COMMENT '支付方式',
  `amount` decimal(10,2) NOT NULL COMMENT '支付金额',
  `transaction_id` varchar(64) DEFAULT NULL COMMENT '第三方交易号',
  `pay_time` datetime DEFAULT NULL COMMENT '支付时间',
  `operator_id` int(11) DEFAULT NULL COMMENT '收银员/操作员 admin_id',
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，可选',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付记录（对账用）';

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_capability`
--

CREATE TABLE `t_payment_capability` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL DEFAULT '0' COMMENT '0=全门店默认',
  `online_pay_enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '线上支付总开关（微信/支付宝/余额）',
  `wechat_enabled` tinyint(4) NOT NULL DEFAULT '1',
  `alipay_enabled` tinyint(4) NOT NULL DEFAULT '0' COMMENT '支付宝官方支付，P3 启用',
  `balance_enabled` tinyint(4) NOT NULL DEFAULT '1',
  `combined_enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '线上组合支付开关',
  `cashier_pay_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端支付总开关',
  `cashier_wechat_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端微信支付',
  `cashier_alipay_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端支付宝支付',
  `cashier_balance_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端余额支付',
  `cashier_combined_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端组合支付',
  `mini_program_pay_enabled` tinyint(4) DEFAULT NULL COMMENT '微信小程序端支付总开关',
  `mini_program_wechat_enabled` tinyint(4) DEFAULT NULL COMMENT '微信小程序端微信支付',
  `mini_program_balance_enabled` tinyint(4) DEFAULT NULL COMMENT '微信小程序端余额支付',
  `mini_program_alipay_enabled` tinyint(4) DEFAULT NULL COMMENT '微信小程序端支付宝支付',
  `offline_collect_enabled` tinyint(4) NOT NULL DEFAULT '1',
  `offline_collect_channels` varchar(32) NOT NULL DEFAULT 'wechat,alipay',
  `cashier_wechat_qr_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端微信收款码独立开关',
  `cashier_alipay_qr_enabled` tinyint(4) DEFAULT NULL COMMENT '收银端支付宝收款码独立开关',
  `disabled_message` varchar(255) NOT NULL DEFAULT '请联系服务员结账',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店支付能力开关';

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_merchant_config`
--

CREATE TABLE `t_payment_merchant_config` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL DEFAULT '0' COMMENT '0=全门店默认，>0=t_shop.id',
  `channel` varchar(16) NOT NULL COMMENT 'wechat|alipay',
  `merchant_key` varchar(32) NOT NULL COMMENT '实例键，如 default、small_amount',
  `enabled` tinyint(4) NOT NULL DEFAULT '1',
  `app_id` varchar(64) DEFAULT NULL,
  `mch_id` varchar(32) DEFAULT NULL COMMENT '微信商户号或支付宝 PID',
  `notify_url` varchar(512) DEFAULT NULL,
  `refund_notify_url` varchar(512) DEFAULT NULL,
  `api_v3_key_enc` varchar(512) DEFAULT NULL COMMENT '微信 APIv3 密钥（加密或 plain: 前缀）',
  `serial_no` varchar(64) DEFAULT NULL,
  `platform_pub_key_id` varchar(128) DEFAULT NULL COMMENT '微信 Wechatpay-Serial 公钥 ID',
  `platform_pub_key_ref` varchar(512) DEFAULT NULL COMMENT '微信官方平台公钥 PEM 或 classpath:/pub_key.pem',
  `private_key_ref` varchar(512) DEFAULT NULL COMMENT '商户私钥 PEM 密文或 classpath:/path',
  `alipay_app_cert_ref` varchar(512) DEFAULT NULL,
  `alipay_public_cert_ref` varchar(512) DEFAULT NULL,
  `alipay_root_cert_ref` varchar(512) DEFAULT NULL,
  `routing_rule_json` json DEFAULT NULL COMMENT '商户路由规则',
  `sort_order` int(11) NOT NULL DEFAULT '0',
  `remark` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付商户配置（连锁按 shop_id 覆盖）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_method`
--

CREATE TABLE `t_payment_method` (
  `id` int(11) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT 'NULL=全局；非空=仅该门店',
  `code` varchar(32) NOT NULL COMMENT '编码：wechat/alipay/cash/member_card/charge_account',
  `name` varchar(32) NOT NULL COMMENT '显示名称',
  `sort_order` int(11) DEFAULT '0',
  `enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '0-禁用 1-启用'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付方式';

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_ninefold_config`
--

CREATE TABLE `t_payment_ninefold_config` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL DEFAULT '0' COMMENT '0=全店默认',
  `enabled` tinyint(4) NOT NULL DEFAULT '0' COMMENT '夜间九折独立开关',
  `pay_rate` decimal(5,4) NOT NULL DEFAULT '0.9000' COMMENT '实付倍率，0.9=九折',
  `min_base_yuan` decimal(10,2) NOT NULL DEFAULT '60.00' COMMENT '券后满额(元)才叠九折',
  `time_start` varchar(8) NOT NULL DEFAULT '00:30',
  `time_end` varchar(8) NOT NULL DEFAULT '03:00',
  `zone_id` varchar(64) NOT NULL DEFAULT 'Asia/Shanghai',
  `eligible_dining_types` varchar(256) NOT NULL DEFAULT '["堂食"]',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店夜间九折配置';

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_refund_guard`
--

CREATE TABLE `t_payment_refund_guard` (
  `shop_id` int(11) NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `idempotency_key` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_refund_request`
--

CREATE TABLE `t_payment_refund_request` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `idempotency_key` varchar(64) NOT NULL,
  `out_refund_no` varchar(64) NOT NULL,
  `requested_fen` int(11) NOT NULL,
  `merchant_config_id` bigint(20) DEFAULT NULL COMMENT '发起退款时绑定的支付商户配置ID',
  `merchant_config_version` int(11) DEFAULT NULL COMMENT '发起退款时绑定的支付商户配置版本',
  `expected_transaction_id` varchar(64) DEFAULT NULL COMMENT '原微信支付交易号',
  `expected_mch_id` varchar(32) DEFAULT NULL COMMENT '退款申请绑定的微信商户号',
  `applied_fen` int(11) NOT NULL DEFAULT '0',
  `status` varchar(24) NOT NULL DEFAULT 'REQUESTED',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- 表的结构 `t_payment_test_txn`
--

CREATE TABLE `t_payment_test_txn` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL,
  `channel_code` varchar(32) NOT NULL COMMENT '渠道 code（PaymentChannelCatalog）',
  `amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '测试金额（元）',
  `terminal` varchar(64) DEFAULT NULL COMMENT '终端标识',
  `idempotency_key` varchar(64) NOT NULL COMMENT '幂等键（客户端生成）',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/DONE/FAILED',
  `charge_status` varchar(32) DEFAULT NULL COMMENT 'READINESS_OK/OFFLINE_NO_MONEY_MOVEMENT/FAILED',
  `refund_status` varchar(32) DEFAULT NULL COMMENT 'NOT_REQUIRED（未发生资金动作）',
  `error` varchar(500) DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付渠道测试交易';

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

-- --------------------------------------------------------

--
-- 表的结构 `t_personal_payment_event`
--

CREATE TABLE `t_personal_payment_event` (
  `id` bigint(20) NOT NULL COMMENT '自增主键',
  `event_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '客户端/App 唯一事件 ID（幂等主键）',
  `channel` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '收款渠道（alipay / wechat）',
  `amount_fen` bigint(20) NOT NULL COMMENT '到账金额（分）',
  `amount_yuan` decimal(10,2) NOT NULL COMMENT '到账金额（元）',
  `timestamp_raw` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '原始时间戳',
  `raw_text` text COLLATE utf8mb4_unicode_ci COMMENT '原始到账通知文本内容',
  `matched_shop_id` int(11) DEFAULT NULL COMMENT '自动匹配到的门店 ID',
  `matched_order_no` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '自动匹配到的订单号',
  `status` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'PROCESSED' COMMENT '处理状态（PROCESSED已处理，MATCHED已核销，UNMATCHED未匹配）',
  `remark` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '处理结果与备注',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='个人收款 App 异步通知事件流水表';

-- --------------------------------------------------------

--
-- 表的结构 `t_printing_device`
--

CREATE TABLE `t_printing_device` (
  `id` bigint(20) NOT NULL COMMENT '设备 ID',
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id，门店隔离维度',
  `name` varchar(128) NOT NULL COMMENT '设备名称',
  `transport` varchar(20) NOT NULL COMMENT '连接方式：LAN/USB/BLUETOOTH/CLOUD',
  `brand` varchar(64) DEFAULT NULL COMMENT '品牌/型号，如 飞鹅/佳博/芯烨',
  `connection_json` text COMMENT '连接参数 JSON（IP/端口/序列号sn/密钥key等；接口读取时密钥与序列号脱敏）',
  `status` varchar(20) NOT NULL DEFAULT 'UNKNOWN' COMMENT '运行状态：ONLINE/OFFLINE/UNKNOWN',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本，从 1 起',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='打印设备';

-- --------------------------------------------------------

--
-- 表的结构 `t_printing_job`
--

CREATE TABLE `t_printing_job` (
  `id` bigint(20) NOT NULL COMMENT '任务 ID',
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id，门店隔离维度',
  `device_id` bigint(20) DEFAULT NULL COMMENT 't_printing_device.id',
  `job_type` varchar(32) NOT NULL COMMENT '单据类型：order/kitchen/refund/shift/test…',
  `status` varchar(20) NOT NULL DEFAULT 'PENDING_DEVICE' COMMENT '状态：PENDING_DEVICE/SENT/PRINTED/FAILED/CANCELED',
  `payload_text` longtext COMMENT '打印内容文本',
  `error` varchar(500) DEFAULT NULL COMMENT '失败原因',
  `retry_count` int(11) NOT NULL DEFAULT '0' COMMENT '已重试次数（仅记录，本模块不提供远程重试入口）',
  `executor` varchar(10) NOT NULL COMMENT '执行方：CLOUD（服务端走飞鹅云）/DEVICE（端侧本地执行）',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `biz_type` varchar(20) DEFAULT NULL COMMENT '业务类型：kds_serve（KDS 划菜）等',
  `biz_id` bigint(20) DEFAULT NULL COMMENT '业务主键：如 t_order_detail.id'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='打印任务记录';

-- --------------------------------------------------------

--
-- 表的结构 `t_printing_rule`
--

CREATE TABLE `t_printing_rule` (
  `id` bigint(20) NOT NULL COMMENT '规则 ID',
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id，门店隔离维度',
  `scenario` varchar(32) NOT NULL COMMENT '打印场景：order/kitchen/refund/shift…',
  `device_id` bigint(20) DEFAULT NULL COMMENT 't_printing_device.id，为空则暂不指派设备',
  `template_code` varchar(64) DEFAULT NULL COMMENT '打印模板编码，映射品牌适配器',
  `copies` int(11) NOT NULL DEFAULT '1' COMMENT '打印份数，1-9',
  `enabled` tinyint(4) NOT NULL DEFAULT '1' COMMENT '是否启用：1 启用 / 0 停用',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本（门店规则集整体版本 = 本店各行最大值）',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='打印规则';

-- --------------------------------------------------------

--
-- 表的结构 `t_printing_template`
--

CREATE TABLE `t_printing_template` (
  `id` bigint(20) NOT NULL COMMENT '模板 ID',
  `shop_id` int(11) NOT NULL DEFAULT '0' COMMENT '门店 ID（0 表示总部系统内置通用模板，>0 为门店自定义模板）',
  `template_code` varchar(64) NOT NULL COMMENT '模板唯一标识编码',
  `template_name` varchar(128) NOT NULL COMMENT '模板名称（如：默认前台结账单、精简后厨单）',
  `scenario` varchar(32) NOT NULL COMMENT '适用场景：ORDER/KITCHEN/SERVE/REFUND/SHIFT/LABEL/TEST',
  `paper_size` varchar(16) NOT NULL DEFAULT '58mm' COMMENT '纸张规格：58mm / 80mm',
  `is_system` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否系统内置模板：1 是（只读/支持克隆），0 否（自定义）',
  `is_default` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否场景默认模板：1 是，0 否',
  `template_json` longtext NOT NULL COMMENT '模板排版设计 JSON 配置（包含 blocks 列表、样式属性及字段开关）',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本号',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='打印小票排版模板配置表';

-- --------------------------------------------------------

--
-- 表的结构 `t_queue_ticket`
--

CREATE TABLE `t_queue_ticket` (
  `id` bigint(20) NOT NULL,
  `ticket_no` varchar(32) NOT NULL COMMENT '排队号，如 A102',
  `shop_id` int(11) NOT NULL DEFAULT '1' COMMENT '门店ID，连锁按门店隔离',
  `openid` varchar(100) NOT NULL COMMENT '用户 openid',
  `mobile` varchar(20) NOT NULL COMMENT '手机号',
  `party_size` int(11) NOT NULL COMMENT '就餐人数',
  `dine_type` varchar(32) NOT NULL COMMENT '就餐方式，如 dinein',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `status` enum('waiting','calling','seated','cancelled','expired') NOT NULL DEFAULT 'waiting' COMMENT '排队状态',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='排队取号记录' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_region`
--

CREATE TABLE `t_region` (
  `id` int(11) NOT NULL,
  `code` varchar(32) NOT NULL COMMENT '区域编码（唯一）',
  `name` varchar(64) NOT NULL COMMENT '区域名称',
  `parent_id` int(11) DEFAULT NULL COMMENT '父区域ID，可空'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='区域主数据';

-- --------------------------------------------------------

--
-- 表的结构 `t_report_export_job`
--

CREATE TABLE `t_report_export_job` (
  `id` bigint(20) NOT NULL COMMENT '任务ID',
  `shop_id` int(11) NOT NULL COMMENT '门店ID t_shop.id（隔离维度）',
  `job_type` varchar(32) NOT NULL COMMENT '任务类型：REPORT_EXPORT/LOG_EXPORT/ARCHIVE_SEARCH',
  `report_type` varchar(64) DEFAULT NULL COMMENT '报表类型：daily/weekly/monthly；日志类任务为 log',
  `filters_json` text COMMENT '筛选条件 JSON（报表 filters / 日志查询条件 + purpose）',
  `format` varchar(16) NOT NULL DEFAULT 'csv' COMMENT '导出格式：csv/xlsx（当前实现仅 csv）',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT '状态：PENDING/RUNNING/DONE/FAILED',
  `file_name` varchar(255) DEFAULT NULL COMMENT '生成文件名（服务端 ./data/exports 目录下）',
  `download_token` varchar(64) DEFAULT NULL COMMENT '32 位随机下载令牌（完成时生成）',
  `token_expires_at` datetime DEFAULT NULL COMMENT '下载令牌过期时间（生成后 15 分钟）',
  `result_summary_json` text COMMENT '结果摘要 JSON（归档查询存命中数/窗口/提示）',
  `error` varchar(512) DEFAULT NULL COMMENT '失败原因或过期提示（如 download link expired）',
  `created_by` int(11) DEFAULT NULL COMMENT '创建管理员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='报表/日志导出与归档检索任务';

-- --------------------------------------------------------

--
-- 表的结构 `t_role`
--

CREATE TABLE `t_role` (
  `id` int(11) NOT NULL,
  `role_code` varchar(32) NOT NULL COMMENT '角色编码，如 super_admin, order_manager',
  `role_name` varchar(64) NOT NULL COMMENT '角色名称',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `sort_order` int(11) DEFAULT '0' COMMENT '排序',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色表';

-- --------------------------------------------------------

--
-- 表的结构 `t_role_permission`
--

CREATE TABLE `t_role_permission` (
  `id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `permission_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='角色-权限关联' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_shift`
--

CREATE TABLE `t_shift` (
  `id` bigint(20) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT '收银员',
  `shop_id` int(11) DEFAULT NULL,
  `start_time` datetime NOT NULL COMMENT '班次开始',
  `end_time` datetime DEFAULT NULL COMMENT '班次结束',
  `start_cash` decimal(10,2) DEFAULT '0.00' COMMENT '开班现金',
  `end_cash` decimal(10,2) DEFAULT NULL COMMENT '交班现金',
  `order_count` int(11) DEFAULT '0',
  `total_amount` decimal(12,2) DEFAULT '0.00',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收银员交班';

-- --------------------------------------------------------

--
-- 表的结构 `t_shop`
--

CREATE TABLE `t_shop` (
  `id` int(11) NOT NULL,
  `name` varchar(64) NOT NULL COMMENT '门店名称',
  `code` varchar(32) DEFAULT NULL COMMENT '门店编码',
  `region_id` int(11) DEFAULT NULL COMMENT '区域ID，关联 t_region.id',
  `address` varchar(255) DEFAULT NULL COMMENT '地址',
  `latitude` decimal(10,7) DEFAULT NULL COMMENT '纬度',
  `longitude` decimal(10,7) DEFAULT NULL COMMENT '经度',
  `contact_phone` varchar(20) DEFAULT NULL COMMENT '联系电话',
  `open_time` time DEFAULT NULL COMMENT '营业开始时间',
  `close_time` time DEFAULT NULL COMMENT '营业结束时间',
  `settle_time` varchar(8) DEFAULT '04:00' COMMENT '每日结算截止时间(HH:mm)，营业日统计窗口=[open_time,次日settle_time)',
  `status` tinyint(4) NOT NULL DEFAULT '1' COMMENT '状态：0-停用 1-营业',
  `sort_order` int(11) NOT NULL DEFAULT '0' COMMENT '列表排序，越小越靠前',
  `ordering_open` tinyint(4) NOT NULL DEFAULT '1' COMMENT 'C端接单营业：1营业 0休息',
  `ordering_review` tinyint(4) NOT NULL DEFAULT '0' COMMENT 'C端评价展示：1开 0关',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `offline_collect_wechat_payload` varchar(2048) DEFAULT NULL COMMENT '微信个人收款码解码后的跳转串（如 wxp://）',
  `offline_collect_alipay_payload` varchar(2048) DEFAULT NULL COMMENT '支付宝收款码解码后的跳转串',
  `offline_collect_wechat_image_path` varchar(512) DEFAULT NULL COMMENT '上传的微信收款码图片相对/绝对路径（可选备份）',
  `offline_collect_alipay_image_path` varchar(512) DEFAULT NULL COMMENT '上传的支付宝收款码图片路径',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店表（多店）';

-- --------------------------------------------------------

--
-- [v1.2.223] 表 `t_shop_printer_config` 已移除：打印设备参数统一以 `t_printing_device.connection_json` 为准（门店/全局飞鹅配置不再使用）
--

-- --------------------------------------------------------

--
-- 表的结构 `t_shop_settings`
--

CREATE TABLE `t_shop_settings` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `module` varchar(64) NOT NULL COMMENT '模块标识',
  `payload_json` longtext COMMENT '覆盖配置 JSON（仅存被覆盖字段）',
  `version` int(11) NOT NULL DEFAULT '1' COMMENT '乐观锁版本',
  `updated_by` int(11) DEFAULT NULL COMMENT '最后更新管理员',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店设置覆盖';

-- --------------------------------------------------------

--
-- 表的结构 `t_shop_takeout_config`
--

CREATE TABLE `t_shop_takeout_config` (
  `shop_id` int(11) NOT NULL COMMENT 't_shop.id',
  `enabled` tinyint(4) NOT NULL DEFAULT '0' COMMENT '1=开启外卖',
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '基础配送费（元）',
  `min_order_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '起送价（元，按商品小计不含配送费）',
  `free_delivery_threshold` decimal(10,2) DEFAULT NULL COMMENT '满额免配送费；NULL 表示不免',
  `max_delivery_distance_km` decimal(5,2) NOT NULL DEFAULT '5.00' COMMENT '最远配送距离(公里)，超出不可下单',
  `free_delivery_max_distance_km` decimal(5,2) NOT NULL DEFAULT '5.00' COMMENT '满额免配送费的最远距离(公里)',
  `delivery_fee_tiers_json` text COMMENT '距离阶梯运费 JSON，如 [{"toKm":3,"fee":5},{"toKm":4,"fee":8},{"toKm":5,"fee":10}]',
  `lead_time_minutes` int(11) NOT NULL DEFAULT '30' COMMENT '预计备餐分钟（展示用）',
  `remark` varchar(500) DEFAULT NULL COMMENT '对外说明',
  `zsq_enabled` tinyint(4) NOT NULL DEFAULT '0' COMMENT '1=启用真省钱聚合配送',
  `zsq_auto_dispatch` tinyint(4) NOT NULL DEFAULT '1' COMMENT '1=商家接单后自动发真省钱配送',
  `zsq_from_address_id` bigint(20) DEFAULT NULL COMMENT '真省钱发单店铺 id，空则用默认店铺',
  `zsq_city_name` varchar(64) DEFAULT NULL COMMENT '地址解析城市，空则取门店城市或江门市',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='门店外卖配置';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_in`
--

CREATE TABLE `t_stock_in` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID',
  `material_id` int(11) NOT NULL,
  `quantity` decimal(12,3) NOT NULL COMMENT '入库数量',
  `price` decimal(10,2) DEFAULT NULL COMMENT '单价（成本）',
  `total_amount` decimal(12,2) DEFAULT NULL COMMENT '总金额',
  `remark` varchar(255) DEFAULT NULL,
  `operator_id` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='原材料入库';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_out`
--

CREATE TABLE `t_stock_out` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID',
  `material_id` int(11) NOT NULL,
  `quantity` decimal(12,3) NOT NULL COMMENT '出库数量',
  `reason` varchar(32) DEFAULT NULL COMMENT '原因：consume/transfer/waste',
  `remark` varchar(255) DEFAULT NULL,
  `operator_id` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='原材料出库/消耗';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_prepare_plan`
--

CREATE TABLE `t_stock_prepare_plan` (
  `id` bigint(20) NOT NULL COMMENT '备货计划ID',
  `shop_id` int(11) NOT NULL COMMENT '门店ID',
  `run_id` bigint(20) NOT NULL COMMENT '预测批次ID(t_stock_prep_forecast_run.id)',
  `prepare_date` date NOT NULL COMMENT '备货日期(与预测 stat_date 对齐)',
  `material_id` int(11) NOT NULL COMMENT '原材料ID',
  `current_stock` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '生成时 t_material.stock 快照',
  `forecast_consume` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '预测消耗总量',
  `safe_stock` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '安全库存',
  `suggest_qty` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '系统建议备货量',
  `manual_adjust` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '人工调整量(±)',
  `final_qty` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '最终确认备货量',
  `status` tinyint(4) NOT NULL DEFAULT '0' COMMENT '0待确认 1已确认 2已采购 3已入库',
  `operator_id` int(11) DEFAULT NULL COMMENT '操作员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='原材料备货计划表';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_prep_config`
--

CREATE TABLE `t_stock_prep_config` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) NOT NULL COMMENT '门店ID',
  `safe_stock_rate` decimal(5,2) NOT NULL DEFAULT '0.10' COMMENT '安全库存系数',
  `default_loss_rate` decimal(5,2) NOT NULL DEFAULT '0.05' COMMENT 'BOM未填损耗时的默认损耗率',
  `forecast_days` int(11) NOT NULL DEFAULT '3' COMMENT '默认预测天数',
  `history_days` int(11) NOT NULL DEFAULT '30' COMMENT '默认回溯天数',
  `weather_factor` decimal(5,2) NOT NULL DEFAULT '1.00' COMMENT '天气修正上限参考/扩展用',
  `holiday_factor` decimal(5,2) NOT NULL DEFAULT '1.20' COMMENT '节假日参考系数/扩展用',
  `member_factor` decimal(5,2) NOT NULL DEFAULT '1.00' COMMENT '会员客流热度系数(充值不计销量，仅乘在预测上)',
  `is_enabled` tinyint(4) NOT NULL DEFAULT '1',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='备货规则配置表(按店)';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_prep_forecast_day`
--

CREATE TABLE `t_stock_prep_forecast_day` (
  `id` bigint(20) NOT NULL,
  `run_id` bigint(20) NOT NULL COMMENT '批次ID',
  `stat_date` date NOT NULL COMMENT '预测自然日',
  `iso_day_of_week` tinyint(4) NOT NULL COMMENT '周一=1…周日=7',
  `day_kind` varchar(64) NOT NULL COMMENT '工作日/周末/调休工作日(含补班说明)等',
  `is_holiday` tinyint(4) NOT NULL DEFAULT '0' COMMENT '是否按法定节假日休息并施加节假日系数',
  `holiday_name` varchar(64) DEFAULT NULL COMMENT '节假日名称或自定义',
  `factor_holiday` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `factor_weather` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `factor_composite` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `weather_available` tinyint(4) NOT NULL DEFAULT '0',
  `weather_summary` varchar(256) DEFAULT NULL,
  `weather_code` int(11) DEFAULT NULL,
  `weather_precip_prob` int(11) DEFAULT NULL COMMENT '降水概率max %',
  `weather_temp_max` decimal(5,1) DEFAULT NULL COMMENT '预报最高温℃',
  `predicted_servings_sum` int(11) DEFAULT NULL COMMENT '本批次当日预测菜品份数合计(预测范围内)',
  `actual_servings_forecast_dishes` int(11) DEFAULT NULL COMMENT '预测范围内菜品当日实际份数合计',
  `actual_servings_all_dishes` int(11) DEFAULT NULL COMMENT '当日全店订单明细销量合计(所有菜品)',
  `actual_order_count` int(11) DEFAULT NULL COMMENT '当日成功单数',
  `daily_stat_total_amount` decimal(12,2) DEFAULT NULL COMMENT '日结表营业额 t_daily_stat.total_amount',
  `daily_stat_discount_amount` decimal(12,2) DEFAULT NULL COMMENT '日结优惠合计',
  `daily_stat_refund_amount` decimal(12,2) DEFAULT NULL COMMENT '日结退款合计',
  `daily_stat_material_cost` decimal(12,2) DEFAULT NULL COMMENT '日结原料成本',
  `daily_stat_settled` tinyint(4) DEFAULT NULL COMMENT '1=日结已 settled_at 非空',
  `day_validated_at` datetime DEFAULT NULL COMMENT '该预测日本行校验完成时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='备货预测-按日';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_prep_forecast_dish`
--

CREATE TABLE `t_stock_prep_forecast_dish` (
  `id` bigint(20) NOT NULL,
  `run_id` bigint(20) NOT NULL,
  `stat_date` date NOT NULL,
  `dish_id` int(11) DEFAULT NULL COMMENT '匹配 t_dish.id，可能为空',
  `dish_name` varchar(100) NOT NULL,
  `baseline_avg` decimal(14,4) NOT NULL DEFAULT '0.0000' COMMENT '该日星期几基线日均份数',
  `predicted_servings` int(11) NOT NULL DEFAULT '0' COMMENT '预测备货份数',
  `actual_quantity` int(11) DEFAULT NULL COMMENT '当日该菜品实际销量(订单明细汇总)',
  `validated_at` datetime DEFAULT NULL COMMENT '写入实际销量的时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='备货预测-按日按菜';

-- --------------------------------------------------------

--
-- 表的结构 `t_stock_prep_forecast_run`
--

CREATE TABLE `t_stock_prep_forecast_run` (
  `id` bigint(20) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID，与订单统计一致；NULL 表示未按店过滤的汇总',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '生成时间',
  `history_days` int(11) NOT NULL COMMENT '回溯天数',
  `forecast_days` int(11) NOT NULL COMMENT '预测天数',
  `history_start_date` date NOT NULL COMMENT '历史统计起始日',
  `history_end_at` datetime NOT NULL COMMENT '历史统计结束时刻',
  `model_notes` varchar(500) DEFAULT NULL COMMENT '模型说明',
  `last_validated_at` datetime DEFAULT NULL COMMENT '最近一次校验写入时间'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='备货预测运行批次';

-- --------------------------------------------------------

--
-- 表的结构 `t_system_config`
--

CREATE TABLE `t_system_config` (
  `id` int(11) NOT NULL,
  `shop_id` int(11) NOT NULL DEFAULT '0' COMMENT '0=全门店默认，>0=t_shop.id',
  `config_key` varchar(100) NOT NULL COMMENT '配置键，如 feieyun.user、invite.poster.qr.x',
  `config_value` varchar(500) DEFAULT NULL COMMENT '配置值',
  `remark` varchar(255) DEFAULT NULL COMMENT '说明'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='系统配置（持久化 application.yml 覆盖项）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_table`
--

CREATE TABLE `t_table` (
  `id` int(11) NOT NULL,
  `shop_id` int(11) DEFAULT NULL COMMENT '门店ID；NULL 表示未迁移的历史数据',
  `number` varchar(20) DEFAULT NULL COMMENT '桌号',
  `open_time` datetime DEFAULT NULL COMMENT '开台时间',
  `qrcode` varchar(100) DEFAULT NULL COMMENT '二维码',
  `status` int(1) UNSIGNED ZEROFILL NOT NULL,
  `out_time` datetime DEFAULT NULL COMMENT '结账时间',
  `amount` decimal(6,2) DEFAULT NULL COMMENT '金额',
  `order_no` varchar(22) DEFAULT NULL COMMENT '订单号'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_takeout_delivery`
--

CREATE TABLE `t_takeout_delivery` (
  `id` bigint(20) NOT NULL,
  `order_id` int(11) NOT NULL COMMENT 't_order.id',
  `order_no` varchar(32) NOT NULL,
  `shop_id` int(11) DEFAULT NULL,
  `user_address_id` bigint(20) DEFAULT NULL COMMENT '下单时选用的 t_user_address.id',
  `receiver_name` varchar(32) DEFAULT NULL,
  `receiver_phone` varchar(20) NOT NULL,
  `address_full` varchar(512) NOT NULL,
  `lng` decimal(10,6) DEFAULT NULL,
  `lat` decimal(10,6) DEFAULT NULL,
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT '0.00',
  `dispatch_status` varchar(24) NOT NULL DEFAULT 'submitted' COMMENT 'submitted|paid|accepted|delivering|completed|cancelled',
  `merchant_remark` varchar(500) DEFAULT NULL,
  `zsq_open_order_id` bigint(20) DEFAULT NULL COMMENT '真省钱 openOrderId（ZsqCreateOrderResult.id）',
  `zsq_order_id` varchar(64) DEFAULT NULL COMMENT '真省钱业务订单号',
  `zsq_shop_number` varchar(32) DEFAULT NULL COMMENT '真省钱发单店铺编号',
  `zsq_parent_order_no` varchar(64) DEFAULT NULL COMMENT '真省钱配送母单号',
  `zsq_delivery_codes_json` varchar(256) DEFAULT NULL COMMENT '已选配送渠道 deliveryCode JSON 数组',
  `zsq_quote_json` text COMMENT '最近一次询价快照 JSON',
  `zsq_dispatch_json` text COMMENT '最近一次发配送响应 JSON',
  `zsq_delivery_send_status` int(11) DEFAULT NULL COMMENT '真省钱 deliverySendStatus 原始值',
  `zsq_phase` varchar(32) DEFAULT NULL COMMENT '归一化阶段 WAITING_RIDER/TO_SHOP/TO_USER/DELIVERED/CANCELLED',
  `zsq_dispatch_status` varchar(32) NOT NULL DEFAULT 'none' COMMENT 'none|pending|dispatched|failed|rider_cancelled|completed',
  `zsq_rider_name` varchar(64) DEFAULT NULL,
  `zsq_rider_phone` varchar(32) DEFAULT NULL,
  `zsq_rider_lat` decimal(10,6) DEFAULT NULL,
  `zsq_rider_lng` decimal(10,6) DEFAULT NULL,
  `zsq_rider_updated_at` datetime DEFAULT NULL,
  `zsq_last_error` varchar(512) DEFAULT NULL COMMENT '最近一次 ZSQ 错误文案',
  `zsq_dispatch_attempts` int(11) NOT NULL DEFAULT '0' COMMENT '发配送尝试次数（含重发）',
  `zsq_liability_fee` decimal(10,2) DEFAULT NULL COMMENT '真省钱取消责任扣费（元）',
  `zsq_actual_fee` decimal(10,2) DEFAULT NULL COMMENT '真省钱实际跑腿费用（元，来自 shopActualCost/discountLastMoney）',
  `zsq_delivery_supplier_name` varchar(64) DEFAULT NULL COMMENT '真省钱实际配送运力渠道（如京东特惠、美团等，来自 deliverySupplierName）',
  `zsq_cancel_prompt` varchar(512) DEFAULT NULL COMMENT '真省钱取消提示文案',
  `zsq_cancel_json` text COMMENT '真省钱取消响应 JSON',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='外卖配送扩展（与 dineInOrTakeOut=外卖 的订单绑定）';

-- --------------------------------------------------------

--
-- 表的结构 `t_unit`
--

CREATE TABLE `t_unit` (
  `id` int(11) NOT NULL,
  `label` varchar(100) DEFAULT NULL,
  `value` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_user`
--

CREATE TABLE `t_user` (
  `id` int(11) NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `openid` varchar(100) DEFAULT NULL,
  `phone` varchar(11) DEFAULT NULL,
  `points` int(11) DEFAULT NULL,
  `balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '账户余额(元)',
  `gift_balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '赠送金余额(元)，与 balance 本金分开',
  `principal_balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '本金(元)；balance=principal_balance+gift_balance',
  `session_key` varchar(255) DEFAULT NULL,
  `avatar` varchar(255) DEFAULT NULL,
  `time` datetime DEFAULT NULL COMMENT '注册时间',
  `user_type` int(11) DEFAULT NULL COMMENT '用户类型：0普通/1会员',
  `invite_code` varchar(10) DEFAULT NULL,
  `level` int(11) DEFAULT NULL COMMENT '会员等级',
  `birthday` varchar(10) DEFAULT NULL COMMENT '生日'
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_user_activity_interaction`
--

CREATE TABLE `t_user_activity_interaction` (
  `id` int(11) NOT NULL,
  `user_id` varchar(255) DEFAULT NULL COMMENT '用户ID（与用户表id对应）',
  `activity_id` varchar(255) DEFAULT NULL COMMENT '活动ID（与活动表id对应）',
  `interaction_type` varchar(255) DEFAULT NULL COMMENT '交互类型：show(展示)/click(点击)/close(关闭)',
  `interaction_time` varchar(255) DEFAULT NULL COMMENT '交互时间',
  `date` datetime DEFAULT NULL COMMENT '交互日期（用于按日过滤）'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_user_address`
--

CREATE TABLE `t_user_address` (
  `id` bigint(20) NOT NULL,
  `openid` varchar(100) NOT NULL COMMENT 't_user.openid',
  `contact_name` varchar(32) DEFAULT NULL,
  `contact_phone` varchar(20) NOT NULL,
  `tag` varchar(20) DEFAULT NULL COMMENT '家/公司/学校等',
  `province` varchar(32) DEFAULT NULL,
  `city` varchar(32) DEFAULT NULL,
  `district` varchar(32) DEFAULT NULL,
  `detail_address` varchar(255) NOT NULL,
  `lng` decimal(10,6) DEFAULT NULL,
  `lat` decimal(10,6) DEFAULT NULL,
  `is_default` tinyint(4) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='小程序用户收货地址';

-- --------------------------------------------------------

--
-- 表的结构 `t_user_coupon`
--

CREATE TABLE `t_user_coupon` (
  `id` bigint(20) NOT NULL COMMENT '主键ID',
  `user_openid` varchar(100) CHARACTER SET utf8mb4 NOT NULL COMMENT '用户微信openid',
  `coupon_id` bigint(20) NOT NULL COMMENT '关联优惠券主表ID',
  `get_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '领取时间',
  `use_time` datetime DEFAULT NULL COMMENT '使用时间（NULL为未使用）',
  `order_no` varchar(50) CHARACTER SET utf8mb4 DEFAULT NULL COMMENT '关联订单号（使用后填充）',
  `status` tinyint(4) NOT NULL DEFAULT '0' COMMENT '状态：0-未使用 1-已使用 2-已失效',
  `expire_time` datetime DEFAULT NULL COMMENT '优惠券失效时间（程序关联主表end_time填充）'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户优惠券关联表（关联优惠券主表）' ROW_FORMAT=DYNAMIC;

-- --------------------------------------------------------

--
-- 表的结构 `t_user_last_shop`
--

CREATE TABLE `t_user_last_shop` (
  `id` bigint(20) NOT NULL,
  `openid` varchar(100) NOT NULL COMMENT 't_user.openid',
  `shop_id` int(11) NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户上次选择门店';

--
-- 转储表的索引
--

--
-- 表的索引 `t_activity_popup`
--
ALTER TABLE `t_activity_popup`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `idx_time_status` (`start_time`,`end_time`,`is_enabled`) USING BTREE COMMENT '查询有效活动的索引';

--
-- 表的索引 `t_admin`
--
ALTER TABLE `t_admin`
  ADD PRIMARY KEY (`id`) USING BTREE;

--
-- 表的索引 `t_admin_region`
--
ALTER TABLE `t_admin_region`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_admin_region` (`admin_id`,`region_id`),
  ADD KEY `idx_region` (`region_id`);

--
-- 表的索引 `t_admin_role`
--
ALTER TABLE `t_admin_role`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_admin_role` (`admin_id`,`role_id`) USING BTREE,
  ADD KEY `idx_role_id` (`role_id`) USING BTREE;

--
-- 表的索引 `t_admin_shop`
--
ALTER TABLE `t_admin_shop`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_admin_shop` (`admin_id`,`shop_id`),
  ADD KEY `idx_shop` (`shop_id`);

--
-- 表的索引 `t_announcement`
--
ALTER TABLE `t_announcement`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `idx_ann_shop_status_sort` (`shop_id`,`status`,`sort_order`,`id`) USING BTREE,
  ADD KEY `idx_ann_time` (`start_time`,`end_time`) USING BTREE;

--
-- 表的索引 `t_api_permission`
--
ALTER TABLE `t_api_permission`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_path_pattern` (`path_pattern`),
  ADD KEY `idx_path_method` (`path_pattern`(100),`method`);

--
-- 表的索引 `t_app_schema_version`
--
ALTER TABLE `t_app_schema_version`
  ADD PRIMARY KEY (`version`);

--
-- 表的索引 `t_banner`
--
ALTER TABLE `t_banner`
  ADD PRIMARY KEY (`id`) USING BTREE;

--
-- 表的索引 `t_cashier_collection_intent`
--
ALTER TABLE `t_cashier_collection_intent`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_cashier_collection_order_channel` (`shop_id`,`order_no`,`channel`),
  ADD KEY `idx_cashier_collection_session` (`session_id`);

--
-- 表的索引 `t_category`
--
ALTER TABLE `t_category`
  ADD PRIMARY KEY (`id`) USING BTREE;

ALTER TABLE `t_category_shop`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_category_shop` (`shop_id`,`category_id`),
  ADD KEY `idx_category_shop_category` (`category_id`);

--
-- 表的索引 `t_combo`
--
ALTER TABLE `t_combo`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_combo_dish` (`dish_id`);

--
-- 表的索引 `t_combo_fixed_item`
--
ALTER TABLE `t_combo_fixed_item`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_combo_fixed_combo` (`combo_id`),
  ADD KEY `fk_combo_fixed_component` (`component_dish_id`);

--
-- 表的索引 `t_combo_group`
--
ALTER TABLE `t_combo_group`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_combo_group_combo` (`combo_id`);

--
-- 表的索引 `t_combo_group_item`
--
ALTER TABLE `t_combo_group_item`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_combo_gi_group` (`group_id`),
  ADD KEY `fk_combo_gi_dish` (`component_dish_id`);

--
-- 表的索引 `t_coupon`
--
ALTER TABLE `t_coupon`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `idx_coupon_type` (`coupon_type`) USING BTREE COMMENT '优惠券类型索引',
  ADD KEY `idx_status` (`status`) USING BTREE COMMENT '状态索引',
  ADD KEY `idx_time_range` (`start_time`,`end_time`) USING BTREE COMMENT '时间范围索引';

--
-- 表的索引 `t_coupon_redeem_code`
--
ALTER TABLE `t_coupon_redeem_code`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_redeem_code` (`redeem_code`) USING BTREE,
  ADD KEY `idx_coupon_id` (`coupon_id`) USING BTREE;

--
-- 表的索引 `t_daily_stat`
--
ALTER TABLE `t_daily_stat`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_date_shop` (`stat_date`,`shop_id`),
  ADD KEY `idx_stat_date` (`stat_date`);

--
-- 表的索引 `t_dish`
--
ALTER TABLE `t_dish`
  ADD PRIMARY KEY (`id`) USING BTREE;

--
-- 表的索引 `t_dish_material_bom`
--
ALTER TABLE `t_dish_material_bom`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_shop_dish_material` (`shop_id`,`dish_id`,`material_id`) USING BTREE,
  ADD KEY `idx_dish` (`dish_id`) USING BTREE,
  ADD KEY `idx_material` (`material_id`) USING BTREE,
  ADD KEY `idx_shop` (`shop_id`) USING BTREE;

--
-- 表的索引 `t_dish_shop`
--
ALTER TABLE `t_dish_shop`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_shop_dish` (`shop_id`,`dish_id`) USING BTREE,
  ADD KEY `idx_dish_shop_dish` (`dish_id`) USING BTREE;

--
-- 表的索引 `t_first_order_campaign`
--
ALTER TABLE `t_first_order_campaign`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_shop_status` (`shop_id`,`status`);

--
-- 表的索引 `t_first_order_redemption`
--
ALTER TABLE `t_first_order_redemption`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_shop_customer` (`shop_id`,`customer_id`),
  ADD KEY `idx_shop_campaign` (`shop_id`,`campaign_id`),
  ADD KEY `idx_order` (`order_id`);

--
-- 表的索引 `t_hq_settings`
--
ALTER TABLE `t_hq_settings`
  ADD PRIMARY KEY (`module`);

--
-- 表的索引 `t_inventory_batch`
--
ALTER TABLE `t_inventory_batch`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_inv_batch_shop_material_wh` (`shop_id`,`material_id`,`warehouse_id`),
  ADD KEY `idx_inv_batch_expiry` (`expiry_date`);

--
-- 表的索引 `t_inventory_bom`
--
ALTER TABLE `t_inventory_bom`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_inv_bom_shop_dish_version` (`shop_id`,`dish_id`,`version_no`),
  ADD KEY `idx_inv_bom_shop_dish_status` (`shop_id`,`dish_id`,`status`);

--
-- 表的索引 `t_inventory_purchase`
--
ALTER TABLE `t_inventory_purchase`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_inv_purchase_shop_status` (`shop_id`,`status`),
  ADD KEY `idx_inv_purchase_supplier` (`supplier_id`);

--
-- 表的索引 `t_inventory_supplier`
--
ALTER TABLE `t_inventory_supplier`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_inv_supplier_shop` (`shop_id`);

--
-- 表的索引 `t_inventory_transfer`
--
ALTER TABLE `t_inventory_transfer`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_inv_transfer_shop_status` (`shop_id`,`status`),
  ADD KEY `idx_inv_transfer_from` (`from_warehouse_id`),
  ADD KEY `idx_inv_transfer_to` (`to_warehouse_id`);

--
-- 表的索引 `t_inventory_warehouse`
--
ALTER TABLE `t_inventory_warehouse`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_inv_warehouse_shop` (`shop_id`);

--
-- 表的索引 `t_invite_record`
--
ALTER TABLE `t_invite_record`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_invite_code_invitee` (`invite_code`,`invitee_openid`) USING BTREE COMMENT '同一邀请码不能重复邀请同一被邀请人',
  ADD KEY `idx_inviter_openid` (`inviter_openid`) USING BTREE COMMENT '邀请者openid索引',
  ADD KEY `idx_invitee_openid` (`invitee_openid`) USING BTREE COMMENT '被邀请者openid索引',
  ADD KEY `idx_create_time` (`create_time`) USING BTREE COMMENT '创建时间索引',
  ADD KEY `idx_invite_code_status` (`invite_code`,`status`) USING BTREE COMMENT '邀请码+状态索引';

--
-- 表的索引 `t_invite_reward_clawback`
--
ALTER TABLE `t_invite_reward_clawback`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_invite_clawback_order` (`invite_record_id`,`order_no`),
  ADD KEY `idx_invite_clawback_status` (`status`,`updated_at`);

--
-- 表的索引 `t_kds_authority_config_version`
--
ALTER TABLE `t_kds_authority_config_version`
  ADD PRIMARY KEY (`shop_id`);

--
-- 表的索引 `t_kds_delivery_consumer`
--
ALTER TABLE `t_kds_delivery_consumer`
  ADD PRIMARY KEY (`shop_id`),
  ADD KEY `idx_kds_delivery_lease_until` (`lease_until`);

--
-- 表的索引 `t_kds_delivery_event`
--
ALTER TABLE `t_kds_delivery_event`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_delivery_event_id` (`event_id`),
  ADD UNIQUE KEY `uk_kds_delivery_order_version` (`order_id`,`projection_version`),
  ADD KEY `idx_kds_delivery_shop_cursor` (`shop_id`,`id`),
  ADD KEY `idx_kds_delivery_shop_created` (`shop_id`,`created_at`);

--
-- 表的索引 `t_kds_device`
--
ALTER TABLE `t_kds_device`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_device_code` (`device_code`),
  ADD KEY `idx_kds_device_shop` (`shop_id`,`screen_tag`);

--
-- 表的索引 `t_kds_device_workflow`
--
ALTER TABLE `t_kds_device_workflow`
  ADD PRIMARY KEY (`device_id`);

--
-- 表的索引 `t_kds_dish_screen`
--
ALTER TABLE `t_kds_dish_screen`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_dish_screen` (`shop_id`,`dish_id`),
  ADD KEY `idx_kds_dish_screen_tag` (`shop_id`,`screen_tag`);

--
-- 表的索引 `t_kds_flow_batch`
--
ALTER TABLE `t_kds_flow_batch`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_kds_flow_batch_ticket` (`ticket_id`,`queue_status`),
  ADD KEY `idx_kds_flow_batch_detail` (`shop_id`,`detail_id`,`queue_status`),
  ADD KEY `idx_kds_flow_batch_fifo_prep` (`shop_id`,`queue_status`,`order_time`),
  ADD KEY `idx_kds_flow_batch_fifo_cook` (`shop_id`,`queue_status`,`prep_at`);

--
-- 表的索引 `t_kds_operation_log`
--
ALTER TABLE `t_kds_operation_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_kds_op_shop_time` (`shop_id`,`created_at`),
  ADD KEY `idx_kds_op_detail` (`detail_id`,`created_at`),
  ADD KEY `idx_kds_op_ticket` (`ticket_id`,`created_at`);

--
-- 表的索引 `t_kds_order`
--
ALTER TABLE `t_kds_order`
  ADD PRIMARY KEY (`order_id`),
  ADD KEY `idx_kds_order_shop_status` (`shop_id`,`kds_order_status`);

--
-- 表的索引 `t_kds_order_projection`
--
ALTER TABLE `t_kds_order_projection`
  ADD PRIMARY KEY (`order_id`),
  ADD KEY `idx_kds_projection_shop_state_order` (`shop_id`,`state`,`order_id`),
  ADD KEY `idx_kds_projection_shop_cursor` (`shop_id`,`last_event_cursor`);

--
-- 表的索引 `t_kds_replication_aggregate`
--
ALTER TABLE `t_kds_replication_aggregate`
  ADD PRIMARY KEY (`shop_id`,`aggregate_key`);

--
-- 表的索引 `t_kds_replication_dead_letter_audit`
--
ALTER TABLE `t_kds_replication_dead_letter_audit`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_kds_dead_letter_audit` (`shop_id`,`event_id`,`created_at`);

--
-- 表的索引 `t_kds_replication_detail_map`
--
ALTER TABLE `t_kds_replication_detail_map`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_replication_local_detail` (`shop_id`,`local_detail_id`),
  ADD UNIQUE KEY `uk_kds_replication_cloud_detail` (`cloud_detail_id`),
  ADD KEY `idx_kds_replication_detail_order` (`shop_id`,`local_order_id`);

--
-- 表的索引 `t_kds_replication_event`
--
ALTER TABLE `t_kds_replication_event`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_replication_event_id` (`event_id`),
  ADD UNIQUE KEY `uk_kds_replication_operation` (`shop_id`,`operation_id`),
  ADD KEY `idx_kds_replication_pending` (`shop_id`,`aggregate_key`,`status`,`occurred_at_ms`,`id`);

--
-- 表的索引 `t_kds_replication_inventory_state`
--
ALTER TABLE `t_kds_replication_inventory_state`
  ADD PRIMARY KEY (`shop_id`,`dish_id`);

--
-- 表的索引 `t_kds_replication_line_state`
--
ALTER TABLE `t_kds_replication_line_state`
  ADD PRIMARY KEY (`shop_id`,`local_detail_id`),
  ADD KEY `idx_kds_replication_line_order` (`shop_id`,`local_order_id`);

--
-- 表的索引 `t_kds_replication_order_map`
--
ALTER TABLE `t_kds_replication_order_map`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_replication_local_order` (`shop_id`,`local_order_id`),
  ADD UNIQUE KEY `uk_kds_replication_aggregate_map` (`shop_id`,`aggregate_key`),
  ADD UNIQUE KEY `uk_kds_replication_cloud_order` (`cloud_order_id`);

--
-- 表的索引 `t_kds_replication_order_state`
--
ALTER TABLE `t_kds_replication_order_state`
  ADD PRIMARY KEY (`shop_id`,`local_order_id`);

--
-- 表的索引 `t_kds_serve_print_job`
--
ALTER TABLE `t_kds_serve_print_job`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `job_key` (`job_key`),
  ADD KEY `idx_kds_serve_print_due` (`status`,`next_attempt_at`);

--
-- 表的索引 `t_kds_shop_config`
--
ALTER TABLE `t_kds_shop_config`
  ADD PRIMARY KEY (`shop_id`);

--
-- 表的索引 `t_kds_skewer_pick`
--
ALTER TABLE `t_kds_skewer_pick`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_kds_skewer_pick_shop_time` (`shop_id`,`picked_at`);

--
-- 表的索引 `t_kds_station`
--
ALTER TABLE `t_kds_station`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_station_shop_code` (`shop_id`,`code`),
  ADD UNIQUE KEY `uk_kds_station_shop_tag` (`shop_id`,`screen_tag`),
  ADD KEY `idx_kds_station_shop` (`shop_id`);

--
-- 表的索引 `t_kds_station_category`
--
ALTER TABLE `t_kds_station_category`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_sc_station_cid` (`station_id`,`cid`),
  ADD KEY `idx_kds_sc_cid` (`cid`);

--
-- 表的索引 `t_kds_sync_dedup`
--
ALTER TABLE `t_kds_sync_dedup`
  ADD PRIMARY KEY (`client_id`);

--
-- 表的索引 `t_kds_ticket`
--
ALTER TABLE `t_kds_ticket`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_kds_ticket_detail_station` (`detail_id`,`station_id`),
  ADD KEY `idx_kds_ticket_shop_screen_status` (`shop_id`,`screen_tag`,`item_status`,`archived`),
  ADD KEY `idx_kds_ticket_order` (`order_id`),
  ADD KEY `idx_kds_ticket_shop_flags` (`shop_id`,`rush_flag`,`overdue_flag`,`add_dish_flag`);

--
-- 表的索引 `t_material`
--
ALTER TABLE `t_material`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_material_shop` (`shop_id`);

--
-- 表的索引 `t_member_recharge`
--
ALTER TABLE `t_member_recharge`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_member_recharge_order_no` (`order_no`),
  ADD KEY `idx_member_recharge_openid_created` (`openid`,`created_at`),
  ADD KEY `idx_member_recharge_user_created` (`user_id`,`created_at`),
  ADD KEY `idx_recharge_drawer_status` (`drawer_session_id`,`status`),
  ADD KEY `idx_recharge_shop_status_pay_time` (`shop_id`,`status`,`pay_time`);

--
-- 表的索引 `t_notification_delivery`
--
ALTER TABLE `t_notification_delivery`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_shop_time` (`shop_id`,`created_at`),
  ADD KEY `idx_shop_rule` (`shop_id`,`rule_id`);

--
-- 表的索引 `t_notification_rule`
--
ALTER TABLE `t_notification_rule`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_shop_event` (`shop_id`,`event_type`);

--
-- 表的索引 `t_operation_log`
--
ALTER TABLE `t_operation_log`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_operation_log_cashier_idem` (`shop_id`,`module`,`action`,`request_key`),
  ADD KEY `idx_admin_created` (`admin_id`,`created_at`),
  ADD KEY `idx_module_action` (`module`,`action`),
  ADD KEY `idx_operation_log_shop` (`shop_id`),
  ADD KEY `idx_operation_log_cashier_trace` (`trace_id`),
  ADD KEY `idx_operation_log_cashier_table_time` (`shop_id`,`source_table`,`created_at`);

--
-- 表的索引 `t_order`
--
ALTER TABLE `t_order`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_order_order_no` (`order_no`) USING BTREE,
  ADD KEY `OP` (`openid`) USING BTREE,
  ADD KEY `idx_order_shop_time` (`shop_id`,`order_time`),
  ADD KEY `idx_order_shop_pay_time` (`shop_id`,`pay_time`),
  ADD KEY `idx_order_shop_openid` (`shop_id`,`openid`),
  ADD KEY `idx_order_cashier_id` (`cashier_id`),
  ADD KEY `idx_order_shop_table_status_id` (`shop_id`,`table_number`,`transac_status`,`id`);

--
-- 表的索引 `t_order_client_request`
--
ALTER TABLE `t_order_client_request`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_order_client_request` (`shop_id`,`client_request_id`) USING BTREE,
  ADD KEY `idx_order_client_request_expiry` (`expires_at`) USING BTREE;

--
-- 表的索引 `t_order_detail`
--
ALTER TABLE `t_order_detail`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `mId` (`mId`) USING BTREE,
  ADD KEY `/` (`Morder_no`) USING BTREE,
  ADD KEY `idx_order_detail_combo_inst` (`mId`,`combo_instance_id`),
  ADD KEY `idx_order_detail_line_type` (`line_type`),
  ADD KEY `idx_order_detail_line_status` (`mId`,`line_status`),
  ADD KEY `idx_order_detail_dish` (`dish_id`) USING BTREE,
  ADD KEY `idx_order_detail_client_line` (`mId`,`client_line_id`);

--
-- 表的索引 `t_order_log`
--
ALTER TABLE `t_order_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_order_no` (`order_no`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `idx_order_log_shop_created` (`shop_id`,`created_at`);

--
-- 表的索引 `t_parking_plate`
--
ALTER TABLE `t_parking_plate`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_plate_user` (`plate_number`,`user_id`) USING BTREE COMMENT '用户+车牌唯一索引（避免重复绑定）',
  ADD KEY `idx_user_id` (`user_id`) USING BTREE COMMENT '用户ID索引（查询提速）';

--
-- 表的索引 `t_payment`
--
ALTER TABLE `t_payment`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_order_no` (`order_no`),
  ADD KEY `idx_pay_time` (`pay_time`),
  ADD KEY `idx_shop_id` (`shop_id`);

--
-- 表的索引 `t_payment_capability`
--
ALTER TABLE `t_payment_capability`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_shop` (`shop_id`);

--
-- 表的索引 `t_payment_merchant_config`
--
ALTER TABLE `t_payment_merchant_config`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_shop_channel_key` (`shop_id`,`channel`,`merchant_key`) USING BTREE,
  ADD KEY `idx_shop_channel` (`shop_id`,`channel`) USING BTREE,
  ADD KEY `idx_payment_merchant_notify_serial` (`channel`,`platform_pub_key_id`) USING BTREE;

--
-- 表的索引 `t_payment_method`
--
ALTER TABLE `t_payment_method`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_code` (`code`),
  ADD KEY `idx_payment_method_shop` (`shop_id`);

--
-- 表的索引 `t_payment_ninefold_config`
--
ALTER TABLE `t_payment_ninefold_config`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_shop` (`shop_id`);

--
-- 表的索引 `t_payment_refund_guard`
--
ALTER TABLE `t_payment_refund_guard`
  ADD PRIMARY KEY (`shop_id`,`order_no`),
  ADD KEY `idx_payment_refund_guard_key` (`shop_id`,`idempotency_key`);

--
-- 表的索引 `t_payment_refund_request`
--
ALTER TABLE `t_payment_refund_request`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_payment_refund_idempotency` (`shop_id`,`idempotency_key`),
  ADD UNIQUE KEY `uk_payment_refund_out_no` (`out_refund_no`),
  ADD KEY `idx_payment_refund_order` (`shop_id`,`order_no`),
  ADD KEY `idx_payment_refund_merchant_config` (`merchant_config_id`,`merchant_config_version`);

--
-- 表的索引 `t_payment_test_txn`
--
ALTER TABLE `t_payment_test_txn`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_shop_idem` (`shop_id`,`idempotency_key`);

--
-- 表的索引 `t_permission`
--
ALTER TABLE `t_permission`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_permission_code` (`permission_code`) USING BTREE;

--
-- 表的索引 `t_personal_payment_event`
--
ALTER TABLE `t_personal_payment_event`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_personal_pay_event_id` (`event_id`),
  ADD KEY `idx_personal_pay_created` (`created_at`),
  ADD KEY `idx_personal_pay_matched_order` (`matched_order_no`);

--
-- 表的索引 `t_printing_device`
--
ALTER TABLE `t_printing_device`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_printing_device_shop` (`shop_id`,`transport`,`status`);

--
-- 表的索引 `t_printing_job`
--
ALTER TABLE `t_printing_job`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_printing_job_shop_time` (`shop_id`,`created_at`),
  ADD KEY `idx_printing_job_shop_device_status` (`shop_id`,`device_id`,`status`),
  ADD KEY `idx_printing_job_biz` (`biz_type`,`biz_id`);

--
-- 表的索引 `t_printing_rule`
--
ALTER TABLE `t_printing_rule`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_printing_rule_shop_scenario` (`shop_id`,`scenario`),
  ADD KEY `idx_printing_rule_shop_device` (`shop_id`,`device_id`);

--
-- 表的索引 `t_printing_template`
--
ALTER TABLE `t_printing_template`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_shop_template_code` (`shop_id`,`template_code`),
  ADD KEY `idx_shop_scenario` (`shop_id`,`scenario`);

--
-- 表的索引 `t_queue_ticket`
--
ALTER TABLE `t_queue_ticket`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_shop_ticket_no` (`shop_id`,`ticket_no`) USING BTREE,
  ADD KEY `idx_shop_status_created` (`shop_id`,`status`,`created_at`) USING BTREE,
  ADD KEY `idx_openid_created` (`openid`,`created_at`) USING BTREE;

--
-- 表的索引 `t_region`
--
ALTER TABLE `t_region`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_region_code` (`code`),
  ADD KEY `idx_region_parent` (`parent_id`);

--
-- 表的索引 `t_report_export_job`
--
ALTER TABLE `t_report_export_job`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_shop_created` (`shop_id`,`created_at`),
  ADD KEY `idx_shop_type_status` (`shop_id`,`job_type`,`status`),
  ADD KEY `idx_token` (`download_token`);

--
-- 表的索引 `t_role`
--
ALTER TABLE `t_role`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_role_code` (`role_code`);

--
-- 表的索引 `t_role_permission`
--
ALTER TABLE `t_role_permission`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_role_permission` (`role_id`,`permission_id`) USING BTREE,
  ADD KEY `idx_permission_id` (`permission_id`) USING BTREE;

--
-- 表的索引 `t_shift`
--
ALTER TABLE `t_shift`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_admin_start` (`admin_id`,`start_time`);

--
-- 表的索引 `t_shop`
--
ALTER TABLE `t_shop`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_code` (`code`),
  ADD KEY `idx_shop_status_sort` (`status`,`sort_order`,`id`),
  ADD KEY `idx_shop_region` (`region_id`);


--
-- 表的索引 `t_shop_settings`
--
ALTER TABLE `t_shop_settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_shop_module` (`shop_id`,`module`);

--
-- 表的索引 `t_shop_takeout_config`
--
ALTER TABLE `t_shop_takeout_config`
  ADD PRIMARY KEY (`shop_id`);

--
-- 表的索引 `t_stock_in`
--
ALTER TABLE `t_stock_in`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_material_id` (`material_id`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `idx_stock_in_shop` (`shop_id`);

--
-- 表的索引 `t_stock_out`
--
ALTER TABLE `t_stock_out`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_material_id` (`material_id`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `idx_stock_out_shop` (`shop_id`);

--
-- 表的索引 `t_stock_prepare_plan`
--
ALTER TABLE `t_stock_prepare_plan`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_run_material_prepare_date` (`run_id`,`material_id`,`prepare_date`) USING BTREE,
  ADD KEY `idx_shop_material_date` (`shop_id`,`material_id`,`prepare_date`) USING BTREE,
  ADD KEY `idx_prepare_date` (`prepare_date`) USING BTREE,
  ADD KEY `idx_status` (`status`) USING BTREE;

--
-- 表的索引 `t_stock_prep_config`
--
ALTER TABLE `t_stock_prep_config`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_shop` (`shop_id`) USING BTREE;

--
-- 表的索引 `t_stock_prep_forecast_day`
--
ALTER TABLE `t_stock_prep_forecast_day`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_spf_day_run_date` (`run_id`,`stat_date`) USING BTREE,
  ADD KEY `idx_spf_day_run` (`run_id`) USING BTREE;

--
-- 表的索引 `t_stock_prep_forecast_dish`
--
ALTER TABLE `t_stock_prep_forecast_dish`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `idx_spf_dish_run_date` (`run_id`,`stat_date`) USING BTREE;

--
-- 表的索引 `t_stock_prep_forecast_run`
--
ALTER TABLE `t_stock_prep_forecast_run`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `idx_spf_run_shop_created` (`shop_id`,`created_at`) USING BTREE;

--
-- 表的索引 `t_system_config`
--
ALTER TABLE `t_system_config`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_shop_config_key` (`shop_id`,`config_key`) USING BTREE;

--
-- 表的索引 `t_table`
--
ALTER TABLE `t_table`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD UNIQUE KEY `uk_table_shop_number` (`shop_id`,`number`) USING BTREE,
  ADD KEY `number` (`number`) USING BTREE,
  ADD KEY `idx_table_shop` (`shop_id`) USING BTREE;

--
-- 表的索引 `t_takeout_delivery`
--
ALTER TABLE `t_takeout_delivery`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_takeout_order_id` (`order_id`),
  ADD KEY `idx_takeout_shop_status` (`shop_id`,`dispatch_status`),
  ADD KEY `idx_takeout_order_no` (`order_no`),
  ADD KEY `idx_takeout_zsq_open_order` (`zsq_open_order_id`),
  ADD KEY `idx_takeout_zsq_dispatch_status` (`zsq_dispatch_status`,`dispatch_status`);

--
-- 表的索引 `t_unit`
--
ALTER TABLE `t_unit`
  ADD PRIMARY KEY (`id`) USING BTREE;

--
-- 表的索引 `t_user`
--
ALTER TABLE `t_user`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `openid` (`openid`) USING BTREE;

--
-- 表的索引 `t_user_activity_interaction`
--
ALTER TABLE `t_user_activity_interaction`
  ADD PRIMARY KEY (`id`) USING BTREE;

--
-- 表的索引 `t_user_address`
--
ALTER TABLE `t_user_address`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_address_openid` (`openid`),
  ADD KEY `idx_user_address_openid_default` (`openid`,`is_default`);

--
-- 表的索引 `t_user_coupon`
--
ALTER TABLE `t_user_coupon`
  ADD PRIMARY KEY (`id`) USING BTREE,
  ADD KEY `idx_user_openid` (`user_openid`) USING BTREE COMMENT '用户openid索引',
  ADD KEY `idx_coupon_id` (`coupon_id`) USING BTREE COMMENT '优惠券ID索引',
  ADD KEY `idx_status` (`status`) USING BTREE COMMENT '状态索引',
  ADD KEY `idx_get_time` (`get_time`) USING BTREE COMMENT '领取时间索引',
  ADD KEY `idx_expire_time` (`expire_time`) USING BTREE COMMENT '失效时间索引';

--
-- 表的索引 `t_user_last_shop`
--
ALTER TABLE `t_user_last_shop`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_openid` (`openid`),
  ADD KEY `idx_shop` (`shop_id`);

--
-- 在导出的表使用AUTO_INCREMENT
--

--
-- 使用表AUTO_INCREMENT `t_activity_popup`
--
ALTER TABLE `t_activity_popup`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '活动ID';

--
-- 使用表AUTO_INCREMENT `t_admin`
--
ALTER TABLE `t_admin`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_admin_region`
--
ALTER TABLE `t_admin_region`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_admin_role`
--
ALTER TABLE `t_admin_role`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_admin_shop`
--
ALTER TABLE `t_admin_shop`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_announcement`
--
ALTER TABLE `t_announcement`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_api_permission`
--
ALTER TABLE `t_api_permission`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_cashier_collection_intent`
--
ALTER TABLE `t_cashier_collection_intent`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_category`
--
ALTER TABLE `t_category`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

ALTER TABLE `t_category_shop`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_combo`
--
ALTER TABLE `t_combo`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_combo_fixed_item`
--
ALTER TABLE `t_combo_fixed_item`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_combo_group`
--
ALTER TABLE `t_combo_group`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_combo_group_item`
--
ALTER TABLE `t_combo_group_item`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_coupon`
--
ALTER TABLE `t_coupon`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键ID';

--
-- 使用表AUTO_INCREMENT `t_coupon_redeem_code`
--
ALTER TABLE `t_coupon_redeem_code`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键ID';

--
-- 使用表AUTO_INCREMENT `t_daily_stat`
--
ALTER TABLE `t_daily_stat`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_dish`
--
ALTER TABLE `t_dish`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_dish_material_bom`
--
ALTER TABLE `t_dish_material_bom`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '配比ID';

--
-- 使用表AUTO_INCREMENT `t_dish_shop`
--
ALTER TABLE `t_dish_shop`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_first_order_campaign`
--
ALTER TABLE `t_first_order_campaign`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_first_order_redemption`
--
ALTER TABLE `t_first_order_redemption`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_inventory_batch`
--
ALTER TABLE `t_inventory_batch`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键自增';

--
-- 使用表AUTO_INCREMENT `t_inventory_bom`
--
ALTER TABLE `t_inventory_bom`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键自增';

--
-- 使用表AUTO_INCREMENT `t_inventory_purchase`
--
ALTER TABLE `t_inventory_purchase`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键自增';

--
-- 使用表AUTO_INCREMENT `t_inventory_supplier`
--
ALTER TABLE `t_inventory_supplier`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键自增';

--
-- 使用表AUTO_INCREMENT `t_inventory_transfer`
--
ALTER TABLE `t_inventory_transfer`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键自增';

--
-- 使用表AUTO_INCREMENT `t_inventory_warehouse`
--
ALTER TABLE `t_inventory_warehouse`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键自增';

--
-- 使用表AUTO_INCREMENT `t_invite_record`
--
ALTER TABLE `t_invite_record`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键ID';

--
-- 使用表AUTO_INCREMENT `t_invite_reward_clawback`
--
ALTER TABLE `t_invite_reward_clawback`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_delivery_event`
--
ALTER TABLE `t_kds_delivery_event`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '全局持久游标；门店内递增但不保证连续';

--
-- 使用表AUTO_INCREMENT `t_kds_device`
--
ALTER TABLE `t_kds_device`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_dish_screen`
--
ALTER TABLE `t_kds_dish_screen`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_flow_batch`
--
ALTER TABLE `t_kds_flow_batch`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_operation_log`
--
ALTER TABLE `t_kds_operation_log`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_replication_dead_letter_audit`
--
ALTER TABLE `t_kds_replication_dead_letter_audit`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_replication_detail_map`
--
ALTER TABLE `t_kds_replication_detail_map`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_replication_event`
--
ALTER TABLE `t_kds_replication_event`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_replication_order_map`
--
ALTER TABLE `t_kds_replication_order_map`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_serve_print_job`
--
ALTER TABLE `t_kds_serve_print_job`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_skewer_pick`
--
ALTER TABLE `t_kds_skewer_pick`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_station`
--
ALTER TABLE `t_kds_station`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_station_category`
--
ALTER TABLE `t_kds_station_category`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_kds_ticket`
--
ALTER TABLE `t_kds_ticket`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_material`
--
ALTER TABLE `t_material`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_member_recharge`
--
ALTER TABLE `t_member_recharge`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_notification_delivery`
--
ALTER TABLE `t_notification_delivery`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_notification_rule`
--
ALTER TABLE `t_notification_rule`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_operation_log`
--
ALTER TABLE `t_operation_log`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_order`
--
ALTER TABLE `t_order`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_order_client_request`
--
ALTER TABLE `t_order_client_request`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_order_detail`
--
ALTER TABLE `t_order_detail`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT COMMENT '编号';

--
-- 使用表AUTO_INCREMENT `t_order_log`
--
ALTER TABLE `t_order_log`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_parking_plate`
--
ALTER TABLE `t_parking_plate`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '记录唯一ID（主键）';

--
-- 使用表AUTO_INCREMENT `t_payment`
--
ALTER TABLE `t_payment`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_payment_capability`
--
ALTER TABLE `t_payment_capability`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_payment_merchant_config`
--
ALTER TABLE `t_payment_merchant_config`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_payment_method`
--
ALTER TABLE `t_payment_method`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_payment_ninefold_config`
--
ALTER TABLE `t_payment_ninefold_config`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_payment_refund_request`
--
ALTER TABLE `t_payment_refund_request`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_payment_test_txn`
--
ALTER TABLE `t_payment_test_txn`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_permission`
--
ALTER TABLE `t_permission`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_personal_payment_event`
--
ALTER TABLE `t_personal_payment_event`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '自增主键';

--
-- 使用表AUTO_INCREMENT `t_printing_device`
--
ALTER TABLE `t_printing_device`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '设备 ID';

--
-- 使用表AUTO_INCREMENT `t_printing_job`
--
ALTER TABLE `t_printing_job`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '任务 ID';

--
-- 使用表AUTO_INCREMENT `t_printing_rule`
--
ALTER TABLE `t_printing_rule`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '规则 ID';

--
-- 使用表AUTO_INCREMENT `t_printing_template`
--
ALTER TABLE `t_printing_template`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '模板 ID';

--
-- 使用表AUTO_INCREMENT `t_queue_ticket`
--
ALTER TABLE `t_queue_ticket`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_region`
--
ALTER TABLE `t_region`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_report_export_job`
--
ALTER TABLE `t_report_export_job`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '任务ID';

--
-- 使用表AUTO_INCREMENT `t_role`
--
ALTER TABLE `t_role`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_role_permission`
--
ALTER TABLE `t_role_permission`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_shift`
--
ALTER TABLE `t_shift`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_shop`
--
ALTER TABLE `t_shop`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;


--
-- 使用表AUTO_INCREMENT `t_shop_settings`
--
ALTER TABLE `t_shop_settings`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_stock_in`
--
ALTER TABLE `t_stock_in`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_stock_out`
--
ALTER TABLE `t_stock_out`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_stock_prepare_plan`
--
ALTER TABLE `t_stock_prepare_plan`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '备货计划ID';

--
-- 使用表AUTO_INCREMENT `t_stock_prep_config`
--
ALTER TABLE `t_stock_prep_config`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_stock_prep_forecast_day`
--
ALTER TABLE `t_stock_prep_forecast_day`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_stock_prep_forecast_dish`
--
ALTER TABLE `t_stock_prep_forecast_dish`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_stock_prep_forecast_run`
--
ALTER TABLE `t_stock_prep_forecast_run`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_system_config`
--
ALTER TABLE `t_system_config`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_table`
--
ALTER TABLE `t_table`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_takeout_delivery`
--
ALTER TABLE `t_takeout_delivery`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_unit`
--
ALTER TABLE `t_unit`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_user`
--
ALTER TABLE `t_user`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_user_address`
--
ALTER TABLE `t_user_address`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 使用表AUTO_INCREMENT `t_user_coupon`
--
ALTER TABLE `t_user_coupon`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '主键ID';

--
-- 使用表AUTO_INCREMENT `t_user_last_shop`
--
ALTER TABLE `t_user_last_shop`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- 限制导出的表
--

--
-- 限制表 `t_admin_region`
--
ALTER TABLE `t_admin_region`
  ADD CONSTRAINT `fk_ar_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ar_region` FOREIGN KEY (`region_id`) REFERENCES `t_region` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_admin_role`
--
ALTER TABLE `t_admin_role`
  ADD CONSTRAINT `fk_admin_role_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_admin_role_role` FOREIGN KEY (`role_id`) REFERENCES `t_role` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_admin_shop`
--
ALTER TABLE `t_admin_shop`
  ADD CONSTRAINT `fk_as_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_as_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_combo`
--
ALTER TABLE `t_combo`
  ADD CONSTRAINT `fk_combo_dish` FOREIGN KEY (`dish_id`) REFERENCES `t_dish` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_combo_fixed_item`
--
ALTER TABLE `t_combo_fixed_item`
  ADD CONSTRAINT `fk_combo_fixed_combo` FOREIGN KEY (`combo_id`) REFERENCES `t_combo` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_combo_fixed_component` FOREIGN KEY (`component_dish_id`) REFERENCES `t_dish` (`id`);

--
-- 限制表 `t_combo_group`
--
ALTER TABLE `t_combo_group`
  ADD CONSTRAINT `fk_combo_group_combo` FOREIGN KEY (`combo_id`) REFERENCES `t_combo` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_combo_group_item`
--
ALTER TABLE `t_combo_group_item`
  ADD CONSTRAINT `fk_combo_gi_dish` FOREIGN KEY (`component_dish_id`) REFERENCES `t_dish` (`id`),
  ADD CONSTRAINT `fk_combo_gi_group` FOREIGN KEY (`group_id`) REFERENCES `t_combo_group` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_coupon_redeem_code`
--
ALTER TABLE `t_coupon_redeem_code`
  ADD CONSTRAINT `fk_redeem_coupon_id` FOREIGN KEY (`coupon_id`) REFERENCES `t_coupon` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_dish_shop`
--
ALTER TABLE `t_dish_shop`
  ADD CONSTRAINT `fk_dish_shop_dish` FOREIGN KEY (`dish_id`) REFERENCES `t_dish` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_dish_shop_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE;

ALTER TABLE `t_category_shop`
  ADD CONSTRAINT `fk_category_shop_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_category_shop_category` FOREIGN KEY (`category_id`) REFERENCES `t_category` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_order`
--
ALTER TABLE `t_order`
  ADD CONSTRAINT `OP` FOREIGN KEY (`openid`) REFERENCES `t_user` (`openid`);

--
-- 限制表 `t_parking_plate`
--
ALTER TABLE `t_parking_plate`
  ADD CONSTRAINT `fk_plate_user` FOREIGN KEY (`user_id`) REFERENCES `t_user` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_role_permission`
--
ALTER TABLE `t_role_permission`
  ADD CONSTRAINT `fk_role_permission_perm` FOREIGN KEY (`permission_id`) REFERENCES `t_permission` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_role_permission_role` FOREIGN KEY (`role_id`) REFERENCES `t_role` (`id`) ON DELETE CASCADE;


--
-- 限制表 `t_stock_prepare_plan`
--
ALTER TABLE `t_stock_prepare_plan`
  ADD CONSTRAINT `fk_prepare_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_stock_prep_forecast_day`
--
ALTER TABLE `t_stock_prep_forecast_day`
  ADD CONSTRAINT `fk_spf_day_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_stock_prep_forecast_dish`
--
ALTER TABLE `t_stock_prep_forecast_dish`
  ADD CONSTRAINT `fk_spf_dish_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_user_coupon`
--
ALTER TABLE `t_user_coupon`
  ADD CONSTRAINT `fk_user_coupon_coupon_id` FOREIGN KEY (`coupon_id`) REFERENCES `t_coupon` (`id`) ON DELETE CASCADE;

--
-- 限制表 `t_user_last_shop`
--
ALTER TABLE `t_user_last_shop`
-- --------------------------------------------------------
--
-- 表的结构 `t_payment_ledger` (不可变支付账本 POS-SDC-101)
--
CREATE TABLE IF NOT EXISTS `t_payment_ledger` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '流水自增ID',
  `ledger_no` varchar(64) NOT NULL COMMENT '权威资金流水号',
  `request_id` varchar(64) NOT NULL COMMENT '幂等请求ID',
  `shop_id` int(11) NOT NULL COMMENT '门店ID',
  `order_id` bigint(20) NOT NULL COMMENT '订单ID',
  `order_no` varchar(64) NOT NULL COMMENT '订单号',
  `terminal_id` varchar(32) DEFAULT NULL COMMENT '收银机终端编号',
  `drawer_session_id` bigint(20) DEFAULT NULL COMMENT '钱箱会话ID',
  `employee_shift_id` bigint(20) DEFAULT NULL COMMENT '员工班次ID',
  `operator_id` int(11) DEFAULT NULL COMMENT '操作人管理员ID',
  `entry_type` varchar(24) NOT NULL COMMENT '流水类型：PAYMENT/REFUND/REVERSAL/ADJUSTMENT',
  `channel` varchar(32) NOT NULL COMMENT '支付渠道：CASH/WECHAT/WECHAT_QR/ALIPAY/ALIPAY_QR/BALANCE_PRINCIPAL/GIFT/OTHER',
  `amount_fen` int(11) NOT NULL COMMENT '资金金额(分)，正数为收入，负数为退款或冲正',
  `status` varchar(24) NOT NULL DEFAULT 'SUCCEEDED' COMMENT '流水状态：SUCCEEDED/FAILED/PENDING',
  `provider_transaction_id` varchar(128) DEFAULT NULL COMMENT '三方支付交易凭证号',
  `original_ledger_id` bigint(20) DEFAULT NULL COMMENT '关联原流水ID(退款或冲正必填)',
  `occurred_at` datetime NOT NULL COMMENT '业务发生时间',
  `business_day` varchar(10) NOT NULL COMMENT '归属营业日(YYYY-MM-DD)',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '落账时间(不可修改)',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_ledger_no` (`ledger_no`),
  UNIQUE KEY `uk_payment_ledger_req` (`shop_id`, `request_id`, `entry_type`, `channel`),
  KEY `idx_payment_ledger_order` (`shop_id`, `order_no`),
  KEY `idx_payment_ledger_day_channel` (`shop_id`, `business_day`, `channel`),
  KEY `idx_payment_ledger_operator` (`shop_id`, `operator_id`, `occurred_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='不可变支付流水账本' ROW_FORMAT=DYNAMIC;

CREATE TABLE IF NOT EXISTS `t_drawer_session` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '钱箱会话自增ID',
  `session_no` varchar(64) NOT NULL COMMENT '会话流水号',
  `shop_id` int(11) NOT NULL COMMENT '门店ID',
  `terminal_id` varchar(64) NOT NULL DEFAULT 'POS-01' COMMENT '收银机终端编号',
  `drawer_code` varchar(32) NOT NULL DEFAULT 'DEFAULT' COMMENT '钱箱代码',
  `state` varchar(32) NOT NULL DEFAULT 'OPEN' COMMENT '状态：OPEN/CLOSING/CLOSED/REOPENED',
  `opened_by` int(11) NOT NULL COMMENT '开班操作人管理员ID',
  `opened_at` datetime NOT NULL COMMENT '开班时间',
  `opening_float_fen` int(11) NOT NULL DEFAULT 0 COMMENT '备用金初始金额(分)',
  `expected_cash_fen` int(11) DEFAULT NULL COMMENT '系统计算应有现金(分)',
  `counted_cash_fen` int(11) DEFAULT NULL COMMENT '实盘现金(分)',
  `variance_fen` int(11) DEFAULT NULL COMMENT '差额(分) = counted - expected',
  `closed_by` int(11) DEFAULT NULL COMMENT '关班人管理员ID',
  `closed_at` datetime DEFAULT NULL COMMENT '关班时间',
  `variance_reason_code` varchar(64) DEFAULT NULL COMMENT '长短款差额原因代码',
  `variance_note` varchar(255) DEFAULT NULL COMMENT '差额详细说明',
  `approved_by` int(11) DEFAULT NULL COMMENT '审批主管管理员ID',
  `approved_at` datetime DEFAULT NULL COMMENT '审批时间',
  `business_day` varchar(16) NOT NULL COMMENT '归属营业日(YYYY-MM-DD)',
  `request_id` varchar(64) DEFAULT NULL COMMENT '开班幂等请求键',
  `close_request_id` varchar(64) DEFAULT NULL COMMENT '交班关箱幂等请求键',
  `version` int(11) NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `active_slot` int(11) GENERATED ALWAYS AS (CASE WHEN `state` IN ('OPEN', 'CLOSING') THEN 1 ELSE NULL END) STORED COMMENT '活动会话槽位(唯一索引)',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawer_session_no` (`session_no`),
  UNIQUE KEY `uk_active_drawer` (`shop_id`, `terminal_id`, `drawer_code`, `active_slot`),
  KEY `idx_drawer_shop_day` (`shop_id`, `business_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='终端钱箱会话' ROW_FORMAT=DYNAMIC;

CREATE TABLE IF NOT EXISTS `t_cash_movement` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '现金动作流水ID',
  `movement_no` varchar(64) NOT NULL COMMENT '动作流水号',
  `drawer_session_id` bigint(20) NOT NULL COMMENT '关联钱箱会话ID',
  `shop_id` int(11) NOT NULL COMMENT '门店ID',
  `movement_type` varchar(32) NOT NULL COMMENT '类型：OPENING_FLOAT/CASH_SALE/CASH_REFUND/CASH_IN/CASH_OUT/CASH_DROP/COUNT/ADJUSTMENT/NO_SALE',
  `amount_fen` int(11) NOT NULL COMMENT '金额(分)，流入为正，流出为负',
  `current_balance_fen` int(11) NOT NULL DEFAULT 0 COMMENT '动作发生后推导钱箱当前现金余额(分)',
  `reason_code` varchar(64) DEFAULT NULL COMMENT '原因代码',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `operator_id` int(11) NOT NULL COMMENT '经办人管理员ID',
  `approver_id` int(11) DEFAULT NULL COMMENT '审批人管理员ID',
  `order_id` bigint(20) DEFAULT NULL COMMENT '关联订单ID',
  `order_no` varchar(64) DEFAULT NULL COMMENT '关联订单号',
  `payment_ledger_id` bigint(20) DEFAULT NULL COMMENT '关联支付台账ID',
  `request_id` varchar(64) DEFAULT NULL COMMENT '幂等请求键',
  `occurred_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '动作发生时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '落账时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_cash_movement_no` (`movement_no`),
  KEY `idx_cm_session` (`drawer_session_id`),
  KEY `idx_cm_shop_time` (`shop_id`, `occurred_at`),
  KEY `idx_cm_order` (`shop_id`, `order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='不可表现金动作账本' ROW_FORMAT=DYNAMIC;

SET @dbname = DATABASE();
SET @tablename = 't_shift';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'drawer_session_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `drawer_session_id` bigint(20) DEFAULT NULL COMMENT ''关联钱箱会话ID'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'terminal_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `terminal_id` varchar(64) DEFAULT NULL COMMENT ''终端编号'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'state') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `state` varchar(32) DEFAULT ''OPEN'' COMMENT ''状态：OPEN/CLOSED'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'business_day') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `business_day` varchar(16) DEFAULT NULL COMMENT ''归属营业日(YYYY-MM-DD)'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'version') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `version` int(11) DEFAULT 1 COMMENT ''乐观锁版本'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
--
-- 表的结构 `t_access_approval`
--
CREATE TABLE IF NOT EXISTS `t_access_approval` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `approval_no` VARCHAR(64) NOT NULL COMMENT '审批唯一流水号',
  `permission_code` VARCHAR(100) NOT NULL COMMENT '需要授权的目标权限码',
  `operator_id` INT NOT NULL COMMENT '操作人管理员ID',
  `authorizer_id` INT NOT NULL COMMENT '授权人(店长)管理员ID',
  `shop_id` INT NOT NULL COMMENT '门店ID',
  `biz_type` VARCHAR(50) NOT NULL COMMENT '业务类型: ORDER, REFUND, CASH_DRAWER等',
  `biz_id` VARCHAR(100) NOT NULL COMMENT '业务对象唯一标识 (如订单号)',
  `amount` DECIMAL(12,2) DEFAULT NULL COMMENT '申请涉及的业务金额',
  `reason` VARCHAR(500) NOT NULL COMMENT '授权原因',
  `auth_method` VARCHAR(30) NOT NULL COMMENT '授权认证方式: PASSWORD, PIN, SESSION',
  `status` VARCHAR(20) NOT NULL DEFAULT 'APPROVED' COMMENT '状态: PENDING, APPROVED, CONSUMED, EXPIRED, REVOKED, REJECTED',
  `token_hash` CHAR(64) NOT NULL COMMENT '短期授权Token的SHA-256哈希值',
  `binding_version` INT NOT NULL DEFAULT 1 COMMENT '审批上下文绑定策略版本: 1兼容, 2严格',
  `token_value` VARCHAR(512) DEFAULT NULL COMMENT '二维码审批令牌AES-GCM短期加密信封，禁止保存原始令牌',
  `max_amount` DECIMAL(12,2) DEFAULT NULL COMMENT '授权允许的最大金额上限',
  `expires_at` DATETIME NOT NULL COMMENT 'Token有效截止时间',
  `consumed_at` DATETIME DEFAULT NULL COMMENT 'Token核销消费时间',
  `request_id` VARCHAR(128) DEFAULT NULL COMMENT '客户端幂等请求标识',
  `terminal_id` VARCHAR(100) DEFAULT NULL COMMENT '终端编号',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_approval_no` (`approval_no`),
  KEY `idx_token_hash` (`token_hash`),
  KEY `idx_operator` (`operator_id`),
  KEY `idx_biz` (`biz_type`, `biz_id`),
  KEY `idx_expire` (`status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='权限临时审批与授权令牌表' ROW_FORMAT=DYNAMIC;

--
-- 表的结构 `t_access_approval_rate_limit`
--
CREATE TABLE IF NOT EXISTS `t_access_approval_rate_limit` (
  `limit_key` CHAR(64) NOT NULL COMMENT 'SHA-256 composite key; never contains raw account or credential',
  `limit_scope` VARCHAR(40) NOT NULL COMMENT 'ONSITE_AUTHORIZE, QR_CREATE, QR_CONFIRM, CREDENTIAL_FAILURE',
  `window_started_at` DATETIME(3) NOT NULL,
  `attempts` INT NOT NULL DEFAULT 0,
  `blocked_until` DATETIME(3) DEFAULT NULL,
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`limit_key`),
  KEY `idx_approval_rate_limit_cleanup` (`updated_at`),
  KEY `idx_approval_rate_limit_blocked` (`blocked_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='审批接口与凭据失败跨实例限流状态';

COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
