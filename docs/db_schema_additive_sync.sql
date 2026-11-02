-- ============================================================
-- 结构增量同步脚本（debug -> cloud），生成于 2026-08-19 16:17:01
-- 源：127.0.0.1:3307/db_diancan_debug
-- 语义：
--   1) 云端缺失的表整表创建（不含数据）；
--   2) 云端已存在的表仅补充缺失字段（逐列守护，已存在则跳过）；
--   3) 不 DROP、不清空、不修改任何已有列/数据；可重复执行。
-- 使用：mysql -h <cloud-host> -u <user> -p <cloud_db> < db_schema_additive_sync.sql
-- 注意：不会为已存在的表补索引/外键；唯一键等约束仅随新建表生效。
-- ============================================================
SET FOREIGN_KEY_CHECKS=0;

DROP PROCEDURE IF EXISTS `p_add_col_if_missing`;
DELIMITER $
$
CREATE PROCEDURE `p_add_col_if_missing`(p_table VARCHAR(128), p_col VARCHAR(128), p_def TEXT)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND COLUMN_NAME = p_col) THEN
    SET @p_add_col_sql = CONCAT('ALTER TABLE `', p_table, '` ADD COLUMN ', p_def);
    PREPARE stmt FROM @p_add_col_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END$
$
DELIMITER ;

-- ---------- 第 1 部分：缺失表整表创建 ----------
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_activity_popup` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '活动ID',
  `name` varchar(100) NOT NULL COMMENT '活动名称',
  `popup_image` varchar(255) NOT NULL COMMENT '弹窗图片',
  `image_url` varchar(255) DEFAULT NULL COMMENT '点击跳转地址',
  `target_user` varchar(20) NOT NULL DEFAULT 'all' COMMENT '目标用户：new/member/all',
  `start_time` datetime NOT NULL COMMENT '开始时间',
  `end_time` datetime NOT NULL COMMENT '结束时间',
  `is_enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT '是否启用：1-启用 0-禁用',
  `budget_amount` decimal(12,2) DEFAULT NULL COMMENT '活动投入预算(元)，用于ROI',
  `max_show_count` int NOT NULL DEFAULT '1' COMMENT '单日最大展示次数',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `sorting` int NOT NULL,
  `type` enum('home_top','home_bottom','page_top','page_hor','page_activity','invite_top') NOT NULL COMMENT '轮播图：home_top/home_bottom/page_top/page_hor/page_activity/invite_top',
  `apply_shop_ids` varchar(500) DEFAULT NULL COMMENT '适用门店 JSON 数组，如 [1,5,3]；NULL/空/[]=全部门店',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_time_status` (`start_time`,`end_time`,`is_enabled`) USING BTREE COMMENT '查询有效活动的索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='活动弹窗表（简化版）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_admin` (
  `id` int NOT NULL AUTO_INCREMENT,
  `userName` varchar(22) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL COMMENT '密码（BCrypt 或历史明文）',
  `token_version` int NOT NULL DEFAULT 0 COMMENT '管理员令牌版本，递增后旧令牌立即失效',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_admin_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL COMMENT '管理员ID，t_admin.id',
  `region_id` int NOT NULL COMMENT '区域ID，t_region.id',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_region` (`admin_id`,`region_id`),
  KEY `idx_region` (`region_id`),
  CONSTRAINT `fk_ar_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ar_region` FOREIGN KEY (`region_id`) REFERENCES `t_region` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='管理员-区域绑定';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_admin_role` (
  `id` int NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL COMMENT 't_admin.id',
  `role_id` int NOT NULL COMMENT 't_role.id',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_admin_role` (`admin_id`,`role_id`) USING BTREE,
  KEY `idx_role_id` (`role_id`) USING BTREE,
  CONSTRAINT `fk_admin_role_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_admin_role_role` FOREIGN KEY (`role_id`) REFERENCES `t_role` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='管理员-角色关联';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_admin_shop` (
  `id` int NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL COMMENT 't_admin.id',
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_shop` (`admin_id`,`shop_id`),
  KEY `idx_shop` (`shop_id`),
  CONSTRAINT `fk_as_admin` FOREIGN KEY (`admin_id`) REFERENCES `t_admin` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_as_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='管理员-可管理门店';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_announcement` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT 'NULL=全部门店可见；非空=仅该门店',
  `title` varchar(200) NOT NULL COMMENT '标题',
  `content` longtext NOT NULL COMMENT '正文（纯文本或富文本 HTML，由前端约定）',
  `status` tinyint NOT NULL DEFAULT '1' COMMENT '1=启用 0=停用',
  `sort_order` int NOT NULL DEFAULT '0' COMMENT '越小越靠前',
  `start_time` datetime DEFAULT NULL COMMENT '可见开始时间，NULL=不限制',
  `end_time` datetime DEFAULT NULL COMMENT '可见结束时间，NULL=不限制',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_ann_shop_status_sort` (`shop_id`,`status`,`sort_order`,`id`) USING BTREE,
  KEY `idx_ann_time` (`start_time`,`end_time`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='门店公告（连锁）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_api_permission` (
  `id` int NOT NULL AUTO_INCREMENT,
  `method` varchar(10) NOT NULL COMMENT 'GET/POST/PUT/DELETE',
  `path_pattern` varchar(255) NOT NULL COMMENT '路径，如 /admin/order/list',
  `permission_code` varchar(64) NOT NULL COMMENT '所需权限码',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_path_pattern` (`path_pattern`),
  KEY `idx_path_method` (`path_pattern`(100),`method`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='接口-权限映射';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_banner` (
  `id` int NOT NULL,
  `image` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  `status` int DEFAULT NULL,
  `type` varchar(10) NOT NULL COMMENT '首页：home，底部：bottom',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_cashier_collection_intent` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `session_id` varchar(64) NOT NULL,
  `channel` varchar(16) NOT NULL,
  `amount_fen` int NOT NULL,
  `status` varchar(24) NOT NULL DEFAULT 'PENDING',
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_cashier_collection_order_channel` (`shop_id`,`order_no`,`channel`),
  KEY `idx_cashier_collection_session` (`session_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_category` (
  `id` int NOT NULL AUTO_INCREMENT,
  `label` varchar(30) DEFAULT NULL,
  `value` varchar(30) DEFAULT NULL,
  `count` int DEFAULT NULL,
  `sele_quantity` int DEFAULT '0',
  `cid` varchar(30) DEFAULT NULL,
  `sorting` int DEFAULT NULL COMMENT '排序',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_combo` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `dish_id` int NOT NULL COMMENT '套餐头菜品 t_dish.id，唯一',
  `combo_type` varchar(16) NOT NULL DEFAULT 'groups' COMMENT 'fixed=仅固定子项; groups=含可选组',
  `status` tinyint NOT NULL DEFAULT '1' COMMENT '1启用 0停用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_combo_dish` (`dish_id`),
  CONSTRAINT `fk_combo_dish` FOREIGN KEY (`dish_id`) REFERENCES `t_dish` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐定义头';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_combo_fixed_item` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `combo_id` bigint NOT NULL,
  `component_dish_id` int NOT NULL COMMENT '子菜 t_dish.id',
  `qty_per_combo` int NOT NULL DEFAULT '1' COMMENT '每份套餐含该子菜份数',
  `sort_order` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_combo_fixed_combo` (`combo_id`),
  KEY `fk_combo_fixed_component` (`component_dish_id`),
  CONSTRAINT `fk_combo_fixed_combo` FOREIGN KEY (`combo_id`) REFERENCES `t_combo` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_combo_fixed_component` FOREIGN KEY (`component_dish_id`) REFERENCES `t_dish` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐固定子项';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_combo_group` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `combo_id` bigint NOT NULL,
  `group_key` varchar(32) NOT NULL COMMENT '与下单 combo_selections 的 key 对应',
  `title` varchar(64) DEFAULT NULL COMMENT '展示标题',
  `min_pick` int NOT NULL DEFAULT '1',
  `max_pick` int NOT NULL DEFAULT '1',
  `sort_order` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_combo_group_combo` (`combo_id`),
  CONSTRAINT `fk_combo_group_combo` FOREIGN KEY (`combo_id`) REFERENCES `t_combo` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐可选组';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_combo_group_item` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `group_id` bigint NOT NULL,
  `component_dish_id` int NOT NULL,
  `extra_price` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '相对套餐基准价的加价(元)/每份套餐',
  `sort_order` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_combo_gi_group` (`group_id`),
  KEY `fk_combo_gi_dish` (`component_dish_id`),
  CONSTRAINT `fk_combo_gi_dish` FOREIGN KEY (`component_dish_id`) REFERENCES `t_dish` (`id`),
  CONSTRAINT `fk_combo_gi_group` FOREIGN KEY (`group_id`) REFERENCES `t_combo_group` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='套餐组内可选项';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_coupon` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `coupon_name` varchar(100) NOT NULL COMMENT '优惠券名称（如：满50减10）',
  `coupon_type` varchar(20) NOT NULL COMMENT '优惠券类型：full_reduction-满减 discount-折扣 direct_reduction-立减',
  `apply_dining_type` enum('all','dine_in','take_out') NOT NULL DEFAULT 'all' COMMENT '''适用用餐方式：all=全部，dine_in=仅限堂食，take_out=仅限打包''',
  `apply_dish_ids` varchar(1000) DEFAULT NULL COMMENT '适用菜品ID数组（JSON字符串），为空表示不限菜品，如 [1,2,3]',
  `apply_shop_ids` varchar(1000) DEFAULT NULL COMMENT '适用门店ID JSON 数组，如 [1,2]；空/NULL 不限门店',
  `discount_value` decimal(10,2) NOT NULL COMMENT '优惠值：满减/立减为金额，折扣为百分比（如80=8折）',
  `min_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '使用门槛（满X元可用），0为无门槛',
  `start_time` datetime NOT NULL COMMENT '生效时间',
  `end_time` datetime NOT NULL COMMENT '失效时间',
  `status` tinyint NOT NULL DEFAULT '1' COMMENT '状态：0-未启用 1-可用 2-已下架',
  `stock` int NOT NULL DEFAULT '-1' COMMENT '库存：-1为无限库存，>=0为有限库存',
  `granted_count` int NOT NULL DEFAULT '0' COMMENT '已发放张数（写入 t_user_coupon 累计）',
  `description` varchar(500) DEFAULT '' COMMENT '优惠券描述',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `validity_time` bigint NOT NULL COMMENT '有效期，单位小时',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_coupon_type` (`coupon_type`) USING BTREE COMMENT '优惠券类型索引',
  KEY `idx_status` (`status`) USING BTREE COMMENT '状态索引',
  KEY `idx_time_range` (`start_time`,`end_time`) USING BTREE COMMENT '时间范围索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='优惠券主表';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_coupon_redeem_code` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `coupon_id` bigint NOT NULL COMMENT '关联优惠券ID（t_coupon.id）',
  `redeem_code` varchar(64) NOT NULL COMMENT '兑换码（唯一）',
  `status` tinyint NOT NULL DEFAULT '0' COMMENT '状态：0-未使用 1-已使用',
  `used_openid` varchar(100) DEFAULT NULL COMMENT '使用者openid',
  `used_time` datetime DEFAULT NULL COMMENT '使用时间',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_redeem_code` (`redeem_code`) USING BTREE,
  KEY `idx_coupon_id` (`coupon_id`) USING BTREE,
  CONSTRAINT `fk_redeem_coupon_id` FOREIGN KEY (`coupon_id`) REFERENCES `t_coupon` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='优惠券兑换码表（一码一券）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_daily_stat` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `stat_date` date NOT NULL COMMENT '统计日期',
  `shop_id` int DEFAULT NULL COMMENT '门店ID，NULL表示全店',
  `total_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '营业额',
  `discount_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '优惠/折扣合计',
  `refund_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '退款合计',
  `material_cost` decimal(12,2) DEFAULT NULL COMMENT '当日原材料成本',
  `settled_at` datetime DEFAULT NULL COMMENT '日结时间',
  `operator_id` int DEFAULT NULL COMMENT '日结操作员',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_date_shop` (`stat_date`,`shop_id`),
  KEY `idx_stat_date` (`stat_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='日结对账';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_dish` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL COMMENT '菜品名称',
  `image` varchar(50) DEFAULT NULL COMMENT '菜品图片',
  `typeId` int DEFAULT NULL COMMENT '类别ID',
  `monthlysale` int DEFAULT '0' COMMENT '商品销售量',
  `unitprice` decimal(6,2) DEFAULT NULL COMMENT '商品单价',
  `cost_price` decimal(10,2) DEFAULT NULL COMMENT '成本价(元)，用于毛利分析',
  `unit` varchar(10) DEFAULT NULL COMMENT '商品单位',
  `quantity` int DEFAULT '0' COMMENT '商品数量',
  `stock` int DEFAULT NULL COMMENT '可售库存份数；NULL 表示不限量；与 quantity 解耦，下单扣减仅更新本列',
  `time` datetime DEFAULT NULL COMMENT '上架时间',
  `onsale` bit(1) DEFAULT NULL COMMENT 'true：上架 false：下架',
  `sold_out` tinyint NOT NULL DEFAULT '0' COMMENT '是否已售罄：0-否 1-是',
  `specification` varchar(255) DEFAULT NULL COMMENT '产品规格',
  `serving_duration_minutes` int NOT NULL DEFAULT '10' COMMENT '出餐时长（分钟），用于 KDS 单品超时判断',
  `sorting` int DEFAULT NULL COMMENT '排序',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_dish_material_bom` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '配比ID',
  `shop_id` int NOT NULL COMMENT '门店ID(t_shop.id)',
  `dish_id` int NOT NULL COMMENT '菜品ID(t_dish.id)',
  `material_id` int NOT NULL COMMENT '原材料ID(t_material.id)',
  `dosage` decimal(10,3) NOT NULL DEFAULT '0.000' COMMENT '单份菜品消耗原材料数量',
  `unit` varchar(16) NOT NULL DEFAULT '斤' COMMENT '单位：斤/克/袋/瓶',
  `loss_rate` decimal(5,2) NOT NULL DEFAULT '0.05' COMMENT '损耗率小数，如0.05=5%；消耗=销量×用量×(1+loss_rate)',
  `is_enabled` tinyint NOT NULL DEFAULT '1' COMMENT '1启用 0禁用',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_dish_material` (`shop_id`,`dish_id`,`material_id`) USING BTREE,
  KEY `idx_dish` (`dish_id`) USING BTREE,
  KEY `idx_material` (`material_id`) USING BTREE,
  KEY `idx_shop` (`shop_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='菜品-原材料配比表(BOM)';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_dish_shop` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `dish_id` int NOT NULL COMMENT 't_dish.id',
  `unitprice` decimal(10,2) DEFAULT NULL COMMENT '门店覆盖价；NULL 则用 t_dish.unitprice',
  `stock` int NOT NULL DEFAULT '-1' COMMENT '门店可售库存；-1 不限量；>=0 为有限库存',
  `stock_enabled` tinyint NOT NULL DEFAULT '0' COMMENT '鏄?惁鍚?敤搴撳瓨璺熻釜锛堟寔涔呮爣蹇楋紝涓嶉殢搴撳瓨鍊煎彉鍖栵級锛? 璺熻釜锛堟墸鍑?鍥為?锛夛紱0 涓嶉檺閲忔垨鏈?惎鐢',
  `sold_out` tinyint NOT NULL DEFAULT '0' COMMENT 'shop sold-out flag: 0 available, 1 sold out',
  `onsale_override` tinyint DEFAULT NULL COMMENT 'NULL 跟随总部；0 强制下架；1 强制上架',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_dish` (`shop_id`,`dish_id`) USING BTREE,
  KEY `idx_dish_shop_dish` (`dish_id`) USING BTREE,
  CONSTRAINT `fk_dish_shop_dish` FOREIGN KEY (`dish_id`) REFERENCES `t_dish` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `fk_dish_shop_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='门店菜品覆盖（价/库存/上下架）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_invite_record` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `inviter_openid` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '邀请者微信openid',
  `invitee_openid` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '被邀请者微信openid（未注册时为NULL）',
  `invite_code` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '邀请码（邀请人维度唯一）',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '邀请时间',
  `status` tinyint NOT NULL DEFAULT '0' COMMENT '状态：0-未注册 1-已注册',
  `reward_type` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'coupon' COMMENT '奖励类型：coupon-优惠券 point-积分',
  `reward_id` bigint DEFAULT NULL COMMENT '奖励优惠券ID（reward_type=coupon时）/积分值（reward_type=point时）',
  `reward_time` datetime DEFAULT NULL COMMENT '奖励发放时间',
  `first_order_reward_amount` decimal(12,2) DEFAULT NULL COMMENT '首单余额奖励金额(元)',
  `first_order_reward_time` datetime DEFAULT NULL COMMENT '首单余额奖励发放时间',
  `first_order_no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '触发首单奖励的订单号',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_invite_code_invitee` (`invite_code`,`invitee_openid`) USING BTREE COMMENT '同一邀请码不能重复邀请同一被邀请人',
  KEY `idx_inviter_openid` (`inviter_openid`) USING BTREE COMMENT '邀请者openid索引',
  KEY `idx_invitee_openid` (`invitee_openid`) USING BTREE COMMENT '被邀请者openid索引',
  KEY `idx_create_time` (`create_time`) USING BTREE COMMENT '创建时间索引',
  KEY `idx_invite_code_status` (`invite_code`,`status`) USING BTREE COMMENT '邀请码+状态索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='邀请关系记录表';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_invite_reward_clawback` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `invite_record_id` bigint NOT NULL,
  `inviter_user_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `outstanding_amount` decimal(12,2) NOT NULL,
  `status` varchar(16) NOT NULL DEFAULT 'PENDING',
  `attempts` int NOT NULL DEFAULT '0',
  `last_error` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_invite_clawback_order` (`invite_record_id`,`order_no`),
  KEY `idx_invite_clawback_status` (`status`,`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_authority_config_version` (
  `shop_id` int NOT NULL,
  `version` bigint NOT NULL DEFAULT '1',
  `cashier_device_code` varchar(64) DEFAULT NULL COMMENT 'Cashier authority identity; not a t_kds_device display device',
  `snapshot_hash` char(64) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier-authoritative KDS configuration generation';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_delivery_consumer` (
  `shop_id` int NOT NULL,
  `device_code` varchar(64) DEFAULT NULL,
  `authority_epoch` bigint NOT NULL DEFAULT '0',
  `lease_token_hash` char(64) DEFAULT NULL,
  `lease_until` datetime DEFAULT NULL,
  `ack_cursor` bigint NOT NULL DEFAULT '0',
  `last_delivered_cursor` bigint NOT NULL DEFAULT '0',
  `bootstrap_base_cursor` bigint NOT NULL DEFAULT '0',
  `bootstrap_required` tinyint(1) NOT NULL DEFAULT '1',
  `client_version` varchar(64) DEFAULT NULL,
  `last_seen_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`),
  KEY `idx_kds_delivery_lease_until` (`lease_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='每门店唯一收银 KDS 消费者租约与 ACK';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_delivery_event` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '全局持久游标；门店内递增但不保证连续',
  `event_id` char(36) NOT NULL,
  `shop_id` int NOT NULL,
  `order_id` int NOT NULL,
  `projection_version` bigint NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `origin_channel` varchar(24) NOT NULL,
  `origin_device_code` varchar(64) DEFAULT NULL,
  `changed_detail_ids_json` text,
  `payload_json` longtext NOT NULL COMMENT '完整订单厨房投影，消费者无需拼 patch',
  `occurred_at_ms` bigint NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_delivery_event_id` (`event_id`),
  UNIQUE KEY `uk_kds_delivery_order_version` (`order_id`,`projection_version`),
  KEY `idx_kds_delivery_shop_cursor` (`shop_id`,`id`),
  KEY `idx_kds_delivery_shop_created` (`shop_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='收银本地 KDS 可靠投递事件日志';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_device` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `station_id` bigint DEFAULT NULL,
  `screen_tag` varchar(32) NOT NULL,
  `device_code` varchar(64) NOT NULL,
  `device_name` varchar(64) DEFAULT NULL,
  `device_token` varchar(128) DEFAULT NULL,
  `workflows_json` varchar(64) DEFAULT NULL COMMENT 'prep,cook,serve 逗号分隔',
  `last_heartbeat_at` datetime DEFAULT NULL,
  `enabled` tinyint NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_device_code` (`device_code`),
  KEY `idx_kds_device_shop` (`shop_id`,`screen_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 厨显设备';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_dish_screen` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `dish_id` int NOT NULL COMMENT 't_dish.id',
  `screen_tag` varchar(32) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_dish_screen` (`shop_id`,`dish_id`),
  KEY `idx_kds_dish_screen_tag` (`shop_id`,`screen_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 菜品绑屏';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_flow_batch` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `ticket_id` bigint NOT NULL COMMENT 't_kds_ticket.id',
  `detail_id` int NOT NULL COMMENT 't_order_detail.id',
  `order_id` int NOT NULL,
  `quantity` int NOT NULL DEFAULT '1' COMMENT '本批次份数',
  `dining_channel` varchar(16) DEFAULT NULL COMMENT 'dine_in/pack/takeout',
  `queue_status` varchar(24) NOT NULL DEFAULT 'pending_prep' COMMENT 'pending_prep/pending_cook/ready_serve/done/void',
  `order_time` datetime DEFAULT NULL COMMENT '下单时间（FCFS）',
  `prep_at` datetime DEFAULT NULL COMMENT '配菜完成时间',
  `cooked_at` datetime DEFAULT NULL COMMENT '制作完成时间',
  `served_at` datetime DEFAULT NULL COMMENT '传菜完成时间',
  `void_reason` varchar(32) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_flow_batch_ticket` (`ticket_id`,`queue_status`),
  KEY `idx_kds_flow_batch_detail` (`shop_id`,`detail_id`,`queue_status`),
  KEY `idx_kds_flow_batch_fifo_prep` (`shop_id`,`queue_status`,`order_time`),
  KEY `idx_kds_flow_batch_fifo_cook` (`shop_id`,`queue_status`,`prep_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 流转批次（分批配菜/划菜/传菜 FCFS）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_operation_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `device_id` bigint DEFAULT NULL,
  `order_id` int NOT NULL,
  `detail_id` int DEFAULT NULL,
  `ticket_id` bigint DEFAULT NULL,
  `operation_type` varchar(32) NOT NULL COMMENT 'advance/revoke/rush/refund/lack/hold/release',
  `from_queue` varchar(32) DEFAULT NULL,
  `to_queue` varchar(32) DEFAULT NULL,
  `quantity` int NOT NULL DEFAULT '0',
  `request_id` varchar(64) DEFAULT NULL,
  `operator_type` varchar(16) NOT NULL DEFAULT 'device' COMMENT 'device/admin/pos',
  `operator_id` bigint DEFAULT NULL,
  `result_code` varchar(32) NOT NULL DEFAULT '0',
  `result_msg` varchar(255) DEFAULT NULL,
  `payload_json` json DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_op_shop_time` (`shop_id`,`created_at`),
  KEY `idx_kds_op_detail` (`detail_id`,`created_at`),
  KEY `idx_kds_op_ticket` (`ticket_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS操作审计日志';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_order` (
  `order_id` int NOT NULL COMMENT 't_order.id',
  `shop_id` int NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `kds_order_status` tinyint NOT NULL DEFAULT '10' COMMENT '10/20/30/40/90',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_id`),
  KEY `idx_kds_order_shop_status` (`shop_id`,`kds_order_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 整单厨显状态';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_order_projection` (
  `order_id` int NOT NULL,
  `shop_id` int NOT NULL,
  `projection_version` bigint NOT NULL,
  `state` varchar(16) NOT NULL,
  `source_channel` varchar(24) NOT NULL,
  `payload_json` longtext NOT NULL,
  `payload_hash` char(64) NOT NULL,
  `last_event_cursor` bigint DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_id`),
  KEY `idx_kds_projection_shop_state_order` (`shop_id`,`state`,`order_id`),
  KEY `idx_kds_projection_shop_cursor` (`shop_id`,`last_event_cursor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='云端订单厨房完整投影';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_aggregate` (
  `shop_id` int NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `order_created_applied` tinyint NOT NULL DEFAULT '0',
  `last_occurred_at_ms` bigint DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_order_revision` bigint NOT NULL DEFAULT '0',
  PRIMARY KEY (`shop_id`,`aggregate_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Per-order replication serialization lock';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_dead_letter_audit` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `event_id` varchar(128) NOT NULL,
  `action` varchar(20) NOT NULL COMMENT 'retry/replace/discard',
  `reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `operator_admin_id` int DEFAULT NULL,
  `operator_subject` varchar(128) NOT NULL,
  `trace_id` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_dead_letter_audit` (`shop_id`,`event_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditable dead-letter operator actions';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_detail_map` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `local_detail_id` bigint NOT NULL,
  `cloud_order_id` int NOT NULL,
  `cloud_detail_id` int NOT NULL,
  `last_local_revision` bigint NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_replication_local_detail` (`shop_id`,`local_detail_id`),
  UNIQUE KEY `uk_kds_replication_cloud_detail` (`cloud_detail_id`),
  KEY `idx_kds_replication_detail_order` (`shop_id`,`local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier local detail to cloud detail mapping';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_event` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `event_id` varchar(128) NOT NULL,
  `shop_id` int NOT NULL,
  `event_type` varchar(40) NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `occurred_at_ms` bigint NOT NULL,
  `operation_id` varchar(128) DEFAULT NULL,
  `local_revision` bigint DEFAULT NULL,
  `payload_json` longtext NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'received' COMMENT 'received/pending/applied/ignored/failed',
  `result_json` longtext,
  `error_code` int DEFAULT NULL,
  `error_message` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `applied_at` datetime DEFAULT NULL,
  `retry_count` int NOT NULL DEFAULT '0',
  `dead_lettered_at` datetime DEFAULT NULL,
  `resolution_action` varchar(20) DEFAULT NULL,
  `resolution_reason` varchar(500) DEFAULT NULL,
  `replacement_event_id` varchar(128) DEFAULT NULL,
  `resolved_at` datetime DEFAULT NULL,
  `request_fingerprint` char(64) DEFAULT NULL COMMENT 'SHA-256 canonical semantic request; excludes idempotency IDs',
  `publisher_device_code` varchar(64) DEFAULT NULL COMMENT 'Authenticated X-Cashier-Device-Code',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_replication_event_id` (`event_id`),
  UNIQUE KEY `uk_kds_replication_operation` (`shop_id`,`operation_id`),
  KEY `idx_kds_replication_pending` (`shop_id`,`aggregate_key`,`status`,`occurred_at_ms`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier-to-cloud durable event inbox';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_inventory_state` (
  `shop_id` int NOT NULL,
  `dish_id` int NOT NULL,
  `availability_revision` bigint NOT NULL,
  `stock` int DEFAULT NULL,
  `sold_out` tinyint DEFAULT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`dish_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Latest cashier-authoritative dish availability';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_line_state` (
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `local_detail_id` bigint NOT NULL,
  `cloud_order_id` int NOT NULL,
  `cloud_detail_id` int NOT NULL,
  `workflow_queue` varchar(40) DEFAULT NULL,
  `prep_remaining` int DEFAULT NULL,
  `cook_remaining` int DEFAULT NULL,
  `ready_remaining` int DEFAULT NULL,
  `remaining_quantity` int DEFAULT NULL,
  `local_revision` bigint NOT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`local_detail_id`),
  KEY `idx_kds_replication_line_order` (`shop_id`,`local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Latest cashier-authoritative KDS line projection';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_order_map` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `aggregate_key` varchar(128) NOT NULL,
  `local_order_no` varchar(100) DEFAULT NULL,
  `cloud_order_id` int NOT NULL,
  `cloud_order_no` varchar(100) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_replication_local_order` (`shop_id`,`local_order_id`),
  UNIQUE KEY `uk_kds_replication_aggregate_map` (`shop_id`,`aggregate_key`),
  UNIQUE KEY `uk_kds_replication_cloud_order` (`cloud_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Cashier local order to cloud order mapping';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_replication_order_state` (
  `shop_id` int NOT NULL,
  `local_order_id` bigint NOT NULL,
  `order_revision` bigint NOT NULL,
  `payload_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`local_order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Latest cashier-authoritative order snapshot';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_shop_config` (
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `kds_mode` varchar(16) NOT NULL DEFAULT 'print_only' COMMENT 'print_only|kds_only|both',
  `sync_legacy_rece` tinyint NOT NULL DEFAULT '1' COMMENT '划菜是否回写 order_rece',
  `auto_off_order_on_kds_done` tinyint NOT NULL DEFAULT '0' COMMENT '1=厨显整单完成时自动置 order_receiving=off_order（清台） 0=不联动',
  `serve_print_enabled` tinyint NOT NULL DEFAULT '1' COMMENT '1=待传菜划单后打印传菜单 0=不打印',
  `auto_push_on_create` tinyint NOT NULL DEFAULT '1' COMMENT '下单即推厨显',
  `skewer_gate` tinyint NOT NULL DEFAULT '1' COMMENT '1先抓串再分流烤制屏 0直连烤制屏',
  `prep_enabled` tinyint DEFAULT NULL COMMENT '1=有待配菜环节 0=跳过待配菜直进待制作 NULL=跟随skewer_gate',
  `default_screen_tag` varchar(32) DEFAULT 'meat_grill',
  `sla_minutes` int NOT NULL DEFAULT '10',
  `archive_hours` int NOT NULL DEFAULT '2' COMMENT '已完成归档小时数',
  `lack_sets_sold_out` tinyint NOT NULL DEFAULT '0' COMMENT '缺货上报是否置 sold_out',
  `merge_same_dish` tinyint NOT NULL DEFAULT '1' COMMENT '1=合并相同菜品（跨订单/跨桌汇总）',
  `pack_inline_merge` tinyint NOT NULL DEFAULT '1' COMMENT '1=堂食与打包内嵌同一行；0=按渠道拆行',
  `combo_merge` tinyint NOT NULL DEFAULT '1' COMMENT '1=套餐子菜与散点同菜合并；0=套餐独立成行',
  `add_dish_timeout_independent` tinyint NOT NULL DEFAULT '1' COMMENT '1=加菜超时按加菜明细自身时间计算；0=跟随订单首单时间',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 门店配置';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_skewer_pick` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `dish_name` varchar(100) NOT NULL,
  `quantity_picked` int NOT NULL DEFAULT '0',
  `unit` varchar(11) DEFAULT NULL,
  `picked_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_kds_skewer_pick_shop_time` (`shop_id`,`picked_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 抓串已抓记录';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_station` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `name` varchar(64) NOT NULL COMMENT '显示名',
  `code` varchar(32) NOT NULL COMMENT '同店唯一编码，如 MEAT',
  `screen_tag` varchar(32) NOT NULL COMMENT 'skewer_aggregate|meat_grill|veg_grill|seafood_special|expedition',
  `sort` int NOT NULL DEFAULT '0',
  `enabled` tinyint NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_station_shop_code` (`shop_id`,`code`),
  UNIQUE KEY `uk_kds_station_shop_tag` (`shop_id`,`screen_tag`),
  KEY `idx_kds_station_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 档口/分屏';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_station_category` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `station_id` bigint NOT NULL,
  `cid` varchar(64) NOT NULL COMMENT 't_category 主键字符串',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_sc_station_cid` (`station_id`,`cid`),
  KEY `idx_kds_sc_cid` (`cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 分类绑档口';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_sync_dedup` (
  `client_id` varchar(64) NOT NULL,
  `shop_id` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 客户端幂等键';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_kds_ticket` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `station_id` bigint NOT NULL,
  `screen_tag` varchar(32) NOT NULL,
  `order_id` int NOT NULL,
  `order_no` varchar(100) NOT NULL,
  `detail_id` int NOT NULL COMMENT 't_order_detail.id',
  `item_status` tinyint NOT NULL DEFAULT '0' COMMENT '0待制作 1制作中 2已完成 3已退菜',
  `skewer_picked` tinyint NOT NULL DEFAULT '0' COMMENT '0待抓串 1已抓串可上烤制屏',
  `skewer_picked_at` datetime DEFAULT NULL COMMENT '抓串完成时间',
  `rush_flag` tinyint NOT NULL DEFAULT '0',
  `add_dish_flag` tinyint NOT NULL DEFAULT '0' COMMENT '加菜标记 0/1',
  `overdue_flag` tinyint NOT NULL DEFAULT '0' COMMENT '超时标记 0/1（待做且超 SLA）',
  `overdue_at` datetime DEFAULT NULL COMMENT '首次标记超时时间',
  `rush_at` datetime DEFAULT NULL COMMENT '催菜时间',
  `order_number_snapshot` int DEFAULT NULL,
  `archived` tinyint NOT NULL DEFAULT '0',
  `served_quantity` int NOT NULL DEFAULT '0' COMMENT '已传菜确认数量（分批出餐）',
  `prep_quantity` int NOT NULL DEFAULT '0' COMMENT '已配菜数量（进入待制作池）',
  `cooked_quantity` int NOT NULL DEFAULT '0' COMMENT '已制作完成数量（进入待传菜池）',
  `prep_completed_at` datetime DEFAULT NULL COMMENT '配菜完成时刻',
  `void_reason` varchar(128) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `accepted_at` datetime DEFAULT NULL,
  `done_at` datetime DEFAULT NULL,
  `served_at` datetime DEFAULT NULL COMMENT '传菜完成时刻',
  `archived_at` datetime DEFAULT NULL COMMENT '归档进入已完成 Tab 时刻',
  `completed_wait_seconds` int DEFAULT NULL COMMENT '最近一次队列完成时的冻结等待秒数',
  `row_version` int NOT NULL DEFAULT '0' COMMENT '乐观锁版本',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_kds_ticket_detail_station` (`detail_id`,`station_id`),
  KEY `idx_kds_ticket_shop_screen_status` (`shop_id`,`screen_tag`,`item_status`,`archived`),
  KEY `idx_kds_ticket_order` (`order_id`),
  KEY `idx_kds_ticket_shop_flags` (`shop_id`,`rush_flag`,`overdue_flag`,`add_dish_flag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 厨显工单';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_material` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT '门店ID，关联 t_shop.id；NULL=未分门店的旧数据',
  `name` varchar(64) NOT NULL COMMENT '原材料名称',
  `unit` varchar(16) NOT NULL DEFAULT '斤' COMMENT '单位',
  `stock` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '当前库存',
  `alert_threshold` decimal(12,3) DEFAULT NULL COMMENT '库存预警阈值',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_material_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='原材料库';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_member_recharge` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL COMMENT 't_user.id',
  `openid` varchar(64) NOT NULL,
  `order_no` varchar(64) DEFAULT NULL COMMENT '微信充值商户单号（与 t_order 无关）；后台渠道可为空',
  `shop_id` int DEFAULT NULL,
  `operator_id` int DEFAULT NULL COMMENT '后台人工充值操作员ID',
  `drawer_session_id` bigint DEFAULT NULL COMMENT '后台人工充值归属钱箱会话ID',
  `channel` varchar(20) NOT NULL COMMENT 'wechat | admin',
  `status` varchar(20) NOT NULL DEFAULT 'pending' COMMENT 'pending|success|cancelled',
  `recharge_amount` decimal(12,2) NOT NULL COMMENT '充值本金（元）',
  `gift_amount` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '赠送（元）',
  `total_amount` decimal(12,2) NOT NULL COMMENT '入账合计（元）=本金+赠送',
  `transaction_id` varchar(128) DEFAULT NULL,
  `pay_time` datetime DEFAULT NULL,
  `remark` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_member_recharge_order_no` (`order_no`),
  KEY `idx_member_recharge_openid_created` (`openid`,`created_at`),
  KEY `idx_member_recharge_user_created` (`user_id`,`created_at`),
  KEY `idx_recharge_drawer_status` (`drawer_session_id`,`status`),
  KEY `idx_recharge_shop_status_pay_time` (`shop_id`,`status`,`pay_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='会员充值流水';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_operation_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT '门店ID，审计隔离',
  `module` varchar(32) NOT NULL COMMENT 'order/dish/price/daily等',
  `action` varchar(64) NOT NULL COMMENT 'delete_order/change_price/un_checkout等',
  `target_id` varchar(64) DEFAULT NULL COMMENT '订单号或ID',
  `admin_id` int DEFAULT NULL,
  `ip` varchar(64) DEFAULT NULL,
  `request_snapshot` text COMMENT '请求关键参数',
  `source_table` varchar(50) DEFAULT NULL COMMENT '源桌号',
  `target_table` varchar(50) DEFAULT NULL COMMENT '目标桌号；非并台为空',
  `order_nos` text COMMENT '涉及订单号 JSON 数组',
  `before_state` text COMMENT '操作前桌台/订单状态 JSON',
  `after_state` text COMMENT '操作后桌台/订单状态 JSON',
  `result_status` varchar(16) DEFAULT NULL COMMENT 'SUCCESS/REJECTED/ROLLED_BACK',
  `result_code` int DEFAULT NULL COMMENT '接口业务码',
  `reason` varchar(255) DEFAULT NULL COMMENT '成功说明或拒绝/回滚原因（不含敏感信息）',
  `request_key` varchar(128) DEFAULT NULL COMMENT 'Idempotency-Key/X-Request-ID/trace 标识',
  `request_fingerprint` char(64) DEFAULT NULL COMMENT '动作和桌号参数 SHA-256，用于防止幂等键误复用',
  `trace_id` varchar(128) DEFAULT NULL COMMENT '链路追踪标识',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_operation_log_cashier_idem` (`shop_id`,`module`,`action`,`request_key`),
  KEY `idx_admin_created` (`admin_id`,`created_at`),
  KEY `idx_module_action` (`module`,`action`),
  KEY `idx_operation_log_shop` (`shop_id`),
  KEY `idx_operation_log_cashier_trace` (`trace_id`),
  KEY `idx_operation_log_cashier_table_time` (`shop_id`,`source_table`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='关键操作日志';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_order` (
  `id` int NOT NULL AUTO_INCREMENT,
  `order_no` varchar(100) NOT NULL COMMENT '订单号',
  `table_number` varchar(50) DEFAULT NULL COMMENT '桌号',
  `number_of_diners` int DEFAULT NULL COMMENT '用餐人数',
  `sett_amount` decimal(6,2) NOT NULL COMMENT '计算总价',
  `transac_status` enum('success','unsettled','cancelled') NOT NULL COMMENT '结账状态：success/unsettled/cancelled',
  `order_receiving` enum('mis_order','rec_order','off_order','cancelled') NOT NULL COMMENT '接单状态：mis_order/rec_order/off_order/cancelled',
  `order_time` datetime NOT NULL COMMENT '下单时间',
  `dineInOrTakeOut` varchar(255) NOT NULL COMMENT '订单类型',
  `orderNumber` int NOT NULL COMMENT '下单次数\r\n',
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
  `shop_id` int DEFAULT NULL COMMENT '门店ID，关联 t_shop.id',
  `notice` int DEFAULT NULL COMMENT '通知取餐',
  `pay_openid` varbinary(255) DEFAULT NULL COMMENT '支付者',
  `discount_amount` decimal(8,2) DEFAULT NULL COMMENT '优惠金额',
  `off_time` datetime DEFAULT NULL COMMENT '订单完成时间',
  `service_fee` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '新年服务费/额外服务费',
  `refund_amount` decimal(10,2) DEFAULT NULL COMMENT '累计成功退款金额（元），由微信 /order/refund/notify 退款成功(SUCCESS)回调累加',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `order_no` (`order_no`) USING BTREE,
  KEY `OP` (`openid`) USING BTREE,
  KEY `idx_order_shop_time` (`shop_id`,`order_time`),
  KEY `idx_order_shop_openid` (`shop_id`,`openid`),
  KEY `idx_order_shop_table_status_id` (`shop_id`,`table_number`,`transac_status`,`id`),
  KEY `idx_order_fulfillment_retry` (`order_receiving`,`transac_status`,`order_time`,`id`),
  CONSTRAINT `OP` FOREIGN KEY (`openid`) REFERENCES `t_user` (`openid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_order_client_request` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `admin_id` int DEFAULT NULL,
  `client_request_id` varchar(128) NOT NULL,
  `request_path` varchar(128) NOT NULL,
  `request_fingerprint` char(64) DEFAULT NULL COMMENT 'SHA-256 of the canonical request body',
  `status` varchar(16) NOT NULL DEFAULT 'PROCESSING',
  `response_snapshot` longtext,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_order_client_request` (`shop_id`,`client_request_id`) USING BTREE,
  KEY `idx_order_client_request_expiry` (`expires_at`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='收银APP写请求24小时幂等账本';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_order_detail` (
  `id` int NOT NULL AUTO_INCREMENT COMMENT '编号',
  `mId` int DEFAULT NULL COMMENT '订单主表ID',
  `name` varchar(100) DEFAULT NULL COMMENT '菜品名称',
  `quantity` int DEFAULT NULL COMMENT '数量',
  `refunded_quantity` int NOT NULL DEFAULT '0' COMMENT 'Cumulative refunded quantity',
  `unit` varchar(11) DEFAULT NULL COMMENT '单位',
  `image` varchar(100) DEFAULT NULL COMMENT '菜品图片',
  `total_price` decimal(6,2) DEFAULT NULL COMMENT '总价',
  `Morder_no` varchar(100) DEFAULT NULL,
  `Morder_num` int DEFAULT NULL,
  `order_rece` varchar(255) DEFAULT NULL,
  `line_status` varchar(16) NOT NULL DEFAULT 'normal' COMMENT 'normal|refunded',
  `remark` varchar(255) DEFAULT NULL,
  `selectedSpicy` varchar(255) DEFAULT NULL,
  `cid` varchar(255) DEFAULT NULL,
  `client_line_id` varchar(64) DEFAULT NULL COMMENT 'Cashier client line correlation ID',
  `dish_id` int DEFAULT NULL COMMENT 't_dish.id，下单时写入；历史数据按 name 回填',
  `line_type` varchar(20) DEFAULT NULL COMMENT 'normal/combo_header/combo_component',
  `combo_id` bigint DEFAULT NULL COMMENT 't_combo.id',
  `combo_instance_id` varchar(40) DEFAULT NULL COMMENT '同一单同一套餐实例 UUID',
  `parent_detail_id` int DEFAULT NULL COMMENT 'combo 子行指向头行 t_order_detail.id',
  `combo_selection_json` varchar(2000) DEFAULT NULL COMMENT '套餐头行：用户选择(JSON)，便于复算与客服',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `mId` (`mId`) USING BTREE,
  KEY `/` (`Morder_no`) USING BTREE,
  KEY `idx_order_detail_combo_inst` (`mId`,`combo_instance_id`),
  KEY `idx_order_detail_line_type` (`line_type`),
  KEY `idx_order_detail_line_status` (`mId`,`line_status`),
  KEY `idx_order_detail_dish` (`dish_id`) USING BTREE,
  KEY `idx_order_detail_client_line` (`mId`,`client_line_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_order_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `order_no` varchar(100) NOT NULL,
  `shop_id` int DEFAULT NULL COMMENT '冗余门店，便于按店筛选',
  `action` varchar(32) NOT NULL COMMENT 'create/add_dish/refund/change_price/checkout/cancel等',
  `operator_type` varchar(16) DEFAULT NULL COMMENT 'openid/admin_id',
  `operator_id` varchar(64) DEFAULT NULL COMMENT 'openid 或 admin_id',
  `remark` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_order_no` (`order_no`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_order_log_shop_created` (`shop_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='订单操作日志';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_parking_plate` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT '记录唯一ID（主键）',
  `plate_number` varchar(20) NOT NULL COMMENT '完整车牌号（如：粤A12345）',
  `plate_type` tinyint NOT NULL COMMENT '车牌类型 1-燃油车 2-新能源车',
  `user_id` int NOT NULL COMMENT '关联用户ID（外键，用户删除时同步删除车牌）',
  `province` varchar(10) NOT NULL COMMENT '车牌省份（如：粤）',
  `is_default` tinyint NOT NULL DEFAULT '0' COMMENT '是否默认车牌 0-否 1-是',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `is_delete` tinyint NOT NULL DEFAULT '0' COMMENT '是否删除 0-未删 1-已删',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_plate_user` (`plate_number`,`user_id`) USING BTREE COMMENT '用户+车牌唯一索引（避免重复绑定）',
  KEY `idx_user_id` (`user_id`) USING BTREE COMMENT '用户ID索引（查询提速）',
  CONSTRAINT `fk_plate_user` FOREIGN KEY (`user_id`) REFERENCES `t_user` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='车牌信息表（用户-车牌关联）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `order_no` varchar(100) NOT NULL COMMENT '订单号',
  `payment_method` varchar(32) NOT NULL COMMENT '支付方式',
  `amount` decimal(10,2) NOT NULL COMMENT '支付金额',
  `transaction_id` varchar(64) DEFAULT NULL COMMENT '第三方交易号',
  `pay_time` datetime DEFAULT NULL COMMENT '支付时间',
  `operator_id` int DEFAULT NULL COMMENT '收银员/操作员 admin_id',
  `shop_id` int DEFAULT NULL COMMENT '门店ID，可选',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_order_no` (`order_no`),
  KEY `idx_pay_time` (`pay_time`),
  KEY `idx_shop_id` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='支付记录（对账用）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment_capability` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL DEFAULT '0' COMMENT '0=全门店默认',
  `online_pay_enabled` tinyint NOT NULL DEFAULT '1' COMMENT '线上支付总开关（微信/支付宝/余额）',
  `wechat_enabled` tinyint NOT NULL DEFAULT '1',
  `alipay_enabled` tinyint NOT NULL DEFAULT '0' COMMENT '支付宝官方支付，P3 启用',
  `balance_enabled` tinyint NOT NULL DEFAULT '1',
  `combined_enabled` tinyint NOT NULL DEFAULT '1' COMMENT '线上组合支付开关',
  `cashier_pay_enabled` tinyint DEFAULT NULL COMMENT '收银端支付总开关',
  `cashier_wechat_enabled` tinyint DEFAULT NULL COMMENT '收银端微信支付',
  `cashier_alipay_enabled` tinyint DEFAULT NULL COMMENT '收银端支付宝支付',
  `cashier_balance_enabled` tinyint DEFAULT NULL COMMENT '收银端余额支付',
  `cashier_combined_enabled` tinyint DEFAULT NULL COMMENT '收银端组合支付',
  `mini_program_pay_enabled` tinyint DEFAULT NULL COMMENT '微信小程序端支付总开关',
  `mini_program_wechat_enabled` tinyint DEFAULT NULL COMMENT '微信小程序端微信支付',
  `mini_program_balance_enabled` tinyint DEFAULT NULL COMMENT '微信小程序端余额支付',
  `offline_collect_enabled` tinyint NOT NULL DEFAULT '1',
  `offline_collect_channels` varchar(32) NOT NULL DEFAULT 'wechat,alipay',
  `disabled_message` varchar(255) NOT NULL DEFAULT '请联系服务员结账',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店支付能力开关';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment_merchant_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL DEFAULT '0' COMMENT '0=全门店默认，>0=t_shop.id',
  `channel` varchar(16) NOT NULL COMMENT 'wechat|alipay',
  `merchant_key` varchar(32) NOT NULL COMMENT '实例键，如 default、small_amount',
  `enabled` tinyint NOT NULL DEFAULT '1',
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
  `sort_order` int NOT NULL DEFAULT '0',
  `remark` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_channel_key` (`shop_id`,`channel`,`merchant_key`) USING BTREE,
  KEY `idx_shop_channel` (`shop_id`,`channel`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='支付商户配置（连锁按 shop_id 覆盖）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment_method` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT 'NULL=全局；非空=仅该门店',
  `code` varchar(32) NOT NULL COMMENT '编码：wechat/alipay/cash/member_card/charge_account',
  `name` varchar(32) NOT NULL COMMENT '显示名称',
  `sort_order` int DEFAULT '0',
  `enabled` tinyint NOT NULL DEFAULT '1' COMMENT '0-禁用 1-启用',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code` (`code`),
  KEY `idx_payment_method_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='支付方式';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment_ninefold_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL DEFAULT '0' COMMENT '0=全店默认',
  `enabled` tinyint NOT NULL DEFAULT '0' COMMENT '夜间九折独立开关',
  `pay_rate` decimal(5,4) NOT NULL DEFAULT '0.9000' COMMENT '实付倍率，0.9=九折',
  `min_base_yuan` decimal(10,2) NOT NULL DEFAULT '60.00' COMMENT '券后满额(元)才叠九折',
  `time_start` varchar(8) NOT NULL DEFAULT '00:30',
  `time_end` varchar(8) NOT NULL DEFAULT '03:00',
  `zone_id` varchar(64) NOT NULL DEFAULT 'Asia/Shanghai',
  `eligible_dining_types` varchar(256) NOT NULL DEFAULT '["堂食"]',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店夜间九折配置';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment_refund_guard` (
  `shop_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `idempotency_key` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`,`order_no`),
  KEY `idx_payment_refund_guard_key` (`shop_id`,`idempotency_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_payment_refund_request` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `order_no` varchar(64) NOT NULL,
  `idempotency_key` varchar(64) NOT NULL,
  `out_refund_no` varchar(64) NOT NULL,
  `requested_fen` int NOT NULL,
  `applied_fen` int NOT NULL DEFAULT '0',
  `status` varchar(24) NOT NULL DEFAULT 'REQUESTED',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_refund_idempotency` (`shop_id`,`idempotency_key`),
  UNIQUE KEY `uk_payment_refund_out_no` (`out_refund_no`),
  KEY `idx_payment_refund_order` (`shop_id`,`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_permission` (
  `id` int NOT NULL AUTO_INCREMENT,
  `permission_code` varchar(64) NOT NULL COMMENT '权限编码，如 order:view, dish:manage',
  `permission_name` varchar(64) NOT NULL COMMENT '权限名称',
  `module` varchar(32) DEFAULT NULL COMMENT '模块：order/dish/statistics等',
  `remark` varchar(255) DEFAULT NULL,
  `sort_order` int DEFAULT '0',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_permission_code` (`permission_code`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='权限表';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_queue_ticket` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ticket_no` varchar(32) NOT NULL COMMENT '排队号，如 A102',
  `shop_id` int NOT NULL DEFAULT '1' COMMENT '门店ID，连锁按门店隔离',
  `openid` varchar(100) NOT NULL COMMENT '用户 openid',
  `mobile` varchar(20) NOT NULL COMMENT '手机号',
  `party_size` int NOT NULL COMMENT '就餐人数',
  `dine_type` varchar(32) NOT NULL COMMENT '就餐方式，如 dinein',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `status` enum('waiting','calling','seated','cancelled','expired') NOT NULL DEFAULT 'waiting' COMMENT '排队状态',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_ticket_no` (`shop_id`,`ticket_no`) USING BTREE,
  KEY `idx_shop_status_created` (`shop_id`,`status`,`created_at`) USING BTREE,
  KEY `idx_openid_created` (`openid`,`created_at`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='排队取号记录';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(32) NOT NULL COMMENT '区域编码（唯一）',
  `name` varchar(64) NOT NULL COMMENT '区域名称',
  `parent_id` int DEFAULT NULL COMMENT '父区域ID，可空',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_region_code` (`code`),
  KEY `idx_region_parent` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='区域主数据';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_role` (
  `id` int NOT NULL AUTO_INCREMENT,
  `role_code` varchar(32) NOT NULL COMMENT '角色编码，如 super_admin, order_manager',
  `role_name` varchar(64) NOT NULL COMMENT '角色名称',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `sort_order` int DEFAULT '0' COMMENT '排序',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_role_code` (`role_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='角色表';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_role_permission` (
  `id` int NOT NULL AUTO_INCREMENT,
  `role_id` int NOT NULL,
  `permission_id` int NOT NULL,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_role_permission` (`role_id`,`permission_id`) USING BTREE,
  KEY `idx_permission_id` (`permission_id`) USING BTREE,
  CONSTRAINT `fk_role_permission_perm` FOREIGN KEY (`permission_id`) REFERENCES `t_permission` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_role_permission_role` FOREIGN KEY (`role_id`) REFERENCES `t_role` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='角色-权限关联';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_shift` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL COMMENT '收银员',
  `shop_id` int DEFAULT NULL,
  `start_time` datetime NOT NULL COMMENT '班次开始',
  `end_time` datetime DEFAULT NULL COMMENT '班次结束',
  `start_cash` decimal(10,2) DEFAULT '0.00' COMMENT '开班现金',
  `end_cash` decimal(10,2) DEFAULT NULL COMMENT '交班现金',
  `order_count` int DEFAULT '0',
  `total_amount` decimal(12,2) DEFAULT '0.00',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_admin_start` (`admin_id`,`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='收银员交班';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_shop` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL COMMENT '门店名称',
  `code` varchar(32) DEFAULT NULL COMMENT '门店编码',
  `region_id` int DEFAULT NULL COMMENT '区域ID，关联 t_region.id',
  `address` varchar(255) DEFAULT NULL COMMENT '地址',
  `latitude` decimal(10,7) DEFAULT NULL COMMENT '纬度',
  `longitude` decimal(10,7) DEFAULT NULL COMMENT '经度',
  `contact_phone` varchar(20) DEFAULT NULL COMMENT '联系电话',
  `open_time` time DEFAULT NULL COMMENT '营业开始时间',
  `close_time` time DEFAULT NULL COMMENT '营业结束时间',
  `status` tinyint NOT NULL DEFAULT '1' COMMENT '状态：0-停用 1-营业',
  `sort_order` int NOT NULL DEFAULT '0' COMMENT '列表排序，越小越靠前',
  `ordering_open` tinyint NOT NULL DEFAULT '1' COMMENT 'C端接单营业：1营业 0休息',
  `ordering_review` tinyint NOT NULL DEFAULT '0' COMMENT 'C端评价展示：1开 0关',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `offline_collect_wechat_payload` varchar(2048) DEFAULT NULL COMMENT '微信个人收款码解码后的跳转串（如 wxp://）',
  `offline_collect_alipay_payload` varchar(2048) DEFAULT NULL COMMENT '支付宝收款码解码后的跳转串',
  `offline_collect_wechat_image_path` varchar(512) DEFAULT NULL COMMENT '上传的微信收款码图片相对/绝对路径（可选备份）',
  `offline_collect_alipay_image_path` varchar(512) DEFAULT NULL COMMENT '上传的支付宝收款码图片路径',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_code` (`code`),
  KEY `idx_shop_status_sort` (`status`,`sort_order`,`id`),
  KEY `idx_shop_region` (`region_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店表（多店）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_category_shop` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `category_id` int NOT NULL COMMENT 't_category.id',
  `sorting_override` int NOT NULL COMMENT '当前门店分类顺序，1-based',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_category_shop` (`shop_id`,`category_id`),
  KEY `idx_category_shop_category` (`category_id`),
  CONSTRAINT `fk_category_shop_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_category_shop_category` FOREIGN KEY (`category_id`) REFERENCES `t_category` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店分类排序覆盖';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_shop_printer_config` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT '门店ID，关联 t_shop.id',
  `feie_url` varchar(255) DEFAULT NULL COMMENT '飞鹅云 API 地址，空则回退系统全局 feieyun.url',
  `feie_user` varchar(128) NOT NULL COMMENT '飞鹅云 user',
  `feie_ukey` varchar(128) NOT NULL COMMENT '飞鹅云 ukey',
  `printer_sn` varchar(64) NOT NULL COMMENT '门店默认打印机 SN',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_id` (`shop_id`) USING BTREE,
  CONSTRAINT `fk_shop_printer_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='门店打印机配置（连锁隔离）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_shop_takeout_config` (
  `shop_id` int NOT NULL COMMENT 't_shop.id',
  `enabled` tinyint NOT NULL DEFAULT '0' COMMENT '1=开启外卖',
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '基础配送费（元）',
  `min_order_amount` decimal(10,2) NOT NULL DEFAULT '0.00' COMMENT '起送价（元，按商品小计不含配送费）',
  `free_delivery_threshold` decimal(10,2) DEFAULT NULL COMMENT '满额免配送费；NULL 表示不免',
  `max_delivery_distance_km` decimal(5,2) NOT NULL DEFAULT '5.00' COMMENT '最远配送距离(公里)，超出不可下单',
  `free_delivery_max_distance_km` decimal(5,2) NOT NULL DEFAULT '5.00' COMMENT '满额免配送费的最远距离(公里)',
  `delivery_fee_tiers_json` text COMMENT '距离阶梯运费 JSON，如 [{"toKm":3,"fee":5},{"toKm":4,"fee":8},{"toKm":5,"fee":10}]',
  `lead_time_minutes` int NOT NULL DEFAULT '30' COMMENT '预计备餐分钟（展示用）',
  `remark` varchar(500) DEFAULT NULL COMMENT '对外说明',
  `zsq_enabled` tinyint NOT NULL DEFAULT '0' COMMENT '1=启用真省钱聚合配送',
  `zsq_auto_dispatch` tinyint NOT NULL DEFAULT '1' COMMENT '1=商家接单后自动发真省钱配送',
  `zsq_from_address_id` bigint DEFAULT NULL COMMENT '真省钱发单店铺 id，空则用默认店铺',
  `zsq_city_name` varchar(64) DEFAULT NULL COMMENT '地址解析城市，空则取门店城市或江门市',
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店外卖配置';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_in` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT '门店ID',
  `material_id` int NOT NULL,
  `quantity` decimal(12,3) NOT NULL COMMENT '入库数量',
  `price` decimal(10,2) DEFAULT NULL COMMENT '单价（成本）',
  `total_amount` decimal(12,2) DEFAULT NULL COMMENT '总金额',
  `remark` varchar(255) DEFAULT NULL,
  `operator_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_material_id` (`material_id`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_stock_in_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='原材料入库';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_out` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT '门店ID',
  `material_id` int NOT NULL,
  `quantity` decimal(12,3) NOT NULL COMMENT '出库数量',
  `reason` varchar(32) DEFAULT NULL COMMENT '原因：consume/transfer/waste',
  `remark` varchar(255) DEFAULT NULL,
  `operator_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_material_id` (`material_id`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_stock_out_shop` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='原材料出库/消耗';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_prep_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL COMMENT '门店ID',
  `safe_stock_rate` decimal(5,2) NOT NULL DEFAULT '0.10' COMMENT '安全库存系数',
  `default_loss_rate` decimal(5,2) NOT NULL DEFAULT '0.05' COMMENT 'BOM未填损耗时的默认损耗率',
  `forecast_days` int NOT NULL DEFAULT '3' COMMENT '默认预测天数',
  `history_days` int NOT NULL DEFAULT '30' COMMENT '默认回溯天数',
  `weather_factor` decimal(5,2) NOT NULL DEFAULT '1.00' COMMENT '天气修正上限参考/扩展用',
  `holiday_factor` decimal(5,2) NOT NULL DEFAULT '1.20' COMMENT '节假日参考系数/扩展用',
  `member_factor` decimal(5,2) NOT NULL DEFAULT '1.00' COMMENT '会员客流热度系数(充值不计销量，仅乘在预测上)',
  `is_enabled` tinyint NOT NULL DEFAULT '1',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop` (`shop_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货规则配置表(按店)';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_prep_forecast_day` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `run_id` bigint NOT NULL COMMENT '批次ID',
  `stat_date` date NOT NULL COMMENT '预测自然日',
  `iso_day_of_week` tinyint NOT NULL COMMENT '周一=1…周日=7',
  `day_kind` varchar(64) NOT NULL COMMENT '工作日/周末/调休工作日(含补班说明)等',
  `is_holiday` tinyint NOT NULL DEFAULT '0' COMMENT '是否按法定节假日休息并施加节假日系数',
  `holiday_name` varchar(64) DEFAULT NULL COMMENT '节假日名称或自定义',
  `factor_holiday` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `factor_weather` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `factor_composite` decimal(8,4) NOT NULL DEFAULT '1.0000',
  `weather_available` tinyint NOT NULL DEFAULT '0',
  `weather_summary` varchar(256) DEFAULT NULL,
  `weather_code` int DEFAULT NULL,
  `weather_precip_prob` int DEFAULT NULL COMMENT '降水概率max %',
  `weather_temp_max` decimal(5,1) DEFAULT NULL COMMENT '预报最高温℃',
  `predicted_servings_sum` int DEFAULT NULL COMMENT '本批次当日预测菜品份数合计(预测范围内)',
  `actual_servings_forecast_dishes` int DEFAULT NULL COMMENT '预测范围内菜品当日实际份数合计',
  `actual_servings_all_dishes` int DEFAULT NULL COMMENT '当日全店订单明细销量合计(所有菜品)',
  `actual_order_count` int DEFAULT NULL COMMENT '当日成功单数',
  `daily_stat_total_amount` decimal(12,2) DEFAULT NULL COMMENT '日结表营业额 t_daily_stat.total_amount',
  `daily_stat_discount_amount` decimal(12,2) DEFAULT NULL COMMENT '日结优惠合计',
  `daily_stat_refund_amount` decimal(12,2) DEFAULT NULL COMMENT '日结退款合计',
  `daily_stat_material_cost` decimal(12,2) DEFAULT NULL COMMENT '日结原料成本',
  `daily_stat_settled` tinyint DEFAULT NULL COMMENT '1=日结已 settled_at 非空',
  `day_validated_at` datetime DEFAULT NULL COMMENT '该预测日本行校验完成时间',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_spf_day_run_date` (`run_id`,`stat_date`) USING BTREE,
  KEY `idx_spf_day_run` (`run_id`) USING BTREE,
  CONSTRAINT `fk_spf_day_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货预测-按日';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_prep_forecast_dish` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `run_id` bigint NOT NULL,
  `stat_date` date NOT NULL,
  `dish_id` int DEFAULT NULL COMMENT '匹配 t_dish.id，可能为空',
  `dish_name` varchar(100) NOT NULL,
  `baseline_avg` decimal(14,4) NOT NULL DEFAULT '0.0000' COMMENT '该日星期几基线日均份数',
  `predicted_servings` int NOT NULL DEFAULT '0' COMMENT '预测备货份数',
  `actual_quantity` int DEFAULT NULL COMMENT '当日该菜品实际销量(订单明细汇总)',
  `validated_at` datetime DEFAULT NULL COMMENT '写入实际销量的时间',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_spf_dish_run_date` (`run_id`,`stat_date`) USING BTREE,
  CONSTRAINT `fk_spf_dish_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货预测-按日按菜';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_prep_forecast_run` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT '门店ID，与订单统计一致；NULL 表示未按店过滤的汇总',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '生成时间',
  `history_days` int NOT NULL COMMENT '回溯天数',
  `forecast_days` int NOT NULL COMMENT '预测天数',
  `history_start_date` date NOT NULL COMMENT '历史统计起始日',
  `history_end_at` datetime NOT NULL COMMENT '历史统计结束时刻',
  `model_notes` varchar(500) DEFAULT NULL COMMENT '模型说明',
  `last_validated_at` datetime DEFAULT NULL COMMENT '最近一次校验写入时间',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_spf_run_shop_created` (`shop_id`,`created_at`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='备货预测运行批次';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_stock_prepare_plan` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '备货计划ID',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `run_id` bigint NOT NULL COMMENT '预测批次ID(t_stock_prep_forecast_run.id)',
  `prepare_date` date NOT NULL COMMENT '备货日期(与预测 stat_date 对齐)',
  `material_id` int NOT NULL COMMENT '原材料ID',
  `current_stock` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '生成时 t_material.stock 快照',
  `forecast_consume` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '预测消耗总量',
  `safe_stock` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '安全库存',
  `suggest_qty` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '系统建议备货量',
  `manual_adjust` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '人工调整量(±)',
  `final_qty` decimal(12,3) NOT NULL DEFAULT '0.000' COMMENT '最终确认备货量',
  `status` tinyint NOT NULL DEFAULT '0' COMMENT '0待确认 1已确认 2已采购 3已入库',
  `operator_id` int DEFAULT NULL COMMENT '操作员 t_admin.id',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_run_material_prepare_date` (`run_id`,`material_id`,`prepare_date`) USING BTREE,
  KEY `idx_shop_material_date` (`shop_id`,`material_id`,`prepare_date`) USING BTREE,
  KEY `idx_prepare_date` (`prepare_date`) USING BTREE,
  KEY `idx_status` (`status`) USING BTREE,
  CONSTRAINT `fk_prepare_run` FOREIGN KEY (`run_id`) REFERENCES `t_stock_prep_forecast_run` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='原材料备货计划表';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_system_config` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL DEFAULT '0' COMMENT '0=全门店默认，>0=t_shop.id',
  `config_key` varchar(100) NOT NULL COMMENT '配置键，如 feieyun.user、invite.poster.qr.x',
  `config_value` varchar(500) DEFAULT NULL COMMENT '配置值',
  `remark` varchar(255) DEFAULT NULL COMMENT '说明',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_shop_config_key` (`shop_id`,`config_key`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='系统配置（持久化 application.yml 覆盖项）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_table` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shop_id` int DEFAULT NULL COMMENT '门店ID；NULL 表示未迁移的历史数据',
  `number` varchar(20) DEFAULT NULL COMMENT '桌号',
  `open_time` datetime DEFAULT NULL COMMENT '开台时间',
  `qrcode` varchar(100) DEFAULT NULL COMMENT '二维码',
  `status` int(1) unsigned zerofill NOT NULL,
  `out_time` datetime DEFAULT NULL COMMENT '结账时间',
  `amount` decimal(6,2) DEFAULT NULL COMMENT '金额',
  `order_no` varchar(22) DEFAULT NULL COMMENT '订单号',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_table_shop_number` (`shop_id`,`number`) USING BTREE,
  KEY `number` (`number`) USING BTREE,
  KEY `idx_table_shop` (`shop_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_takeout_delivery` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `order_id` int NOT NULL COMMENT 't_order.id',
  `order_no` varchar(32) NOT NULL,
  `shop_id` int DEFAULT NULL,
  `user_address_id` bigint DEFAULT NULL COMMENT '下单时选用的 t_user_address.id',
  `receiver_name` varchar(32) DEFAULT NULL,
  `receiver_phone` varchar(20) NOT NULL,
  `address_full` varchar(512) NOT NULL,
  `lng` decimal(10,6) DEFAULT NULL,
  `lat` decimal(10,6) DEFAULT NULL,
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT '0.00',
  `dispatch_status` varchar(24) NOT NULL DEFAULT 'submitted' COMMENT 'submitted|paid|accepted|delivering|completed|cancelled',
  `merchant_remark` varchar(500) DEFAULT NULL,
  `zsq_open_order_id` bigint DEFAULT NULL COMMENT '真省钱 openOrderId（ZsqCreateOrderResult.id）',
  `zsq_order_id` varchar(64) DEFAULT NULL COMMENT '真省钱业务订单号',
  `zsq_shop_number` varchar(32) DEFAULT NULL COMMENT '真省钱发单店铺编号',
  `zsq_parent_order_no` varchar(64) DEFAULT NULL COMMENT '真省钱配送母单号',
  `zsq_delivery_codes_json` varchar(256) DEFAULT NULL COMMENT '已选配送渠道 deliveryCode JSON 数组',
  `zsq_quote_json` text COMMENT '最近一次询价快照 JSON',
  `zsq_dispatch_json` text COMMENT '最近一次发配送响应 JSON',
  `zsq_delivery_send_status` int DEFAULT NULL COMMENT '真省钱 deliverySendStatus 原始值',
  `zsq_phase` varchar(32) DEFAULT NULL COMMENT '归一化阶段 WAITING_RIDER/TO_SHOP/TO_USER/DELIVERED/CANCELLED',
  `zsq_dispatch_status` varchar(32) NOT NULL DEFAULT 'none' COMMENT 'none|pending|dispatched|failed|rider_cancelled|completed',
  `zsq_rider_name` varchar(64) DEFAULT NULL,
  `zsq_rider_phone` varchar(32) DEFAULT NULL,
  `zsq_rider_lat` decimal(10,6) DEFAULT NULL,
  `zsq_rider_lng` decimal(10,6) DEFAULT NULL,
  `zsq_rider_updated_at` datetime DEFAULT NULL,
  `zsq_last_error` varchar(512) DEFAULT NULL COMMENT '最近一次 ZSQ 错误文案',
  `zsq_dispatch_attempts` int NOT NULL DEFAULT '0' COMMENT '发配送尝试次数（含重发）',
  `zsq_liability_fee` decimal(10,2) DEFAULT NULL COMMENT '真省钱取消责任扣费（元）',
  `zsq_actual_fee` decimal(10,2) DEFAULT NULL COMMENT '真省钱实际跑腿费用（元，来自 shopActualCost/discountLastMoney）',
  `zsq_delivery_supplier_name` varchar(64) DEFAULT NULL COMMENT '真省钱实际配送运力渠道（如京东特惠、美团等，来自 deliverySupplierName）',
  `zsq_cancel_prompt` varchar(512) DEFAULT NULL COMMENT '真省钱取消提示文案',
  `zsq_cancel_json` text COMMENT '真省钱取消响应 JSON',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_takeout_order_id` (`order_id`),
  KEY `idx_takeout_shop_status` (`shop_id`,`dispatch_status`),
  KEY `idx_takeout_order_no` (`order_no`),
  KEY `idx_takeout_zsq_open_order` (`zsq_open_order_id`),
  KEY `idx_takeout_zsq_dispatch_status` (`zsq_dispatch_status`,`dispatch_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='外卖配送扩展（与 dineInOrTakeOut=外卖 的订单绑定）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_unit` (
  `id` int NOT NULL AUTO_INCREMENT,
  `label` varchar(100) DEFAULT NULL,
  `value` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_user` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) DEFAULT NULL,
  `openid` varchar(100) DEFAULT NULL,
  `phone` varchar(11) DEFAULT NULL,
  `points` int DEFAULT NULL,
  `balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '账户余额(元)',
  `gift_balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '赠送金余额(元)，与 balance 本金分开',
  `principal_balance` decimal(12,2) NOT NULL DEFAULT '0.00' COMMENT '本金(元)；balance=principal_balance+gift_balance',
  `session_key` varchar(255) DEFAULT NULL,
  `avatar` varchar(255) DEFAULT NULL,
  `time` datetime DEFAULT NULL COMMENT '注册时间',
  `user_type` int DEFAULT NULL COMMENT '用户类型：0普通/1会员',
  `invite_code` varchar(10) DEFAULT NULL,
  `level` int DEFAULT NULL COMMENT '会员等级',
  `birthday` varchar(10) DEFAULT NULL COMMENT '生日',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `openid` (`openid`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_user_activity_interaction` (
  `id` int NOT NULL,
  `user_id` varchar(255) DEFAULT NULL COMMENT '用户ID（与用户表id对应）',
  `activity_id` varchar(255) DEFAULT NULL COMMENT '活动ID（与活动表id对应）',
  `interaction_type` varchar(255) DEFAULT NULL COMMENT '交互类型：show(展示)/click(点击)/close(关闭)',
  `interaction_time` varchar(255) DEFAULT NULL COMMENT '交互时间',
  `date` datetime DEFAULT NULL COMMENT '交互日期（用于按日过滤）',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_user_address` (
  `id` bigint NOT NULL AUTO_INCREMENT,
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
  `is_default` tinyint NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_address_openid` (`openid`),
  KEY `idx_user_address_openid_default` (`openid`,`is_default`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='小程序用户收货地址';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_user_coupon` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `user_openid` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT '用户微信openid',
  `coupon_id` bigint NOT NULL COMMENT '关联优惠券主表ID',
  `get_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '领取时间',
  `use_time` datetime DEFAULT NULL COMMENT '使用时间（NULL为未使用）',
  `order_no` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT '关联订单号（使用后填充）',
  `status` tinyint NOT NULL DEFAULT '0' COMMENT '状态：0-未使用 1-已使用 2-已失效',
  `expire_time` datetime DEFAULT NULL COMMENT '优惠券失效时间（程序关联主表end_time填充）',
  PRIMARY KEY (`id`) USING BTREE,
  KEY `idx_user_openid` (`user_openid`) USING BTREE COMMENT '用户openid索引',
  KEY `idx_coupon_id` (`coupon_id`) USING BTREE COMMENT '优惠券ID索引',
  KEY `idx_status` (`status`) USING BTREE COMMENT '状态索引',
  KEY `idx_get_time` (`get_time`) USING BTREE COMMENT '领取时间索引',
  KEY `idx_expire_time` (`expire_time`) USING BTREE COMMENT '失效时间索引',
  CONSTRAINT `fk_user_coupon_coupon_id` FOREIGN KEY (`coupon_id`) REFERENCES `t_coupon` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC COMMENT='用户优惠券关联表（关联优惠券主表）';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE IF NOT EXISTS `t_user_last_shop` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `openid` varchar(100) NOT NULL COMMENT 't_user.openid',
  `shop_id` int NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_openid` (`openid`),
  KEY `idx_shop` (`shop_id`),
  CONSTRAINT `fk_uls_shop` FOREIGN KEY (`shop_id`) REFERENCES `t_shop` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='用户上次选择门店';
/*!40101 SET character_set_client = @saved_cs_client */;

-- ---------- 第 2 部分：已存在表逐列补字段（不存在才添加） ----------
CALL `p_add_col_if_missing`('t_activity_popup','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'活动ID\' FIRST');
CALL `p_add_col_if_missing`('t_activity_popup','name','`name` varchar(100) NOT NULL COMMENT \'活动名称\' AFTER `id`');
CALL `p_add_col_if_missing`('t_activity_popup','popup_image','`popup_image` varchar(255) NOT NULL COMMENT \'弹窗图片\' AFTER `name`');
CALL `p_add_col_if_missing`('t_activity_popup','image_url','`image_url` varchar(255) NULL DEFAULT NULL COMMENT \'点击跳转地址\' AFTER `popup_image`');
CALL `p_add_col_if_missing`('t_activity_popup','target_user','`target_user` varchar(20) NOT NULL DEFAULT \'all\' COMMENT \'目标用户：new/member/all\' AFTER `image_url`');
CALL `p_add_col_if_missing`('t_activity_popup','start_time','`start_time` datetime NOT NULL COMMENT \'开始时间\' AFTER `target_user`');
CALL `p_add_col_if_missing`('t_activity_popup','end_time','`end_time` datetime NOT NULL COMMENT \'结束时间\' AFTER `start_time`');
CALL `p_add_col_if_missing`('t_activity_popup','is_enabled','`is_enabled` tinyint(1) NOT NULL DEFAULT 1 COMMENT \'是否启用：1-启用 0-禁用\' AFTER `end_time`');
CALL `p_add_col_if_missing`('t_activity_popup','budget_amount','`budget_amount` decimal(12,2) NULL DEFAULT NULL COMMENT \'活动投入预算(元)，用于ROI\' AFTER `is_enabled`');
CALL `p_add_col_if_missing`('t_activity_popup','max_show_count','`max_show_count` int NOT NULL DEFAULT 1 COMMENT \'单日最大展示次数\' AFTER `budget_amount`');
CALL `p_add_col_if_missing`('t_activity_popup','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'创建时间\' AFTER `max_show_count`');
CALL `p_add_col_if_missing`('t_activity_popup','sorting','`sorting` int NOT NULL AFTER `created_at`');
CALL `p_add_col_if_missing`('t_activity_popup','type','`type` enum(\'home_top\',\'home_bottom\',\'page_top\',\'page_hor\',\'page_activity\',\'invite_top\') NOT NULL COMMENT \'轮播图：home_top/home_bottom/page_top/page_hor/page_activity/invite_top\' AFTER `sorting`');
CALL `p_add_col_if_missing`('t_activity_popup','apply_shop_ids','`apply_shop_ids` varchar(500) NULL DEFAULT NULL COMMENT \'适用门店 JSON 数组，如 [1,5,3]；NULL/空/[]=全部门店\' AFTER `type`');
CALL `p_add_col_if_missing`('t_admin','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_admin','userName','`userName` varchar(22) NULL DEFAULT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_admin','work_no','`work_no` varchar(32) NULL DEFAULT NULL COMMENT \'员工工号，用于工号登录\' AFTER `userName`');
CALL `p_add_col_if_missing`('t_admin','real_name','`real_name` varchar(64) NULL DEFAULT NULL COMMENT \'员工真实姓名，系统各处操作人展示此姓名\' AFTER `work_no`');
CALL `p_add_col_if_missing`('t_admin','job_title','`job_title` varchar(64) NULL DEFAULT NULL COMMENT \'员工岗位/职位\' AFTER `real_name`');
CALL `p_add_col_if_missing`('t_admin','password','`password` varchar(255) NULL DEFAULT NULL COMMENT \'密码（BCrypt 或历史明文）\' AFTER `job_title`');
CALL `p_add_col_if_missing`('t_admin','token_version','`token_version` int NOT NULL DEFAULT 0 COMMENT \'管理员令牌版本，递增后旧令牌立即失效\' AFTER `password`');
CALL `p_add_col_if_missing`('t_admin_region','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_admin_region','admin_id','`admin_id` int NOT NULL COMMENT \'管理员ID，t_admin.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_admin_region','region_id','`region_id` int NOT NULL COMMENT \'区域ID，t_region.id\' AFTER `admin_id`');
CALL `p_add_col_if_missing`('t_admin_role','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_admin_role','admin_id','`admin_id` int NOT NULL COMMENT \'t_admin.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_admin_role','role_id','`role_id` int NOT NULL COMMENT \'t_role.id\' AFTER `admin_id`');
CALL `p_add_col_if_missing`('t_admin_shop','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_admin_shop','admin_id','`admin_id` int NOT NULL COMMENT \'t_admin.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_admin_shop','shop_id','`shop_id` int NOT NULL COMMENT \'t_shop.id\' AFTER `admin_id`');
CALL `p_add_col_if_missing`('t_announcement','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_announcement','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'NULL=全部门店可见；非空=仅该门店\' AFTER `id`');
CALL `p_add_col_if_missing`('t_announcement','title','`title` varchar(200) NOT NULL COMMENT \'标题\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_announcement','content','`content` longtext NOT NULL COMMENT \'正文（纯文本或富文本 HTML，由前端约定）\' AFTER `title`');
CALL `p_add_col_if_missing`('t_announcement','status','`status` tinyint NOT NULL DEFAULT 1 COMMENT \'1=启用 0=停用\' AFTER `content`');
CALL `p_add_col_if_missing`('t_announcement','sort_order','`sort_order` int NOT NULL DEFAULT 0 COMMENT \'越小越靠前\' AFTER `status`');
CALL `p_add_col_if_missing`('t_announcement','start_time','`start_time` datetime NULL DEFAULT NULL COMMENT \'可见开始时间，NULL=不限制\' AFTER `sort_order`');
CALL `p_add_col_if_missing`('t_announcement','end_time','`end_time` datetime NULL DEFAULT NULL COMMENT \'可见结束时间，NULL=不限制\' AFTER `start_time`');
CALL `p_add_col_if_missing`('t_announcement','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `end_time`');
CALL `p_add_col_if_missing`('t_announcement','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_api_permission','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_api_permission','method','`method` varchar(10) NOT NULL COMMENT \'GET/POST/PUT/DELETE\' AFTER `id`');
CALL `p_add_col_if_missing`('t_api_permission','path_pattern','`path_pattern` varchar(255) NOT NULL COMMENT \'路径，如 /admin/order/list\' AFTER `method`');
CALL `p_add_col_if_missing`('t_api_permission','permission_code','`permission_code` varchar(64) NOT NULL COMMENT \'所需权限码\' AFTER `path_pattern`');
CALL `p_add_col_if_missing`('t_banner','id','`id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_banner','image','`image` varchar(255) NULL DEFAULT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_banner','url','`url` varchar(255) NULL DEFAULT NULL AFTER `image`');
CALL `p_add_col_if_missing`('t_banner','status','`status` int NULL DEFAULT NULL AFTER `url`');
CALL `p_add_col_if_missing`('t_banner','type','`type` varchar(10) NOT NULL COMMENT \'首页：home，底部：bottom\' AFTER `status`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','order_no','`order_no` varchar(64) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','session_id','`session_id` varchar(64) NOT NULL AFTER `order_no`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','channel','`channel` varchar(16) NOT NULL AFTER `session_id`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','amount_fen','`amount_fen` int NOT NULL AFTER `channel`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','status','`status` varchar(24) NOT NULL DEFAULT \'PENDING\' AFTER `amount_fen`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','expires_at','`expires_at` datetime NOT NULL AFTER `status`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `expires_at`');
CALL `p_add_col_if_missing`('t_cashier_collection_intent','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_category','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_category','label','`label` varchar(30) NULL DEFAULT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_category','value','`value` varchar(30) NULL DEFAULT NULL AFTER `label`');
CALL `p_add_col_if_missing`('t_category','count','`count` int NULL DEFAULT NULL AFTER `value`');
CALL `p_add_col_if_missing`('t_category','sele_quantity','`sele_quantity` int NULL DEFAULT 0 AFTER `count`');
CALL `p_add_col_if_missing`('t_category','cid','`cid` varchar(30) NULL DEFAULT NULL AFTER `sele_quantity`');
CALL `p_add_col_if_missing`('t_category','sorting','`sorting` int NULL DEFAULT NULL COMMENT \'排序\' AFTER `cid`');
CALL `p_add_col_if_missing`('t_combo','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_combo','dish_id','`dish_id` int NOT NULL COMMENT \'套餐头菜品 t_dish.id，唯一\' AFTER `id`');
CALL `p_add_col_if_missing`('t_combo','combo_type','`combo_type` varchar(16) NOT NULL DEFAULT \'groups\' COMMENT \'fixed=仅固定子项; groups=含可选组\' AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_combo','status','`status` tinyint NOT NULL DEFAULT 1 COMMENT \'1启用 0停用\' AFTER `combo_type`');
CALL `p_add_col_if_missing`('t_combo','limit_per_order','`limit_per_order` int NULL DEFAULT NULL COMMENT \'单笔订单限购份数，NULL或<=0表示不限\' AFTER `status`');
CALL `p_add_col_if_missing`('t_combo','limit_per_user','`limit_per_user` int NULL DEFAULT NULL COMMENT \'单用户限购份数，NULL或<=0表示不限\' AFTER `limit_per_order`');
CALL `p_add_col_if_missing`('t_combo','limit_cycle','`limit_cycle` varchar(20) NOT NULL DEFAULT \'daily\' COMMENT \'用户限购周期：daily(每日)|lifetime(终生)\' AFTER `limit_per_user`');
CALL `p_add_col_if_missing`('t_combo','start_time','`start_time` datetime NULL DEFAULT NULL COMMENT \'活动生效开始时间，NULL表示不限\' AFTER `limit_cycle`');
CALL `p_add_col_if_missing`('t_combo','end_time','`end_time` datetime NULL DEFAULT NULL COMMENT \'活动生效截止时间，NULL表示不限\' AFTER `start_time`');
CALL `p_add_col_if_missing`('t_combo','available_days','`available_days` varchar(32) NULL DEFAULT NULL COMMENT \'可用星期，逗号分隔，NULL表示不限\' AFTER `end_time`');
CALL `p_add_col_if_missing`('t_combo','time_range_start','`time_range_start` varchar(16) NULL DEFAULT NULL COMMENT \'每日可用起始时段，如 11:00\' AFTER `available_days`');
CALL `p_add_col_if_missing`('t_combo','time_range_end','`time_range_end` varchar(16) NULL DEFAULT NULL COMMENT \'每日可用截止时段，如 14:00\' AFTER `time_range_start`');
CALL `p_add_col_if_missing`('t_combo','apply_dining_type','`apply_dining_type` varchar(20) NOT NULL DEFAULT \'all\' COMMENT \'适用就餐方式：all|dine_in|take_out\' AFTER `time_range_end`');
CALL `p_add_col_if_missing`('t_combo','allow_coupon','`allow_coupon` tinyint NOT NULL DEFAULT 1 COMMENT \'是否允许叠加优惠券：1允许 0禁止\' AFTER `apply_dining_type`');
CALL `p_add_col_if_missing`('t_combo','daily_stock','`daily_stock` int NULL DEFAULT NULL COMMENT \'每日套餐配额，NULL表示不限\' AFTER `allow_coupon`');
CALL `p_add_col_if_missing`('t_combo','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `daily_stock`');
CALL `p_add_col_if_missing`('t_combo','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_combo_fixed_item','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_combo_fixed_item','combo_id','`combo_id` bigint NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_combo_fixed_item','component_dish_id','`component_dish_id` int NOT NULL COMMENT \'子菜 t_dish.id\' AFTER `combo_id`');
CALL `p_add_col_if_missing`('t_combo_fixed_item','qty_per_combo','`qty_per_combo` int NOT NULL DEFAULT 1 COMMENT \'每份套餐含该子菜份数\' AFTER `component_dish_id`');
CALL `p_add_col_if_missing`('t_combo_fixed_item','sort_order','`sort_order` int NOT NULL DEFAULT 0 AFTER `qty_per_combo`');
CALL `p_add_col_if_missing`('t_combo_group','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_combo_group','combo_id','`combo_id` bigint NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_combo_group','group_key','`group_key` varchar(32) NOT NULL COMMENT \'与下单 combo_selections 的 key 对应\' AFTER `combo_id`');
CALL `p_add_col_if_missing`('t_combo_group','title','`title` varchar(64) NULL DEFAULT NULL COMMENT \'展示标题\' AFTER `group_key`');
CALL `p_add_col_if_missing`('t_combo_group','min_pick','`min_pick` int NOT NULL DEFAULT 1 AFTER `title`');
CALL `p_add_col_if_missing`('t_combo_group','max_pick','`max_pick` int NOT NULL DEFAULT 1 AFTER `min_pick`');
CALL `p_add_col_if_missing`('t_combo_group','sort_order','`sort_order` int NOT NULL DEFAULT 0 AFTER `max_pick`');
CALL `p_add_col_if_missing`('t_combo_group_item','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_combo_group_item','group_id','`group_id` bigint NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_combo_group_item','component_dish_id','`component_dish_id` int NOT NULL AFTER `group_id`');
CALL `p_add_col_if_missing`('t_combo_group_item','extra_price','`extra_price` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT \'相对套餐基准价的加价(元)/每份套餐\' AFTER `component_dish_id`');
CALL `p_add_col_if_missing`('t_combo_group_item','sort_order','`sort_order` int NOT NULL DEFAULT 0 AFTER `extra_price`');
CALL `p_add_col_if_missing`('t_coupon','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'主键ID\' FIRST');
CALL `p_add_col_if_missing`('t_coupon','coupon_name','`coupon_name` varchar(100) NOT NULL COMMENT \'优惠券名称（如：满50减10）\' AFTER `id`');
CALL `p_add_col_if_missing`('t_coupon','coupon_type','`coupon_type` varchar(20) NOT NULL COMMENT \'优惠券类型：full_reduction-满减 discount-折扣 direct_reduction-立减\' AFTER `coupon_name`');
CALL `p_add_col_if_missing`('t_coupon','apply_dining_type','`apply_dining_type` enum(\'all\',\'dine_in\',\'take_out\') NOT NULL DEFAULT \'all\' COMMENT \'\\\'适用用餐方式：all=全部，dine_in=仅限堂食，take_out=仅限打包\\\'\' AFTER `coupon_type`');
CALL `p_add_col_if_missing`('t_coupon','apply_dish_ids','`apply_dish_ids` varchar(1000) NULL DEFAULT NULL COMMENT \'适用菜品ID数组（JSON字符串），为空表示不限菜品，如 [1,2,3]\' AFTER `apply_dining_type`');
CALL `p_add_col_if_missing`('t_coupon','apply_shop_ids','`apply_shop_ids` varchar(1000) NULL DEFAULT NULL COMMENT \'适用门店ID JSON 数组，如 [1,2]；空/NULL 不限门店\' AFTER `apply_dish_ids`');
CALL `p_add_col_if_missing`('t_coupon','discount_value','`discount_value` decimal(10,2) NOT NULL COMMENT \'优惠值：满减/立减为金额，折扣为百分比（如80=8折）\' AFTER `apply_shop_ids`');
CALL `p_add_col_if_missing`('t_coupon','min_amount','`min_amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT \'使用门槛（满X元可用），0为无门槛\' AFTER `discount_value`');
CALL `p_add_col_if_missing`('t_coupon','start_time','`start_time` datetime NOT NULL COMMENT \'生效时间\' AFTER `min_amount`');
CALL `p_add_col_if_missing`('t_coupon','end_time','`end_time` datetime NOT NULL COMMENT \'失效时间\' AFTER `start_time`');
CALL `p_add_col_if_missing`('t_coupon','status','`status` tinyint NOT NULL DEFAULT 1 COMMENT \'状态：0-未启用 1-可用 2-已下架\' AFTER `end_time`');
CALL `p_add_col_if_missing`('t_coupon','stock','`stock` int NOT NULL DEFAULT -1 COMMENT \'库存：-1为无限库存，>=0为有限库存\' AFTER `status`');
CALL `p_add_col_if_missing`('t_coupon','granted_count','`granted_count` int NOT NULL DEFAULT 0 COMMENT \'已发放张数（写入 t_user_coupon 累计）\' AFTER `stock`');
CALL `p_add_col_if_missing`('t_coupon','description','`description` varchar(500) NULL DEFAULT \'\' COMMENT \'优惠券描述\' AFTER `granted_count`');
CALL `p_add_col_if_missing`('t_coupon','create_time','`create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'创建时间\' AFTER `description`');
CALL `p_add_col_if_missing`('t_coupon','update_time','`update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT \'更新时间\' AFTER `create_time`');
CALL `p_add_col_if_missing`('t_coupon','validity_time','`validity_time` bigint NOT NULL COMMENT \'有效期，单位小时\' AFTER `update_time`');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'主键ID\' FIRST');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','coupon_id','`coupon_id` bigint NOT NULL COMMENT \'关联优惠券ID（t_coupon.id）\' AFTER `id`');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','redeem_code','`redeem_code` varchar(64) NOT NULL COMMENT \'兑换码（唯一）\' AFTER `coupon_id`');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','status','`status` tinyint NOT NULL DEFAULT 0 COMMENT \'状态：0-未使用 1-已使用\' AFTER `redeem_code`');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','used_openid','`used_openid` varchar(100) NULL DEFAULT NULL COMMENT \'使用者openid\' AFTER `status`');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','used_time','`used_time` datetime NULL DEFAULT NULL COMMENT \'使用时间\' AFTER `used_openid`');
CALL `p_add_col_if_missing`('t_coupon_redeem_code','create_time','`create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'创建时间\' AFTER `used_time`');
CALL `p_add_col_if_missing`('t_daily_stat','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_daily_stat','stat_date','`stat_date` date NOT NULL COMMENT \'统计日期\' AFTER `id`');
CALL `p_add_col_if_missing`('t_daily_stat','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID，NULL表示全店\' AFTER `stat_date`');
CALL `p_add_col_if_missing`('t_daily_stat','total_amount','`total_amount` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'营业额\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_daily_stat','discount_amount','`discount_amount` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'优惠/折扣合计\' AFTER `total_amount`');
CALL `p_add_col_if_missing`('t_daily_stat','refund_amount','`refund_amount` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'退款合计\' AFTER `discount_amount`');
CALL `p_add_col_if_missing`('t_daily_stat','material_cost','`material_cost` decimal(12,2) NULL DEFAULT NULL COMMENT \'当日原材料成本\' AFTER `refund_amount`');
CALL `p_add_col_if_missing`('t_daily_stat','settled_at','`settled_at` datetime NULL DEFAULT NULL COMMENT \'日结时间\' AFTER `material_cost`');
CALL `p_add_col_if_missing`('t_daily_stat','operator_id','`operator_id` int NULL DEFAULT NULL COMMENT \'日结操作员\' AFTER `settled_at`');
CALL `p_add_col_if_missing`('t_daily_stat','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_dish','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_dish','name','`name` varchar(50) NULL DEFAULT NULL COMMENT \'菜品名称\' AFTER `id`');
CALL `p_add_col_if_missing`('t_dish','image','`image` varchar(50) NULL DEFAULT NULL COMMENT \'菜品图片\' AFTER `name`');
CALL `p_add_col_if_missing`('t_dish','typeId','`typeId` int NULL DEFAULT NULL COMMENT \'类别ID\' AFTER `image`');
CALL `p_add_col_if_missing`('t_dish','monthlysale','`monthlysale` int NULL DEFAULT 0 COMMENT \'商品销售量\' AFTER `typeId`');
CALL `p_add_col_if_missing`('t_dish','unitprice','`unitprice` decimal(6,2) NULL DEFAULT NULL COMMENT \'商品单价\' AFTER `monthlysale`');
CALL `p_add_col_if_missing`('t_dish','cost_price','`cost_price` decimal(10,2) NULL DEFAULT NULL COMMENT \'成本价(元)，用于毛利分析\' AFTER `unitprice`');
CALL `p_add_col_if_missing`('t_dish','unit','`unit` varchar(10) NULL DEFAULT NULL COMMENT \'商品单位\' AFTER `cost_price`');
CALL `p_add_col_if_missing`('t_dish','quantity','`quantity` int NULL DEFAULT 0 COMMENT \'商品数量\' AFTER `unit`');
CALL `p_add_col_if_missing`('t_dish','stock','`stock` int NULL DEFAULT NULL COMMENT \'可售库存份数；NULL 表示不限量；与 quantity 解耦，下单扣减仅更新本列\' AFTER `quantity`');
CALL `p_add_col_if_missing`('t_dish','time','`time` datetime NULL DEFAULT NULL COMMENT \'上架时间\' AFTER `stock`');
CALL `p_add_col_if_missing`('t_dish','onsale','`onsale` bit(1) NULL DEFAULT NULL COMMENT \'true：上架 false：下架\' AFTER `time`');
CALL `p_add_col_if_missing`('t_dish','sold_out','`sold_out` tinyint NOT NULL DEFAULT 0 COMMENT \'是否已售罄：0-否 1-是\' AFTER `onsale`');
CALL `p_add_col_if_missing`('t_dish','specification','`specification` varchar(255) NULL DEFAULT NULL COMMENT \'产品规格\' AFTER `sold_out`');
CALL `p_add_col_if_missing`('t_dish','serving_duration_minutes','`serving_duration_minutes` int NOT NULL DEFAULT 10 COMMENT \'出餐时长（分钟），用于 KDS 单品超时判断\' AFTER `specification`');
CALL `p_add_col_if_missing`('t_dish','sorting','`sorting` int NULL DEFAULT NULL COMMENT \'排序\' AFTER `serving_duration_minutes`');
CALL `p_add_col_if_missing`('t_dish_material_bom','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'配比ID\' FIRST');
CALL `p_add_col_if_missing`('t_dish_material_bom','shop_id','`shop_id` int NOT NULL COMMENT \'门店ID(t_shop.id)\' AFTER `id`');
CALL `p_add_col_if_missing`('t_dish_material_bom','dish_id','`dish_id` int NOT NULL COMMENT \'菜品ID(t_dish.id)\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_dish_material_bom','material_id','`material_id` int NOT NULL COMMENT \'原材料ID(t_material.id)\' AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_dish_material_bom','dosage','`dosage` decimal(10,3) NOT NULL DEFAULT 0.000 COMMENT \'单份菜品消耗原材料数量\' AFTER `material_id`');
CALL `p_add_col_if_missing`('t_dish_material_bom','unit','`unit` varchar(16) NOT NULL DEFAULT \'斤\' COMMENT \'单位：斤/克/袋/瓶\' AFTER `dosage`');
CALL `p_add_col_if_missing`('t_dish_material_bom','loss_rate','`loss_rate` decimal(5,2) NOT NULL DEFAULT 0.05 COMMENT \'损耗率小数，如0.05=5%；消耗=销量×用量×(1+loss_rate)\' AFTER `unit`');
CALL `p_add_col_if_missing`('t_dish_material_bom','is_enabled','`is_enabled` tinyint NOT NULL DEFAULT 1 COMMENT \'1启用 0禁用\' AFTER `loss_rate`');
CALL `p_add_col_if_missing`('t_dish_material_bom','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `is_enabled`');
CALL `p_add_col_if_missing`('t_dish_material_bom','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_dish_shop','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_dish_shop','shop_id','`shop_id` int NOT NULL COMMENT \'t_shop.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_dish_shop','dish_id','`dish_id` int NOT NULL COMMENT \'t_dish.id\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_dish_shop','unitprice','`unitprice` decimal(10,2) NULL DEFAULT NULL COMMENT \'门店覆盖价；NULL 则用 t_dish.unitprice\' AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_dish_shop','stock','`stock` int NOT NULL DEFAULT -1 COMMENT \'门店可售库存；-1 不限量；>=0 为有限库存\' AFTER `unitprice`');
CALL `p_add_col_if_missing`('t_dish_shop','stock_enabled','`stock_enabled` tinyint NOT NULL DEFAULT 0 COMMENT \'鏄?惁鍚?敤搴撳瓨璺熻釜锛堟寔涔呮爣蹇楋紝涓嶉殢搴撳瓨鍊煎彉鍖栵級锛? 璺熻釜锛堟墸鍑?鍥為?锛夛紱0 涓嶉檺閲忔垨鏈?惎鐢\' AFTER `stock`');
CALL `p_add_col_if_missing`('t_dish_shop','sold_out','`sold_out` tinyint NOT NULL DEFAULT 0 COMMENT \'shop sold-out flag: 0 available, 1 sold out\' AFTER `stock_enabled`');
CALL `p_add_col_if_missing`('t_dish_shop','onsale_override','`onsale_override` tinyint NULL DEFAULT NULL COMMENT \'NULL 跟随总部；0 强制下架；1 强制上架\' AFTER `sold_out`');
CALL `p_add_col_if_missing`('t_dish_shop','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `onsale_override`');
CALL `p_add_col_if_missing`('t_invite_record','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'主键ID\' FIRST');
CALL `p_add_col_if_missing`('t_invite_record','inviter_openid','`inviter_openid` varchar(100) NOT NULL COMMENT \'邀请者微信openid\' AFTER `id`');
CALL `p_add_col_if_missing`('t_invite_record','invitee_openid','`invitee_openid` varchar(100) NULL DEFAULT NULL COMMENT \'被邀请者微信openid（未注册时为NULL）\' AFTER `inviter_openid`');
CALL `p_add_col_if_missing`('t_invite_record','invite_code','`invite_code` varchar(20) NOT NULL COMMENT \'邀请码（邀请人维度唯一）\' AFTER `invitee_openid`');
CALL `p_add_col_if_missing`('t_invite_record','create_time','`create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'邀请时间\' AFTER `invite_code`');
CALL `p_add_col_if_missing`('t_invite_record','status','`status` tinyint NOT NULL DEFAULT 0 COMMENT \'状态：0-未注册 1-已注册\' AFTER `create_time`');
CALL `p_add_col_if_missing`('t_invite_record','reward_type','`reward_type` varchar(20) NULL DEFAULT \'coupon\' COMMENT \'奖励类型：coupon-优惠券 point-积分\' AFTER `status`');
CALL `p_add_col_if_missing`('t_invite_record','reward_id','`reward_id` bigint NULL DEFAULT NULL COMMENT \'奖励优惠券ID（reward_type=coupon时）/积分值（reward_type=point时）\' AFTER `reward_type`');
CALL `p_add_col_if_missing`('t_invite_record','reward_time','`reward_time` datetime NULL DEFAULT NULL COMMENT \'奖励发放时间\' AFTER `reward_id`');
CALL `p_add_col_if_missing`('t_invite_record','first_order_reward_amount','`first_order_reward_amount` decimal(12,2) NULL DEFAULT NULL COMMENT \'首单余额奖励金额(元)\' AFTER `reward_time`');
CALL `p_add_col_if_missing`('t_invite_record','first_order_reward_time','`first_order_reward_time` datetime NULL DEFAULT NULL COMMENT \'首单余额奖励发放时间\' AFTER `first_order_reward_amount`');
CALL `p_add_col_if_missing`('t_invite_record','first_order_no','`first_order_no` varchar(64) NULL DEFAULT NULL COMMENT \'触发首单奖励的订单号\' AFTER `first_order_reward_time`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','invite_record_id','`invite_record_id` bigint NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','inviter_user_id','`inviter_user_id` int NOT NULL AFTER `invite_record_id`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','order_no','`order_no` varchar(64) NOT NULL AFTER `inviter_user_id`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','outstanding_amount','`outstanding_amount` decimal(12,2) NOT NULL AFTER `order_no`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','status','`status` varchar(16) NOT NULL DEFAULT \'PENDING\' AFTER `outstanding_amount`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','attempts','`attempts` int NOT NULL DEFAULT 0 AFTER `status`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','last_error','`last_error` varchar(255) NULL DEFAULT NULL AFTER `attempts`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `last_error`');
CALL `p_add_col_if_missing`('t_invite_reward_clawback','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_authority_config_version','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_authority_config_version','version','`version` bigint NOT NULL DEFAULT 1 AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_authority_config_version','cashier_device_code','`cashier_device_code` varchar(64) NULL DEFAULT NULL COMMENT \'Cashier authority identity; not a t_kds_device display device\' AFTER `version`');
CALL `p_add_col_if_missing`('t_kds_authority_config_version','snapshot_hash','`snapshot_hash` char(64) NULL DEFAULT NULL AFTER `cashier_device_code`');
CALL `p_add_col_if_missing`('t_kds_authority_config_version','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `snapshot_hash`');
CALL `p_add_col_if_missing`('t_kds_authority_config_version','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','device_code','`device_code` varchar(64) NULL DEFAULT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','authority_epoch','`authority_epoch` bigint NOT NULL DEFAULT 0 AFTER `device_code`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','lease_token_hash','`lease_token_hash` char(64) NULL DEFAULT NULL AFTER `authority_epoch`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','lease_until','`lease_until` datetime NULL DEFAULT NULL AFTER `lease_token_hash`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','ack_cursor','`ack_cursor` bigint NOT NULL DEFAULT 0 AFTER `lease_until`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','last_delivered_cursor','`last_delivered_cursor` bigint NOT NULL DEFAULT 0 AFTER `ack_cursor`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','bootstrap_base_cursor','`bootstrap_base_cursor` bigint NOT NULL DEFAULT 0 AFTER `last_delivered_cursor`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','bootstrap_required','`bootstrap_required` tinyint(1) NOT NULL DEFAULT 1 AFTER `bootstrap_base_cursor`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','client_version','`client_version` varchar(64) NULL DEFAULT NULL AFTER `bootstrap_required`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','last_seen_at','`last_seen_at` datetime NULL DEFAULT NULL AFTER `client_version`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `last_seen_at`');
CALL `p_add_col_if_missing`('t_kds_delivery_consumer','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'全局持久游标；门店内递增但不保证连续\' FIRST');
CALL `p_add_col_if_missing`('t_kds_delivery_event','event_id','`event_id` char(36) NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','shop_id','`shop_id` int NOT NULL AFTER `event_id`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','order_id','`order_id` int NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','projection_version','`projection_version` bigint NOT NULL AFTER `order_id`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','event_type','`event_type` varchar(32) NOT NULL AFTER `projection_version`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','origin_channel','`origin_channel` varchar(24) NOT NULL AFTER `event_type`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','origin_device_code','`origin_device_code` varchar(64) NULL DEFAULT NULL AFTER `origin_channel`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','changed_detail_ids_json','`changed_detail_ids_json` text NULL DEFAULT NULL AFTER `origin_device_code`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','payload_json','`payload_json` longtext NOT NULL COMMENT \'完整订单厨房投影，消费者无需拼 patch\' AFTER `changed_detail_ids_json`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','occurred_at_ms','`occurred_at_ms` bigint NOT NULL AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_delivery_event','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `occurred_at_ms`');
CALL `p_add_col_if_missing`('t_kds_device','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_device','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_device','station_id','`station_id` bigint NULL DEFAULT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_device','screen_tag','`screen_tag` varchar(32) NOT NULL AFTER `station_id`');
CALL `p_add_col_if_missing`('t_kds_device','device_code','`device_code` varchar(64) NOT NULL AFTER `screen_tag`');
CALL `p_add_col_if_missing`('t_kds_device','device_name','`device_name` varchar(64) NULL DEFAULT NULL AFTER `device_code`');
CALL `p_add_col_if_missing`('t_kds_device','device_token','`device_token` varchar(128) NULL DEFAULT NULL AFTER `device_name`');
CALL `p_add_col_if_missing`('t_kds_device','workflows_json','`workflows_json` varchar(64) NULL DEFAULT NULL COMMENT \'prep,cook,serve 逗号分隔\' AFTER `device_token`');
CALL `p_add_col_if_missing`('t_kds_device','last_heartbeat_at','`last_heartbeat_at` datetime NULL DEFAULT NULL AFTER `workflows_json`');
CALL `p_add_col_if_missing`('t_kds_device','enabled','`enabled` tinyint NOT NULL DEFAULT 1 AFTER `last_heartbeat_at`');
CALL `p_add_col_if_missing`('t_kds_device','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `enabled`');
CALL `p_add_col_if_missing`('t_kds_device','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_dish_screen','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_dish_screen','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_dish_screen','dish_id','`dish_id` int NOT NULL COMMENT \'t_dish.id\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_dish_screen','screen_tag','`screen_tag` varchar(32) NOT NULL AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_kds_dish_screen','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `screen_tag`');
CALL `p_add_col_if_missing`('t_kds_dish_screen','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_flow_batch','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','ticket_id','`ticket_id` bigint NOT NULL COMMENT \'t_kds_ticket.id\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','detail_id','`detail_id` int NOT NULL COMMENT \'t_order_detail.id\' AFTER `ticket_id`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','order_id','`order_id` int NOT NULL AFTER `detail_id`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','quantity','`quantity` int NOT NULL DEFAULT 1 COMMENT \'本批次份数\' AFTER `order_id`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','dining_channel','`dining_channel` varchar(16) NULL DEFAULT NULL COMMENT \'dine_in/pack/takeout\' AFTER `quantity`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','queue_status','`queue_status` varchar(24) NOT NULL DEFAULT \'pending_prep\' COMMENT \'pending_prep/pending_cook/ready_serve/done/void\' AFTER `dining_channel`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','order_time','`order_time` datetime NULL DEFAULT NULL COMMENT \'下单时间（FCFS）\' AFTER `queue_status`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','prep_at','`prep_at` datetime NULL DEFAULT NULL COMMENT \'配菜完成时间\' AFTER `order_time`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','cooked_at','`cooked_at` datetime NULL DEFAULT NULL COMMENT \'制作完成时间\' AFTER `prep_at`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','served_at','`served_at` datetime NULL DEFAULT NULL COMMENT \'传菜完成时间\' AFTER `cooked_at`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','void_reason','`void_reason` varchar(32) NULL DEFAULT NULL AFTER `served_at`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `void_reason`');
CALL `p_add_col_if_missing`('t_kds_flow_batch','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_operation_log','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_operation_log','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','device_id','`device_id` bigint NULL DEFAULT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','order_id','`order_id` int NOT NULL AFTER `device_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','detail_id','`detail_id` int NULL DEFAULT NULL AFTER `order_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','ticket_id','`ticket_id` bigint NULL DEFAULT NULL AFTER `detail_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','operation_type','`operation_type` varchar(32) NOT NULL COMMENT \'advance/revoke/rush/refund/lack/hold/release\' AFTER `ticket_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','from_queue','`from_queue` varchar(32) NULL DEFAULT NULL AFTER `operation_type`');
CALL `p_add_col_if_missing`('t_kds_operation_log','to_queue','`to_queue` varchar(32) NULL DEFAULT NULL AFTER `from_queue`');
CALL `p_add_col_if_missing`('t_kds_operation_log','quantity','`quantity` int NOT NULL DEFAULT 0 AFTER `to_queue`');
CALL `p_add_col_if_missing`('t_kds_operation_log','request_id','`request_id` varchar(64) NULL DEFAULT NULL AFTER `quantity`');
CALL `p_add_col_if_missing`('t_kds_operation_log','operator_type','`operator_type` varchar(16) NOT NULL DEFAULT \'device\' COMMENT \'device/admin/pos\' AFTER `request_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','operator_id','`operator_id` bigint NULL DEFAULT NULL AFTER `operator_type`');
CALL `p_add_col_if_missing`('t_kds_operation_log','result_code','`result_code` varchar(32) NOT NULL DEFAULT \'0\' AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_kds_operation_log','result_msg','`result_msg` varchar(255) NULL DEFAULT NULL AFTER `result_code`');
CALL `p_add_col_if_missing`('t_kds_operation_log','payload_json','`payload_json` json NULL DEFAULT NULL AFTER `result_msg`');
CALL `p_add_col_if_missing`('t_kds_operation_log','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_order','order_id','`order_id` int NOT NULL COMMENT \'t_order.id\' FIRST');
CALL `p_add_col_if_missing`('t_kds_order','shop_id','`shop_id` int NOT NULL AFTER `order_id`');
CALL `p_add_col_if_missing`('t_kds_order','order_no','`order_no` varchar(100) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_order','kds_order_status','`kds_order_status` tinyint NOT NULL DEFAULT 10 COMMENT \'10/20/30/40/90\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_kds_order','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `kds_order_status`');
CALL `p_add_col_if_missing`('t_kds_order','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_order_projection','order_id','`order_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_order_projection','shop_id','`shop_id` int NOT NULL AFTER `order_id`');
CALL `p_add_col_if_missing`('t_kds_order_projection','projection_version','`projection_version` bigint NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_order_projection','state','`state` varchar(16) NOT NULL AFTER `projection_version`');
CALL `p_add_col_if_missing`('t_kds_order_projection','source_channel','`source_channel` varchar(24) NOT NULL AFTER `state`');
CALL `p_add_col_if_missing`('t_kds_order_projection','payload_json','`payload_json` longtext NOT NULL AFTER `source_channel`');
CALL `p_add_col_if_missing`('t_kds_order_projection','payload_hash','`payload_hash` char(64) NOT NULL AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_order_projection','last_event_cursor','`last_event_cursor` bigint NULL DEFAULT NULL AFTER `payload_hash`');
CALL `p_add_col_if_missing`('t_kds_order_projection','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `last_event_cursor`');
CALL `p_add_col_if_missing`('t_kds_order_projection','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','aggregate_key','`aggregate_key` varchar(128) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','order_created_applied','`order_created_applied` tinyint NOT NULL DEFAULT 0 AFTER `aggregate_key`');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','last_occurred_at_ms','`last_occurred_at_ms` bigint NULL DEFAULT NULL AFTER `order_created_applied`');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `last_occurred_at_ms`');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_aggregate','last_order_revision','`last_order_revision` bigint NOT NULL DEFAULT 0 AFTER `updated_at`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','event_id','`event_id` varchar(128) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','action','`action` varchar(20) NOT NULL COMMENT \'retry/replace/discard\' AFTER `event_id`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','reason','`reason` varchar(500) NULL DEFAULT NULL AFTER `action`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','replacement_event_id','`replacement_event_id` varchar(128) NULL DEFAULT NULL AFTER `reason`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','operator_admin_id','`operator_admin_id` int NULL DEFAULT NULL AFTER `replacement_event_id`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','operator_subject','`operator_subject` varchar(128) NOT NULL AFTER `operator_admin_id`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','trace_id','`trace_id` varchar(128) NULL DEFAULT NULL AFTER `operator_subject`');
CALL `p_add_col_if_missing`('t_kds_replication_dead_letter_audit','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `trace_id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','local_order_id','`local_order_id` bigint NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','local_detail_id','`local_detail_id` bigint NOT NULL AFTER `local_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','cloud_order_id','`cloud_order_id` int NOT NULL AFTER `local_detail_id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','cloud_detail_id','`cloud_detail_id` int NOT NULL AFTER `cloud_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','last_local_revision','`last_local_revision` bigint NOT NULL DEFAULT 0 AFTER `cloud_detail_id`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `last_local_revision`');
CALL `p_add_col_if_missing`('t_kds_replication_detail_map','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_event','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_event','event_id','`event_id` varchar(128) NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_replication_event','shop_id','`shop_id` int NOT NULL AFTER `event_id`');
CALL `p_add_col_if_missing`('t_kds_replication_event','event_type','`event_type` varchar(40) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_event','aggregate_key','`aggregate_key` varchar(128) NOT NULL AFTER `event_type`');
CALL `p_add_col_if_missing`('t_kds_replication_event','occurred_at_ms','`occurred_at_ms` bigint NOT NULL AFTER `aggregate_key`');
CALL `p_add_col_if_missing`('t_kds_replication_event','operation_id','`operation_id` varchar(128) NULL DEFAULT NULL AFTER `occurred_at_ms`');
CALL `p_add_col_if_missing`('t_kds_replication_event','local_revision','`local_revision` bigint NULL DEFAULT NULL AFTER `operation_id`');
CALL `p_add_col_if_missing`('t_kds_replication_event','payload_json','`payload_json` longtext NOT NULL AFTER `local_revision`');
CALL `p_add_col_if_missing`('t_kds_replication_event','status','`status` varchar(20) NOT NULL DEFAULT \'received\' COMMENT \'received/pending/applied/ignored/failed\' AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_replication_event','result_json','`result_json` longtext NULL DEFAULT NULL AFTER `status`');
CALL `p_add_col_if_missing`('t_kds_replication_event','error_code','`error_code` int NULL DEFAULT NULL AFTER `result_json`');
CALL `p_add_col_if_missing`('t_kds_replication_event','error_message','`error_message` varchar(500) NULL DEFAULT NULL AFTER `error_code`');
CALL `p_add_col_if_missing`('t_kds_replication_event','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `error_message`');
CALL `p_add_col_if_missing`('t_kds_replication_event','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_event','applied_at','`applied_at` datetime NULL DEFAULT NULL AFTER `updated_at`');
CALL `p_add_col_if_missing`('t_kds_replication_event','retry_count','`retry_count` int NOT NULL DEFAULT 0 AFTER `applied_at`');
CALL `p_add_col_if_missing`('t_kds_replication_event','dead_lettered_at','`dead_lettered_at` datetime NULL DEFAULT NULL AFTER `retry_count`');
CALL `p_add_col_if_missing`('t_kds_replication_event','resolution_action','`resolution_action` varchar(20) NULL DEFAULT NULL AFTER `dead_lettered_at`');
CALL `p_add_col_if_missing`('t_kds_replication_event','resolution_reason','`resolution_reason` varchar(500) NULL DEFAULT NULL AFTER `resolution_action`');
CALL `p_add_col_if_missing`('t_kds_replication_event','replacement_event_id','`replacement_event_id` varchar(128) NULL DEFAULT NULL AFTER `resolution_reason`');
CALL `p_add_col_if_missing`('t_kds_replication_event','resolved_at','`resolved_at` datetime NULL DEFAULT NULL AFTER `replacement_event_id`');
CALL `p_add_col_if_missing`('t_kds_replication_event','request_fingerprint','`request_fingerprint` char(64) NULL DEFAULT NULL COMMENT \'SHA-256 canonical semantic request; excludes idempotency IDs\' AFTER `resolved_at`');
CALL `p_add_col_if_missing`('t_kds_replication_event','publisher_device_code','`publisher_device_code` varchar(64) NULL DEFAULT NULL COMMENT \'Authenticated X-Cashier-Device-Code\' AFTER `request_fingerprint`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','dish_id','`dish_id` int NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','availability_revision','`availability_revision` bigint NOT NULL AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','stock','`stock` int NULL DEFAULT NULL AFTER `availability_revision`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','sold_out','`sold_out` tinyint NULL DEFAULT NULL AFTER `stock`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','payload_json','`payload_json` longtext NOT NULL AFTER `sold_out`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_replication_inventory_state','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','local_order_id','`local_order_id` bigint NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','local_detail_id','`local_detail_id` bigint NOT NULL AFTER `local_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','cloud_order_id','`cloud_order_id` int NOT NULL AFTER `local_detail_id`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','cloud_detail_id','`cloud_detail_id` int NOT NULL AFTER `cloud_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','workflow_queue','`workflow_queue` varchar(40) NULL DEFAULT NULL AFTER `cloud_detail_id`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','prep_remaining','`prep_remaining` int NULL DEFAULT NULL AFTER `workflow_queue`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','cook_remaining','`cook_remaining` int NULL DEFAULT NULL AFTER `prep_remaining`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','ready_remaining','`ready_remaining` int NULL DEFAULT NULL AFTER `cook_remaining`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','remaining_quantity','`remaining_quantity` int NULL DEFAULT NULL AFTER `ready_remaining`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','local_revision','`local_revision` bigint NOT NULL AFTER `remaining_quantity`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','payload_json','`payload_json` longtext NOT NULL AFTER `local_revision`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_replication_line_state','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','local_order_id','`local_order_id` bigint NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','aggregate_key','`aggregate_key` varchar(128) NOT NULL AFTER `local_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','local_order_no','`local_order_no` varchar(100) NULL DEFAULT NULL AFTER `aggregate_key`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','cloud_order_id','`cloud_order_id` int NOT NULL AFTER `local_order_no`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','cloud_order_no','`cloud_order_no` varchar(100) NOT NULL AFTER `cloud_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `cloud_order_no`');
CALL `p_add_col_if_missing`('t_kds_replication_order_map','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_replication_order_state','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_replication_order_state','local_order_id','`local_order_id` bigint NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_replication_order_state','order_revision','`order_revision` bigint NOT NULL AFTER `local_order_id`');
CALL `p_add_col_if_missing`('t_kds_replication_order_state','payload_json','`payload_json` longtext NOT NULL AFTER `order_revision`');
CALL `p_add_col_if_missing`('t_kds_replication_order_state','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `payload_json`');
CALL `p_add_col_if_missing`('t_kds_replication_order_state','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_shop_config','shop_id','`shop_id` int NOT NULL COMMENT \'t_shop.id\' FIRST');
CALL `p_add_col_if_missing`('t_kds_shop_config','kds_mode','`kds_mode` varchar(16) NOT NULL DEFAULT \'print_only\' COMMENT \'print_only|kds_only|both\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_shop_config','sync_legacy_rece','`sync_legacy_rece` tinyint NOT NULL DEFAULT 1 COMMENT \'划菜是否回写 order_rece\' AFTER `kds_mode`');
CALL `p_add_col_if_missing`('t_kds_shop_config','auto_off_order_on_kds_done','`auto_off_order_on_kds_done` tinyint NOT NULL DEFAULT 0 COMMENT \'1=厨显整单完成时自动置 order_receiving=off_order（清台） 0=不联动\' AFTER `sync_legacy_rece`');
CALL `p_add_col_if_missing`('t_kds_shop_config','serve_print_enabled','`serve_print_enabled` tinyint NOT NULL DEFAULT 1 COMMENT \'1=待传菜划单后打印传菜单 0=不打印\' AFTER `auto_off_order_on_kds_done`');
CALL `p_add_col_if_missing`('t_kds_shop_config','auto_push_on_create','`auto_push_on_create` tinyint NOT NULL DEFAULT 1 COMMENT \'下单即推厨显\' AFTER `serve_print_enabled`');
CALL `p_add_col_if_missing`('t_kds_shop_config','skewer_gate','`skewer_gate` tinyint NOT NULL DEFAULT 1 COMMENT \'1先抓串再分流烤制屏 0直连烤制屏\' AFTER `auto_push_on_create`');
CALL `p_add_col_if_missing`('t_kds_shop_config','prep_enabled','`prep_enabled` tinyint NULL DEFAULT NULL COMMENT \'1=有待配菜环节 0=跳过待配菜直进待制作 NULL=跟随skewer_gate\' AFTER `skewer_gate`');
CALL `p_add_col_if_missing`('t_kds_shop_config','default_screen_tag','`default_screen_tag` varchar(32) NULL DEFAULT \'meat_grill\' AFTER `prep_enabled`');
CALL `p_add_col_if_missing`('t_kds_shop_config','sla_minutes','`sla_minutes` int NOT NULL DEFAULT 10 AFTER `default_screen_tag`');
CALL `p_add_col_if_missing`('t_kds_shop_config','archive_hours','`archive_hours` int NOT NULL DEFAULT 2 COMMENT \'已完成归档小时数\' AFTER `sla_minutes`');
CALL `p_add_col_if_missing`('t_kds_shop_config','lack_sets_sold_out','`lack_sets_sold_out` tinyint NOT NULL DEFAULT 0 COMMENT \'缺货上报是否置 sold_out\' AFTER `archive_hours`');
CALL `p_add_col_if_missing`('t_kds_shop_config','merge_same_dish','`merge_same_dish` tinyint NOT NULL DEFAULT 1 COMMENT \'1=合并相同菜品（跨订单/跨桌汇总）\' AFTER `lack_sets_sold_out`');
CALL `p_add_col_if_missing`('t_kds_shop_config','pack_inline_merge','`pack_inline_merge` tinyint NOT NULL DEFAULT 1 COMMENT \'1=堂食与打包内嵌同一行；0=按渠道拆行\' AFTER `merge_same_dish`');
CALL `p_add_col_if_missing`('t_kds_shop_config','combo_merge','`combo_merge` tinyint NOT NULL DEFAULT 1 COMMENT \'1=套餐子菜与散点同菜合并；0=套餐独立成行\' AFTER `pack_inline_merge`');
CALL `p_add_col_if_missing`('t_kds_shop_config','enable_prep_workflow','`enable_prep_workflow` tinyint NOT NULL DEFAULT 1 COMMENT \'1=启用待配菜环节 0=跳过待配菜直接进入待制作\' AFTER `combo_merge`');
CALL `p_add_col_if_missing`('t_kds_shop_config','add_dish_timeout_independent','`add_dish_timeout_independent` tinyint NOT NULL DEFAULT 1 COMMENT \'1=加菜超时按加菜明细自身时间计算；0=跟随订单首单时间\' AFTER `enable_prep_workflow`');
CALL `p_add_col_if_missing`('t_kds_shop_config','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `add_dish_timeout_independent`');
CALL `p_add_col_if_missing`('t_kds_skewer_pick','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_skewer_pick','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_skewer_pick','dish_name','`dish_name` varchar(100) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_skewer_pick','quantity_picked','`quantity_picked` int NOT NULL DEFAULT 0 AFTER `dish_name`');
CALL `p_add_col_if_missing`('t_kds_skewer_pick','unit','`unit` varchar(11) NULL DEFAULT NULL AFTER `quantity_picked`');
CALL `p_add_col_if_missing`('t_kds_skewer_pick','picked_at','`picked_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `unit`');
CALL `p_add_col_if_missing`('t_kds_station','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_station','shop_id','`shop_id` int NOT NULL COMMENT \'t_shop.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_station','name','`name` varchar(64) NOT NULL COMMENT \'显示名\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_station','code','`code` varchar(32) NOT NULL COMMENT \'同店唯一编码，如 MEAT\' AFTER `name`');
CALL `p_add_col_if_missing`('t_kds_station','screen_tag','`screen_tag` varchar(32) NOT NULL COMMENT \'skewer_aggregate|meat_grill|veg_grill|seafood_special|expedition\' AFTER `code`');
CALL `p_add_col_if_missing`('t_kds_station','sort','`sort` int NOT NULL DEFAULT 0 AFTER `screen_tag`');
CALL `p_add_col_if_missing`('t_kds_station','enabled','`enabled` tinyint NOT NULL DEFAULT 1 AFTER `sort`');
CALL `p_add_col_if_missing`('t_kds_station','enable_prep_workflow','`enable_prep_workflow` tinyint NULL DEFAULT NULL COMMENT \'1=启用待配菜环节 0=跳过待配菜 NULL=继承门店配置\' AFTER `enabled`');
CALL `p_add_col_if_missing`('t_kds_station','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `enable_prep_workflow`');
CALL `p_add_col_if_missing`('t_kds_station','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_station_category','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_station_category','station_id','`station_id` bigint NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_station_category','cid','`cid` varchar(64) NOT NULL COMMENT \'t_category 主键字符串\' AFTER `station_id`');
CALL `p_add_col_if_missing`('t_kds_station_category','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `cid`');
CALL `p_add_col_if_missing`('t_kds_sync_dedup','client_id','`client_id` varchar(64) NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_kds_sync_dedup','shop_id','`shop_id` int NOT NULL AFTER `client_id`');
CALL `p_add_col_if_missing`('t_kds_sync_dedup','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_ticket','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_kds_ticket','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_kds_ticket','station_id','`station_id` bigint NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_kds_ticket','screen_tag','`screen_tag` varchar(32) NOT NULL AFTER `station_id`');
CALL `p_add_col_if_missing`('t_kds_ticket','order_id','`order_id` int NOT NULL AFTER `screen_tag`');
CALL `p_add_col_if_missing`('t_kds_ticket','order_no','`order_no` varchar(100) NOT NULL AFTER `order_id`');
CALL `p_add_col_if_missing`('t_kds_ticket','detail_id','`detail_id` int NOT NULL COMMENT \'t_order_detail.id\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_kds_ticket','item_status','`item_status` tinyint NOT NULL DEFAULT 0 COMMENT \'0待制作 1制作中 2已完成 3已退菜\' AFTER `detail_id`');
CALL `p_add_col_if_missing`('t_kds_ticket','skewer_picked','`skewer_picked` tinyint NOT NULL DEFAULT 0 COMMENT \'0待抓串 1已抓串可上烤制屏\' AFTER `item_status`');
CALL `p_add_col_if_missing`('t_kds_ticket','skewer_picked_at','`skewer_picked_at` datetime NULL DEFAULT NULL COMMENT \'抓串完成时间\' AFTER `skewer_picked`');
CALL `p_add_col_if_missing`('t_kds_ticket','rush_flag','`rush_flag` tinyint NOT NULL DEFAULT 0 AFTER `skewer_picked_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','add_dish_flag','`add_dish_flag` tinyint NOT NULL DEFAULT 0 COMMENT \'加菜标记 0/1\' AFTER `rush_flag`');
CALL `p_add_col_if_missing`('t_kds_ticket','overdue_flag','`overdue_flag` tinyint NOT NULL DEFAULT 0 COMMENT \'超时标记 0/1（待做且超 SLA）\' AFTER `add_dish_flag`');
CALL `p_add_col_if_missing`('t_kds_ticket','overdue_at','`overdue_at` datetime NULL DEFAULT NULL COMMENT \'首次标记超时时间\' AFTER `overdue_flag`');
CALL `p_add_col_if_missing`('t_kds_ticket','rush_at','`rush_at` datetime NULL DEFAULT NULL COMMENT \'催菜时间\' AFTER `overdue_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','order_number_snapshot','`order_number_snapshot` int NULL DEFAULT NULL AFTER `rush_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','archived','`archived` tinyint NOT NULL DEFAULT 0 AFTER `order_number_snapshot`');
CALL `p_add_col_if_missing`('t_kds_ticket','served_quantity','`served_quantity` int NOT NULL DEFAULT 0 COMMENT \'已传菜确认数量（分批出餐）\' AFTER `archived`');
CALL `p_add_col_if_missing`('t_kds_ticket','prep_quantity','`prep_quantity` int NOT NULL DEFAULT 0 COMMENT \'已配菜数量（进入待制作池）\' AFTER `served_quantity`');
CALL `p_add_col_if_missing`('t_kds_ticket','cooked_quantity','`cooked_quantity` int NOT NULL DEFAULT 0 COMMENT \'已制作完成数量（进入待传菜池）\' AFTER `prep_quantity`');
CALL `p_add_col_if_missing`('t_kds_ticket','prep_completed_at','`prep_completed_at` datetime NULL DEFAULT NULL COMMENT \'配菜完成时刻\' AFTER `cooked_quantity`');
CALL `p_add_col_if_missing`('t_kds_ticket','void_reason','`void_reason` varchar(128) NULL DEFAULT NULL AFTER `prep_completed_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `void_reason`');
CALL `p_add_col_if_missing`('t_kds_ticket','accepted_at','`accepted_at` datetime NULL DEFAULT NULL AFTER `created_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','done_at','`done_at` datetime NULL DEFAULT NULL AFTER `accepted_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','served_at','`served_at` datetime NULL DEFAULT NULL COMMENT \'传菜完成时刻\' AFTER `done_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','archived_at','`archived_at` datetime NULL DEFAULT NULL COMMENT \'归档进入已完成 Tab 时刻\' AFTER `served_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','completed_wait_seconds','`completed_wait_seconds` int NULL DEFAULT NULL COMMENT \'最近一次队列完成时的冻结等待秒数\' AFTER `archived_at`');
CALL `p_add_col_if_missing`('t_kds_ticket','row_version','`row_version` int NOT NULL DEFAULT 0 COMMENT \'乐观锁版本\' AFTER `completed_wait_seconds`');
CALL `p_add_col_if_missing`('t_kds_ticket','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `row_version`');
CALL `p_add_col_if_missing`('t_material','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_material','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID，关联 t_shop.id；NULL=未分门店的旧数据\' AFTER `id`');
CALL `p_add_col_if_missing`('t_material','name','`name` varchar(64) NOT NULL COMMENT \'原材料名称\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_material','unit','`unit` varchar(16) NOT NULL DEFAULT \'斤\' COMMENT \'单位\' AFTER `name`');
CALL `p_add_col_if_missing`('t_material','stock','`stock` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'当前库存\' AFTER `unit`');
CALL `p_add_col_if_missing`('t_material','alert_threshold','`alert_threshold` decimal(12,3) NULL DEFAULT NULL COMMENT \'库存预警阈值\' AFTER `stock`');
CALL `p_add_col_if_missing`('t_material','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `alert_threshold`');
CALL `p_add_col_if_missing`('t_material','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_member_recharge','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_member_recharge','user_id','`user_id` int NOT NULL COMMENT \'t_user.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_member_recharge','openid','`openid` varchar(64) NOT NULL AFTER `user_id`');
CALL `p_add_col_if_missing`('t_member_recharge','order_no','`order_no` varchar(64) NULL DEFAULT NULL COMMENT \'微信充值商户单号（与 t_order 无关）；后台渠道可为空\' AFTER `openid`');
CALL `p_add_col_if_missing`('t_member_recharge','shop_id','`shop_id` int NULL DEFAULT NULL AFTER `order_no`');
CALL `p_add_col_if_missing`('t_member_recharge','operator_id','`operator_id` int NULL DEFAULT NULL COMMENT \'后台人工充值操作员ID\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_member_recharge','drawer_session_id','`drawer_session_id` bigint NULL DEFAULT NULL COMMENT \'后台人工充值归属钱箱会话ID\' AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_member_recharge','channel','`channel` varchar(20) NOT NULL COMMENT \'wechat | admin\' AFTER `drawer_session_id`');
CALL `p_add_col_if_missing`('t_member_recharge','status','`status` varchar(20) NOT NULL DEFAULT \'pending\' COMMENT \'pending|success|cancelled\' AFTER `channel`');
CALL `p_add_col_if_missing`('t_member_recharge','recharge_amount','`recharge_amount` decimal(12,2) NOT NULL COMMENT \'充值本金（元）\' AFTER `status`');
CALL `p_add_col_if_missing`('t_member_recharge','gift_amount','`gift_amount` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'赠送（元）\' AFTER `recharge_amount`');
CALL `p_add_col_if_missing`('t_member_recharge','total_amount','`total_amount` decimal(12,2) NOT NULL COMMENT \'入账合计（元）=本金+赠送\' AFTER `gift_amount`');
CALL `p_add_col_if_missing`('t_member_recharge','transaction_id','`transaction_id` varchar(128) NULL DEFAULT NULL AFTER `total_amount`');
CALL `p_add_col_if_missing`('t_member_recharge','pay_time','`pay_time` datetime NULL DEFAULT NULL AFTER `transaction_id`');
CALL `p_add_col_if_missing`('t_member_recharge','remark','`remark` varchar(500) NULL DEFAULT NULL AFTER `pay_time`');
CALL `p_add_col_if_missing`('t_member_recharge','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `remark`');
CALL `p_add_col_if_missing`('t_member_recharge','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_operation_log','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_operation_log','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID，审计隔离\' AFTER `id`');
CALL `p_add_col_if_missing`('t_operation_log','module','`module` varchar(32) NOT NULL COMMENT \'order/dish/price/daily等\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_operation_log','action','`action` varchar(64) NOT NULL COMMENT \'delete_order/change_price/un_checkout等\' AFTER `module`');
CALL `p_add_col_if_missing`('t_operation_log','target_id','`target_id` varchar(64) NULL DEFAULT NULL COMMENT \'订单号或ID\' AFTER `action`');
CALL `p_add_col_if_missing`('t_operation_log','admin_id','`admin_id` int NULL DEFAULT NULL AFTER `target_id`');
CALL `p_add_col_if_missing`('t_operation_log','ip','`ip` varchar(64) NULL DEFAULT NULL AFTER `admin_id`');
CALL `p_add_col_if_missing`('t_operation_log','request_snapshot','`request_snapshot` text NULL DEFAULT NULL COMMENT \'请求关键参数\' AFTER `ip`');
CALL `p_add_col_if_missing`('t_operation_log','source_table','`source_table` varchar(50) NULL DEFAULT NULL COMMENT \'源桌号\' AFTER `request_snapshot`');
CALL `p_add_col_if_missing`('t_operation_log','target_table','`target_table` varchar(50) NULL DEFAULT NULL COMMENT \'目标桌号；非并台为空\' AFTER `source_table`');
CALL `p_add_col_if_missing`('t_operation_log','order_nos','`order_nos` text NULL DEFAULT NULL COMMENT \'涉及订单号 JSON 数组\' AFTER `target_table`');
CALL `p_add_col_if_missing`('t_operation_log','before_state','`before_state` text NULL DEFAULT NULL COMMENT \'操作前桌台/订单状态 JSON\' AFTER `order_nos`');
CALL `p_add_col_if_missing`('t_operation_log','after_state','`after_state` text NULL DEFAULT NULL COMMENT \'操作后桌台/订单状态 JSON\' AFTER `before_state`');
CALL `p_add_col_if_missing`('t_operation_log','result_status','`result_status` varchar(16) NULL DEFAULT NULL COMMENT \'SUCCESS/REJECTED/ROLLED_BACK\' AFTER `after_state`');
CALL `p_add_col_if_missing`('t_operation_log','result_code','`result_code` int NULL DEFAULT NULL COMMENT \'接口业务码\' AFTER `result_status`');
CALL `p_add_col_if_missing`('t_operation_log','reason','`reason` varchar(255) NULL DEFAULT NULL COMMENT \'成功说明或拒绝/回滚原因（不含敏感信息）\' AFTER `result_code`');
CALL `p_add_col_if_missing`('t_operation_log','request_key','`request_key` varchar(128) NULL DEFAULT NULL COMMENT \'Idempotency-Key/X-Request-ID/trace 标识\' AFTER `reason`');
CALL `p_add_col_if_missing`('t_operation_log','request_fingerprint','`request_fingerprint` char(64) NULL DEFAULT NULL COMMENT \'动作和桌号参数 SHA-256，用于防止幂等键误复用\' AFTER `request_key`');
CALL `p_add_col_if_missing`('t_operation_log','trace_id','`trace_id` varchar(128) NULL DEFAULT NULL COMMENT \'链路追踪标识\' AFTER `request_fingerprint`');
CALL `p_add_col_if_missing`('t_operation_log','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `trace_id`');
CALL `p_add_col_if_missing`('t_order','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_order','order_no','`order_no` varchar(100) NOT NULL COMMENT \'订单号\' AFTER `id`');
CALL `p_add_col_if_missing`('t_order','master_order_no','`master_order_no` varchar(100) NULL DEFAULT NULL COMMENT \'并台主单号：若该单作为从单被并入主单所属桌台，则记录主单号；非从单为NULL\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_order','table_number','`table_number` varchar(50) NULL DEFAULT NULL COMMENT \'桌号\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_order','number_of_diners','`number_of_diners` int NULL DEFAULT NULL COMMENT \'用餐人数\' AFTER `table_number`');
CALL `p_add_col_if_missing`('t_order','sett_amount','`sett_amount` decimal(6,2) NOT NULL COMMENT \'计算总价\' AFTER `number_of_diners`');
CALL `p_add_col_if_missing`('t_order','transac_status','`transac_status` enum(\'success\',\'unsettled\',\'cancelled\') NOT NULL COMMENT \'结账状态：success/unsettled/cancelled\' AFTER `sett_amount`');
CALL `p_add_col_if_missing`('t_order','order_receiving','`order_receiving` enum(\'mis_order\',\'rec_order\',\'off_order\',\'cancelled\') NOT NULL COMMENT \'接单状态：mis_order/rec_order/off_order/cancelled\' AFTER `transac_status`');
CALL `p_add_col_if_missing`('t_order','order_time','`order_time` datetime NOT NULL COMMENT \'下单时间\' AFTER `order_receiving`');
CALL `p_add_col_if_missing`('t_order','dineInOrTakeOut','`dineInOrTakeOut` varchar(255) NOT NULL COMMENT \'订单类型\' AFTER `order_time`');
CALL `p_add_col_if_missing`('t_order','orderNumber','`orderNumber` int NOT NULL COMMENT \'下单次数

\' AFTER `dineInOrTakeOut`');
CALL `p_add_col_if_missing`('t_order','remark','`remark` varchar(255) NULL DEFAULT NULL COMMENT \'备注\' AFTER `orderNumber`');
CALL `p_add_col_if_missing`('t_order','openid','`openid` varchar(255) NOT NULL COMMENT \'创建者\' AFTER `remark`');
CALL `p_add_col_if_missing`('t_order','prepay_id','`prepay_id` varchar(255) NULL DEFAULT NULL COMMENT \'prepay_id\' AFTER `openid`');
CALL `p_add_col_if_missing`('t_order','transaction_id','`transaction_id` varchar(255) NULL DEFAULT NULL AFTER `prepay_id`');
CALL `p_add_col_if_missing`('t_order','pay_time','`pay_time` datetime NULL DEFAULT NULL COMMENT \'支付时间\' AFTER `transaction_id`');
CALL `p_add_col_if_missing`('t_order','payment_method','`payment_method` varchar(255) NULL DEFAULT NULL COMMENT \'支付方式\' AFTER `pay_time`');
CALL `p_add_col_if_missing`('t_order','pay_amount_wechat','`pay_amount_wechat` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'微信支付金额(元)\' AFTER `payment_method`');
CALL `p_add_col_if_missing`('t_order','pay_amount_alipay','`pay_amount_alipay` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'支付宝支付金额(元)\' AFTER `pay_amount_wechat`');
CALL `p_add_col_if_missing`('t_order','pay_amount_balance','`pay_amount_balance` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'余额支付金额(元)\' AFTER `pay_amount_alipay`');
CALL `p_add_col_if_missing`('t_order','balance_pay_principal','`balance_pay_principal` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'余额支付从本金扣(元)\' AFTER `pay_amount_balance`');
CALL `p_add_col_if_missing`('t_order','balance_pay_gift_wallet','`balance_pay_gift_wallet` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'余额支付从赠送金账户扣(元)\' AFTER `balance_pay_principal`');
CALL `p_add_col_if_missing`('t_order','pay_amount_gift','`pay_amount_gift` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'赠送金支付金额(元)\' AFTER `balance_pay_gift_wallet`');
CALL `p_add_col_if_missing`('t_order','pay_amount_cash','`pay_amount_cash` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'现金支付金额(元)\' AFTER `pay_amount_gift`');
CALL `p_add_col_if_missing`('t_order','checkout_cash_tender','`checkout_cash_tender` decimal(12,2) NULL DEFAULT NULL COMMENT \'结账客人付现金额(元)，可大于 pay_amount_cash\' AFTER `pay_amount_cash`');
CALL `p_add_col_if_missing`('t_order','checkout_change_amount','`checkout_change_amount` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'找零金额(元)\' AFTER `checkout_cash_tender`');
CALL `p_add_col_if_missing`('t_order','checkout_change_channel','`checkout_change_channel` varchar(16) NULL DEFAULT NULL COMMENT \'找零渠道: wechat/cash/alipay\' AFTER `checkout_change_amount`');
CALL `p_add_col_if_missing`('t_order','merchantId','`merchantId` varchar(255) NULL DEFAULT \'1\' AFTER `checkout_change_channel`');
CALL `p_add_col_if_missing`('t_order','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID，关联 t_shop.id\' AFTER `merchantId`');
CALL `p_add_col_if_missing`('t_order','notice','`notice` int NULL DEFAULT NULL COMMENT \'通知取餐\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_order','pay_openid','`pay_openid` varbinary(255) NULL DEFAULT NULL COMMENT \'支付者\' AFTER `notice`');
CALL `p_add_col_if_missing`('t_order','discount_amount','`discount_amount` decimal(8,2) NULL DEFAULT NULL COMMENT \'优惠金额\' AFTER `pay_openid`');
CALL `p_add_col_if_missing`('t_order','off_time','`off_time` datetime NULL DEFAULT NULL COMMENT \'订单完成时间\' AFTER `discount_amount`');
CALL `p_add_col_if_missing`('t_order','service_fee','`service_fee` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT \'新年服务费/额外服务费\' AFTER `off_time`');
CALL `p_add_col_if_missing`('t_order','refund_amount','`refund_amount` decimal(10,2) NULL DEFAULT NULL COMMENT \'累计成功退款金额（元），由微信 /order/refund/notify 退款成功(SUCCESS)回调累加\' AFTER `service_fee`');
CALL `p_add_col_if_missing`('t_order_client_request','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_order_client_request','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_order_client_request','admin_id','`admin_id` int NULL DEFAULT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_order_client_request','client_request_id','`client_request_id` varchar(128) NOT NULL AFTER `admin_id`');
CALL `p_add_col_if_missing`('t_order_client_request','request_path','`request_path` varchar(128) NOT NULL AFTER `client_request_id`');
CALL `p_add_col_if_missing`('t_order_client_request','request_fingerprint','`request_fingerprint` char(64) NULL DEFAULT NULL COMMENT \'SHA-256 of the canonical request body\' AFTER `request_path`');
CALL `p_add_col_if_missing`('t_order_client_request','status','`status` varchar(16) NOT NULL DEFAULT \'PROCESSING\' AFTER `request_fingerprint`');
CALL `p_add_col_if_missing`('t_order_client_request','response_snapshot','`response_snapshot` longtext NULL DEFAULT NULL AFTER `status`');
CALL `p_add_col_if_missing`('t_order_client_request','expires_at','`expires_at` datetime NOT NULL AFTER `response_snapshot`');
CALL `p_add_col_if_missing`('t_order_client_request','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `expires_at`');
CALL `p_add_col_if_missing`('t_order_client_request','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_order_detail','id','`id` int NOT NULL AUTO_INCREMENT COMMENT \'编号\' FIRST');
CALL `p_add_col_if_missing`('t_order_detail','mId','`mId` int NULL DEFAULT NULL COMMENT \'订单主表ID\' AFTER `id`');
CALL `p_add_col_if_missing`('t_order_detail','name','`name` varchar(100) NULL DEFAULT NULL COMMENT \'菜品名称\' AFTER `mId`');
CALL `p_add_col_if_missing`('t_order_detail','quantity','`quantity` int NULL DEFAULT NULL COMMENT \'数量\' AFTER `name`');
CALL `p_add_col_if_missing`('t_order_detail','refunded_quantity','`refunded_quantity` int NOT NULL DEFAULT 0 COMMENT \'Cumulative refunded quantity\' AFTER `quantity`');
CALL `p_add_col_if_missing`('t_order_detail','unit','`unit` varchar(11) NULL DEFAULT NULL COMMENT \'单位\' AFTER `refunded_quantity`');
CALL `p_add_col_if_missing`('t_order_detail','image','`image` varchar(100) NULL DEFAULT NULL COMMENT \'菜品图片\' AFTER `unit`');
CALL `p_add_col_if_missing`('t_order_detail','total_price','`total_price` decimal(6,2) NULL DEFAULT NULL COMMENT \'总价\' AFTER `image`');
CALL `p_add_col_if_missing`('t_order_detail','Morder_no','`Morder_no` varchar(100) NULL DEFAULT NULL AFTER `total_price`');
CALL `p_add_col_if_missing`('t_order_detail','Morder_num','`Morder_num` int NULL DEFAULT NULL AFTER `Morder_no`');
CALL `p_add_col_if_missing`('t_order_detail','order_rece','`order_rece` varchar(255) NULL DEFAULT NULL AFTER `Morder_num`');
CALL `p_add_col_if_missing`('t_order_detail','line_status','`line_status` varchar(16) NOT NULL DEFAULT \'normal\' COMMENT \'normal|refunded\' AFTER `order_rece`');
CALL `p_add_col_if_missing`('t_order_detail','remark','`remark` varchar(255) NULL DEFAULT NULL AFTER `line_status`');
CALL `p_add_col_if_missing`('t_order_detail','selectedSpicy','`selectedSpicy` varchar(255) NULL DEFAULT NULL AFTER `remark`');
CALL `p_add_col_if_missing`('t_order_detail','cid','`cid` varchar(255) NULL DEFAULT NULL AFTER `selectedSpicy`');
CALL `p_add_col_if_missing`('t_order_detail','client_line_id','`client_line_id` varchar(64) NULL DEFAULT NULL COMMENT \'Cashier client line correlation ID\' AFTER `cid`');
CALL `p_add_col_if_missing`('t_order_detail','dish_id','`dish_id` int NULL DEFAULT NULL COMMENT \'t_dish.id，下单时写入；历史数据按 name 回填\' AFTER `client_line_id`');
CALL `p_add_col_if_missing`('t_order_detail','line_type','`line_type` varchar(20) NULL DEFAULT NULL COMMENT \'normal/combo_header/combo_component\' AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_order_detail','combo_id','`combo_id` bigint NULL DEFAULT NULL COMMENT \'t_combo.id\' AFTER `line_type`');
CALL `p_add_col_if_missing`('t_order_detail','combo_instance_id','`combo_instance_id` varchar(40) NULL DEFAULT NULL COMMENT \'同一单同一套餐实例 UUID\' AFTER `combo_id`');
CALL `p_add_col_if_missing`('t_order_detail','parent_detail_id','`parent_detail_id` int NULL DEFAULT NULL COMMENT \'combo 子行指向头行 t_order_detail.id\' AFTER `combo_instance_id`');
CALL `p_add_col_if_missing`('t_order_detail','combo_selection_json','`combo_selection_json` varchar(2000) NULL DEFAULT NULL COMMENT \'套餐头行：用户选择(JSON)，便于复算与客服\' AFTER `parent_detail_id`');
CALL `p_add_col_if_missing`('t_order_log','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_order_log','order_no','`order_no` varchar(100) NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_order_log','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'冗余门店，便于按店筛选\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_order_log','action','`action` varchar(32) NOT NULL COMMENT \'create/add_dish/refund/change_price/checkout/cancel等\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_order_log','operator_type','`operator_type` varchar(16) NULL DEFAULT NULL COMMENT \'openid/admin_id\' AFTER `action`');
CALL `p_add_col_if_missing`('t_order_log','operator_id','`operator_id` varchar(64) NULL DEFAULT NULL COMMENT \'openid 或 admin_id\' AFTER `operator_type`');
CALL `p_add_col_if_missing`('t_order_log','remark','`remark` varchar(255) NULL DEFAULT NULL AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_order_log','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `remark`');
CALL `p_add_col_if_missing`('t_parking_plate','id','`id` bigint unsigned NOT NULL AUTO_INCREMENT COMMENT \'记录唯一ID（主键）\' FIRST');
CALL `p_add_col_if_missing`('t_parking_plate','plate_number','`plate_number` varchar(20) NOT NULL COMMENT \'完整车牌号（如：粤A12345）\' AFTER `id`');
CALL `p_add_col_if_missing`('t_parking_plate','plate_type','`plate_type` tinyint NOT NULL COMMENT \'车牌类型 1-燃油车 2-新能源车\' AFTER `plate_number`');
CALL `p_add_col_if_missing`('t_parking_plate','user_id','`user_id` int NOT NULL COMMENT \'关联用户ID（外键，用户删除时同步删除车牌）\' AFTER `plate_type`');
CALL `p_add_col_if_missing`('t_parking_plate','province','`province` varchar(10) NOT NULL COMMENT \'车牌省份（如：粤）\' AFTER `user_id`');
CALL `p_add_col_if_missing`('t_parking_plate','is_default','`is_default` tinyint NOT NULL DEFAULT 0 COMMENT \'是否默认车牌 0-否 1-是\' AFTER `province`');
CALL `p_add_col_if_missing`('t_parking_plate','create_time','`create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'创建时间\' AFTER `is_default`');
CALL `p_add_col_if_missing`('t_parking_plate','update_time','`update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT \'更新时间\' AFTER `create_time`');
CALL `p_add_col_if_missing`('t_parking_plate','is_delete','`is_delete` tinyint NOT NULL DEFAULT 0 COMMENT \'是否删除 0-未删 1-已删\' AFTER `update_time`');
CALL `p_add_col_if_missing`('t_payment','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_payment','order_no','`order_no` varchar(100) NOT NULL COMMENT \'订单号\' AFTER `id`');
CALL `p_add_col_if_missing`('t_payment','payment_method','`payment_method` varchar(32) NOT NULL COMMENT \'支付方式\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_payment','amount','`amount` decimal(10,2) NOT NULL COMMENT \'支付金额\' AFTER `payment_method`');
CALL `p_add_col_if_missing`('t_payment','transaction_id','`transaction_id` varchar(64) NULL DEFAULT NULL COMMENT \'第三方交易号\' AFTER `amount`');
CALL `p_add_col_if_missing`('t_payment','pay_time','`pay_time` datetime NULL DEFAULT NULL COMMENT \'支付时间\' AFTER `transaction_id`');
CALL `p_add_col_if_missing`('t_payment','operator_id','`operator_id` int NULL DEFAULT NULL COMMENT \'收银员/操作员 admin_id\' AFTER `pay_time`');
CALL `p_add_col_if_missing`('t_payment','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID，可选\' AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_payment','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_capability','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_payment_capability','shop_id','`shop_id` int NOT NULL DEFAULT 0 COMMENT \'0=全门店默认\' AFTER `id`');
CALL `p_add_col_if_missing`('t_payment_capability','online_pay_enabled','`online_pay_enabled` tinyint NOT NULL DEFAULT 1 COMMENT \'线上支付总开关（微信/支付宝/余额）\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_capability','wechat_enabled','`wechat_enabled` tinyint NOT NULL DEFAULT 1 AFTER `online_pay_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','alipay_enabled','`alipay_enabled` tinyint NOT NULL DEFAULT 0 COMMENT \'支付宝官方支付，P3 启用\' AFTER `wechat_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','balance_enabled','`balance_enabled` tinyint NOT NULL DEFAULT 1 AFTER `alipay_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','combined_enabled','`combined_enabled` tinyint NOT NULL DEFAULT 1 COMMENT \'线上组合支付开关\' AFTER `balance_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','cashier_pay_enabled','`cashier_pay_enabled` tinyint NULL DEFAULT NULL COMMENT \'收银端支付总开关\' AFTER `combined_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','cashier_wechat_enabled','`cashier_wechat_enabled` tinyint NULL DEFAULT NULL COMMENT \'收银端微信支付\' AFTER `cashier_pay_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','cashier_alipay_enabled','`cashier_alipay_enabled` tinyint NULL DEFAULT NULL COMMENT \'收银端支付宝支付\' AFTER `cashier_wechat_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','cashier_balance_enabled','`cashier_balance_enabled` tinyint NULL DEFAULT NULL COMMENT \'收银端余额支付\' AFTER `cashier_alipay_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','cashier_combined_enabled','`cashier_combined_enabled` tinyint NULL DEFAULT NULL COMMENT \'收银端组合支付\' AFTER `cashier_balance_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','mini_program_pay_enabled','`mini_program_pay_enabled` tinyint NULL DEFAULT NULL COMMENT \'微信小程序端支付总开关\' AFTER `cashier_combined_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','mini_program_wechat_enabled','`mini_program_wechat_enabled` tinyint NULL DEFAULT NULL COMMENT \'微信小程序端微信支付\' AFTER `mini_program_pay_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','mini_program_balance_enabled','`mini_program_balance_enabled` tinyint NULL DEFAULT NULL COMMENT \'微信小程序端余额支付\' AFTER `mini_program_wechat_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','offline_collect_enabled','`offline_collect_enabled` tinyint NOT NULL DEFAULT 1 AFTER `mini_program_balance_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','offline_collect_channels','`offline_collect_channels` varchar(32) NOT NULL DEFAULT \'wechat,alipay\' AFTER `offline_collect_enabled`');
CALL `p_add_col_if_missing`('t_payment_capability','disabled_message','`disabled_message` varchar(255) NOT NULL DEFAULT \'请联系服务员结账\' AFTER `offline_collect_channels`');
CALL `p_add_col_if_missing`('t_payment_capability','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `disabled_message`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_payment_merchant_config','shop_id','`shop_id` int NOT NULL DEFAULT 0 COMMENT \'0=全门店默认，>0=t_shop.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','channel','`channel` varchar(16) NOT NULL COMMENT \'wechat|alipay\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','merchant_key','`merchant_key` varchar(32) NOT NULL COMMENT \'实例键，如 default、small_amount\' AFTER `channel`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','enabled','`enabled` tinyint NOT NULL DEFAULT 1 AFTER `merchant_key`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','app_id','`app_id` varchar(64) NULL DEFAULT NULL AFTER `enabled`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','mch_id','`mch_id` varchar(32) NULL DEFAULT NULL COMMENT \'微信商户号或支付宝 PID\' AFTER `app_id`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','notify_url','`notify_url` varchar(512) NULL DEFAULT NULL AFTER `mch_id`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','refund_notify_url','`refund_notify_url` varchar(512) NULL DEFAULT NULL AFTER `notify_url`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','api_v3_key_enc','`api_v3_key_enc` varchar(512) NULL DEFAULT NULL COMMENT \'微信 APIv3 密钥（加密或 plain: 前缀）\' AFTER `refund_notify_url`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','serial_no','`serial_no` varchar(64) NULL DEFAULT NULL AFTER `api_v3_key_enc`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','platform_pub_key_id','`platform_pub_key_id` varchar(128) NULL DEFAULT NULL COMMENT \'微信 Wechatpay-Serial 公钥 ID\' AFTER `serial_no`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','platform_pub_key_ref','`platform_pub_key_ref` varchar(512) NULL DEFAULT NULL COMMENT \'微信官方平台公钥 PEM 或 classpath:/pub_key.pem\' AFTER `platform_pub_key_id`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','private_key_ref','`private_key_ref` varchar(512) NULL DEFAULT NULL COMMENT \'商户私钥 PEM 密文或 classpath:/path\' AFTER `platform_pub_key_ref`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','alipay_app_cert_ref','`alipay_app_cert_ref` varchar(512) NULL DEFAULT NULL AFTER `private_key_ref`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','alipay_public_cert_ref','`alipay_public_cert_ref` varchar(512) NULL DEFAULT NULL AFTER `alipay_app_cert_ref`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','alipay_root_cert_ref','`alipay_root_cert_ref` varchar(512) NULL DEFAULT NULL AFTER `alipay_public_cert_ref`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','routing_rule_json','`routing_rule_json` json NULL DEFAULT NULL COMMENT \'商户路由规则\' AFTER `alipay_root_cert_ref`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','sort_order','`sort_order` int NOT NULL DEFAULT 0 AFTER `routing_rule_json`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','remark','`remark` varchar(255) NULL DEFAULT NULL AFTER `sort_order`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `remark`');
CALL `p_add_col_if_missing`('t_payment_merchant_config','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_payment_method','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_payment_method','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'NULL=全局；非空=仅该门店\' AFTER `id`');
CALL `p_add_col_if_missing`('t_payment_method','code','`code` varchar(32) NOT NULL COMMENT \'编码：wechat/alipay/cash/member_card/charge_account\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_method','name','`name` varchar(32) NOT NULL COMMENT \'显示名称\' AFTER `code`');
CALL `p_add_col_if_missing`('t_payment_method','sort_order','`sort_order` int NULL DEFAULT 0 AFTER `name`');
CALL `p_add_col_if_missing`('t_payment_method','enabled','`enabled` tinyint NOT NULL DEFAULT 1 COMMENT \'0-禁用 1-启用\' AFTER `sort_order`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','shop_id','`shop_id` int NOT NULL DEFAULT 0 COMMENT \'0=全店默认\' AFTER `id`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','enabled','`enabled` tinyint NOT NULL DEFAULT 0 COMMENT \'夜间九折独立开关\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','pay_rate','`pay_rate` decimal(5,4) NOT NULL DEFAULT 0.9000 COMMENT \'实付倍率，0.9=九折\' AFTER `enabled`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','min_base_yuan','`min_base_yuan` decimal(10,2) NOT NULL DEFAULT 60.00 COMMENT \'券后满额(元)才叠九折\' AFTER `pay_rate`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','time_start','`time_start` varchar(8) NOT NULL DEFAULT \'00:30\' AFTER `min_base_yuan`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','time_end','`time_end` varchar(8) NOT NULL DEFAULT \'03:00\' AFTER `time_start`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','zone_id','`zone_id` varchar(64) NOT NULL DEFAULT \'Asia/Shanghai\' AFTER `time_end`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','eligible_dining_types','`eligible_dining_types` varchar(256) NOT NULL DEFAULT \'["堂食"]\' AFTER `zone_id`');
CALL `p_add_col_if_missing`('t_payment_ninefold_config','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `eligible_dining_types`');
CALL `p_add_col_if_missing`('t_payment_refund_guard','shop_id','`shop_id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_payment_refund_guard','order_no','`order_no` varchar(64) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_refund_guard','idempotency_key','`idempotency_key` varchar(64) NOT NULL AFTER `order_no`');
CALL `p_add_col_if_missing`('t_payment_refund_guard','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `idempotency_key`');
CALL `p_add_col_if_missing`('t_payment_refund_guard','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_payment_refund_request','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_payment_refund_request','shop_id','`shop_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_payment_refund_request','order_no','`order_no` varchar(64) NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_payment_refund_request','idempotency_key','`idempotency_key` varchar(64) NOT NULL AFTER `order_no`');
CALL `p_add_col_if_missing`('t_payment_refund_request','out_refund_no','`out_refund_no` varchar(64) NOT NULL AFTER `idempotency_key`');
CALL `p_add_col_if_missing`('t_payment_refund_request','requested_fen','`requested_fen` int NOT NULL AFTER `out_refund_no`');
CALL `p_add_col_if_missing`('t_payment_refund_request','applied_fen','`applied_fen` int NOT NULL DEFAULT 0 AFTER `requested_fen`');
CALL `p_add_col_if_missing`('t_payment_refund_request','status','`status` varchar(24) NOT NULL DEFAULT \'REQUESTED\' AFTER `applied_fen`');
CALL `p_add_col_if_missing`('t_payment_refund_request','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `status`');
CALL `p_add_col_if_missing`('t_payment_refund_request','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_permission','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_permission','permission_code','`permission_code` varchar(64) NOT NULL COMMENT \'权限编码，如 order:view, dish:manage\' AFTER `id`');
CALL `p_add_col_if_missing`('t_permission','permission_name','`permission_name` varchar(64) NOT NULL COMMENT \'权限名称\' AFTER `permission_code`');
CALL `p_add_col_if_missing`('t_permission','module','`module` varchar(32) NULL DEFAULT NULL COMMENT \'模块：order/dish/statistics等\' AFTER `permission_name`');
CALL `p_add_col_if_missing`('t_permission','remark','`remark` varchar(255) NULL DEFAULT NULL AFTER `module`');
CALL `p_add_col_if_missing`('t_permission','sort_order','`sort_order` int NULL DEFAULT 0 AFTER `remark`');
CALL `p_add_col_if_missing`('t_queue_ticket','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_queue_ticket','ticket_no','`ticket_no` varchar(32) NOT NULL COMMENT \'排队号，如 A102\' AFTER `id`');
CALL `p_add_col_if_missing`('t_queue_ticket','shop_id','`shop_id` int NOT NULL DEFAULT 1 COMMENT \'门店ID，连锁按门店隔离\' AFTER `ticket_no`');
CALL `p_add_col_if_missing`('t_queue_ticket','openid','`openid` varchar(100) NOT NULL COMMENT \'用户 openid\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_queue_ticket','mobile','`mobile` varchar(20) NOT NULL COMMENT \'手机号\' AFTER `openid`');
CALL `p_add_col_if_missing`('t_queue_ticket','party_size','`party_size` int NOT NULL COMMENT \'就餐人数\' AFTER `mobile`');
CALL `p_add_col_if_missing`('t_queue_ticket','dine_type','`dine_type` varchar(32) NOT NULL COMMENT \'就餐方式，如 dinein\' AFTER `party_size`');
CALL `p_add_col_if_missing`('t_queue_ticket','remark','`remark` varchar(255) NULL DEFAULT NULL COMMENT \'备注\' AFTER `dine_type`');
CALL `p_add_col_if_missing`('t_queue_ticket','status','`status` enum(\'waiting\',\'calling\',\'seated\',\'cancelled\',\'expired\') NOT NULL DEFAULT \'waiting\' COMMENT \'排队状态\' AFTER `remark`');
CALL `p_add_col_if_missing`('t_queue_ticket','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `status`');
CALL `p_add_col_if_missing`('t_queue_ticket','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_region','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_region','code','`code` varchar(32) NOT NULL COMMENT \'区域编码（唯一）\' AFTER `id`');
CALL `p_add_col_if_missing`('t_region','name','`name` varchar(64) NOT NULL COMMENT \'区域名称\' AFTER `code`');
CALL `p_add_col_if_missing`('t_region','parent_id','`parent_id` int NULL DEFAULT NULL COMMENT \'父区域ID，可空\' AFTER `name`');
CALL `p_add_col_if_missing`('t_role','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_role','role_code','`role_code` varchar(32) NOT NULL COMMENT \'角色编码，如 super_admin, order_manager\' AFTER `id`');
CALL `p_add_col_if_missing`('t_role','role_name','`role_name` varchar(64) NOT NULL COMMENT \'角色名称\' AFTER `role_code`');
CALL `p_add_col_if_missing`('t_role','remark','`remark` varchar(255) NULL DEFAULT NULL COMMENT \'备注\' AFTER `role_name`');
CALL `p_add_col_if_missing`('t_role','sort_order','`sort_order` int NULL DEFAULT 0 COMMENT \'排序\' AFTER `remark`');
CALL `p_add_col_if_missing`('t_role_permission','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_role_permission','role_id','`role_id` int NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_role_permission','permission_id','`permission_id` int NOT NULL AFTER `role_id`');
CALL `p_add_col_if_missing`('t_shift','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_shift','admin_id','`admin_id` int NOT NULL COMMENT \'收银员\' AFTER `id`');
CALL `p_add_col_if_missing`('t_shift','shop_id','`shop_id` int NULL DEFAULT NULL AFTER `admin_id`');
CALL `p_add_col_if_missing`('t_shift','start_time','`start_time` datetime NOT NULL COMMENT \'班次开始\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_shift','end_time','`end_time` datetime NULL DEFAULT NULL COMMENT \'班次结束\' AFTER `start_time`');
CALL `p_add_col_if_missing`('t_shift','start_cash','`start_cash` decimal(10,2) NULL DEFAULT 0.00 COMMENT \'开班现金\' AFTER `end_time`');
CALL `p_add_col_if_missing`('t_shift','end_cash','`end_cash` decimal(10,2) NULL DEFAULT NULL COMMENT \'交班现金\' AFTER `start_cash`');
CALL `p_add_col_if_missing`('t_shift','order_count','`order_count` int NULL DEFAULT 0 AFTER `end_cash`');
CALL `p_add_col_if_missing`('t_shift','total_amount','`total_amount` decimal(12,2) NULL DEFAULT 0.00 AFTER `order_count`');
CALL `p_add_col_if_missing`('t_shift','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `total_amount`');
CALL `p_add_col_if_missing`('t_shop','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_shop','name','`name` varchar(64) NOT NULL COMMENT \'门店名称\' AFTER `id`');
CALL `p_add_col_if_missing`('t_shop','code','`code` varchar(32) NULL DEFAULT NULL COMMENT \'门店编码\' AFTER `name`');
CALL `p_add_col_if_missing`('t_shop','region_id','`region_id` int NULL DEFAULT NULL COMMENT \'区域ID，关联 t_region.id\' AFTER `code`');
CALL `p_add_col_if_missing`('t_shop','address','`address` varchar(255) NULL DEFAULT NULL COMMENT \'地址\' AFTER `region_id`');
CALL `p_add_col_if_missing`('t_shop','latitude','`latitude` decimal(10,7) NULL DEFAULT NULL COMMENT \'纬度\' AFTER `address`');
CALL `p_add_col_if_missing`('t_shop','longitude','`longitude` decimal(10,7) NULL DEFAULT NULL COMMENT \'经度\' AFTER `latitude`');
CALL `p_add_col_if_missing`('t_shop','contact_phone','`contact_phone` varchar(20) NULL DEFAULT NULL COMMENT \'联系电话\' AFTER `longitude`');
CALL `p_add_col_if_missing`('t_shop','open_time','`open_time` time NULL DEFAULT NULL COMMENT \'营业开始时间\' AFTER `contact_phone`');
CALL `p_add_col_if_missing`('t_shop','close_time','`close_time` time NULL DEFAULT NULL COMMENT \'营业结束时间\' AFTER `open_time`');
CALL `p_add_col_if_missing`('t_shop','status','`status` tinyint NOT NULL DEFAULT 1 COMMENT \'状态：0-停用 1-营业\' AFTER `close_time`');
CALL `p_add_col_if_missing`('t_shop','sort_order','`sort_order` int NOT NULL DEFAULT 0 COMMENT \'列表排序，越小越靠前\' AFTER `status`');
CALL `p_add_col_if_missing`('t_shop','ordering_open','`ordering_open` tinyint NOT NULL DEFAULT 1 COMMENT \'C端接单营业：1营业 0休息\' AFTER `sort_order`');
CALL `p_add_col_if_missing`('t_shop','ordering_review','`ordering_review` tinyint NOT NULL DEFAULT 0 COMMENT \'C端评价展示：1开 0关\' AFTER `ordering_open`');
CALL `p_add_col_if_missing`('t_shop','remark','`remark` varchar(255) NULL DEFAULT NULL COMMENT \'备注\' AFTER `ordering_review`');
CALL `p_add_col_if_missing`('t_shop','offline_collect_wechat_payload','`offline_collect_wechat_payload` varchar(2048) NULL DEFAULT NULL COMMENT \'微信个人收款码解码后的跳转串（如 wxp://）\' AFTER `remark`');
CALL `p_add_col_if_missing`('t_shop','offline_collect_alipay_payload','`offline_collect_alipay_payload` varchar(2048) NULL DEFAULT NULL COMMENT \'支付宝收款码解码后的跳转串\' AFTER `offline_collect_wechat_payload`');
CALL `p_add_col_if_missing`('t_shop','offline_collect_wechat_image_path','`offline_collect_wechat_image_path` varchar(512) NULL DEFAULT NULL COMMENT \'上传的微信收款码图片相对/绝对路径（可选备份）\' AFTER `offline_collect_alipay_payload`');
CALL `p_add_col_if_missing`('t_shop','offline_collect_alipay_image_path','`offline_collect_alipay_image_path` varchar(512) NULL DEFAULT NULL COMMENT \'上传的支付宝收款码图片路径\' AFTER `offline_collect_wechat_image_path`');
CALL `p_add_col_if_missing`('t_shop','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `offline_collect_alipay_image_path`');
CALL `p_add_col_if_missing`('t_shop','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_shop_printer_config','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_shop_printer_config','shop_id','`shop_id` int NOT NULL COMMENT \'门店ID，关联 t_shop.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_shop_printer_config','feie_url','`feie_url` varchar(255) NULL DEFAULT NULL COMMENT \'飞鹅云 API 地址，空则回退系统全局 feieyun.url\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_shop_printer_config','feie_user','`feie_user` varchar(128) NOT NULL COMMENT \'飞鹅云 user\' AFTER `feie_url`');
CALL `p_add_col_if_missing`('t_shop_printer_config','feie_ukey','`feie_ukey` varchar(128) NOT NULL COMMENT \'飞鹅云 ukey\' AFTER `feie_user`');
CALL `p_add_col_if_missing`('t_shop_printer_config','printer_sn','`printer_sn` varchar(64) NOT NULL COMMENT \'门店默认打印机 SN\' AFTER `feie_ukey`');
CALL `p_add_col_if_missing`('t_shop_printer_config','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `printer_sn`');
CALL `p_add_col_if_missing`('t_shop_printer_config','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','shop_id','`shop_id` int NOT NULL COMMENT \'t_shop.id\' FIRST');
CALL `p_add_col_if_missing`('t_shop_takeout_config','enabled','`enabled` tinyint NOT NULL DEFAULT 0 COMMENT \'1=开启外卖\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','delivery_fee','`delivery_fee` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT \'基础配送费（元）\' AFTER `enabled`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','min_order_amount','`min_order_amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT \'起送价（元，按商品小计不含配送费）\' AFTER `delivery_fee`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','free_delivery_threshold','`free_delivery_threshold` decimal(10,2) NULL DEFAULT NULL COMMENT \'满额免配送费；NULL 表示不免\' AFTER `min_order_amount`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','max_delivery_distance_km','`max_delivery_distance_km` decimal(5,2) NOT NULL DEFAULT 5.00 COMMENT \'最远配送距离(公里)，超出不可下单\' AFTER `free_delivery_threshold`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','free_delivery_max_distance_km','`free_delivery_max_distance_km` decimal(5,2) NOT NULL DEFAULT 5.00 COMMENT \'满额免配送费的最远距离(公里)\' AFTER `max_delivery_distance_km`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','delivery_fee_tiers_json','`delivery_fee_tiers_json` text NULL DEFAULT NULL COMMENT \'距离阶梯运费 JSON，如 [{"toKm":3,"fee":5},{"toKm":4,"fee":8},{"toKm":5,"fee":10}]\' AFTER `free_delivery_max_distance_km`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','lead_time_minutes','`lead_time_minutes` int NOT NULL DEFAULT 30 COMMENT \'预计备餐分钟（展示用）\' AFTER `delivery_fee_tiers_json`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','remark','`remark` varchar(500) NULL DEFAULT NULL COMMENT \'对外说明\' AFTER `lead_time_minutes`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','zsq_enabled','`zsq_enabled` tinyint NOT NULL DEFAULT 0 COMMENT \'1=启用真省钱聚合配送\' AFTER `remark`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','zsq_auto_dispatch','`zsq_auto_dispatch` tinyint NOT NULL DEFAULT 1 COMMENT \'1=商家接单后自动发真省钱配送\' AFTER `zsq_enabled`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','zsq_from_address_id','`zsq_from_address_id` bigint NULL DEFAULT NULL COMMENT \'真省钱发单店铺 id，空则用默认店铺\' AFTER `zsq_auto_dispatch`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','zsq_city_name','`zsq_city_name` varchar(64) NULL DEFAULT NULL COMMENT \'地址解析城市，空则取门店城市或江门市\' AFTER `zsq_from_address_id`');
CALL `p_add_col_if_missing`('t_shop_takeout_config','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `zsq_city_name`');
CALL `p_add_col_if_missing`('t_stock_in','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_stock_in','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID\' AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_in','material_id','`material_id` int NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_stock_in','quantity','`quantity` decimal(12,3) NOT NULL COMMENT \'入库数量\' AFTER `material_id`');
CALL `p_add_col_if_missing`('t_stock_in','price','`price` decimal(10,2) NULL DEFAULT NULL COMMENT \'单价（成本）\' AFTER `quantity`');
CALL `p_add_col_if_missing`('t_stock_in','total_amount','`total_amount` decimal(12,2) NULL DEFAULT NULL COMMENT \'总金额\' AFTER `price`');
CALL `p_add_col_if_missing`('t_stock_in','remark','`remark` varchar(255) NULL DEFAULT NULL AFTER `total_amount`');
CALL `p_add_col_if_missing`('t_stock_in','operator_id','`operator_id` int NULL DEFAULT NULL AFTER `remark`');
CALL `p_add_col_if_missing`('t_stock_in','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_stock_out','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_stock_out','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID\' AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_out','material_id','`material_id` int NOT NULL AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_stock_out','quantity','`quantity` decimal(12,3) NOT NULL COMMENT \'出库数量\' AFTER `material_id`');
CALL `p_add_col_if_missing`('t_stock_out','reason','`reason` varchar(32) NULL DEFAULT NULL COMMENT \'原因：consume/transfer/waste\' AFTER `quantity`');
CALL `p_add_col_if_missing`('t_stock_out','remark','`remark` varchar(255) NULL DEFAULT NULL AFTER `reason`');
CALL `p_add_col_if_missing`('t_stock_out','operator_id','`operator_id` int NULL DEFAULT NULL AFTER `remark`');
CALL `p_add_col_if_missing`('t_stock_out','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_stock_prep_config','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_stock_prep_config','shop_id','`shop_id` int NOT NULL COMMENT \'门店ID\' AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_prep_config','safe_stock_rate','`safe_stock_rate` decimal(5,2) NOT NULL DEFAULT 0.10 COMMENT \'安全库存系数\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_stock_prep_config','default_loss_rate','`default_loss_rate` decimal(5,2) NOT NULL DEFAULT 0.05 COMMENT \'BOM未填损耗时的默认损耗率\' AFTER `safe_stock_rate`');
CALL `p_add_col_if_missing`('t_stock_prep_config','forecast_days','`forecast_days` int NOT NULL DEFAULT 3 COMMENT \'默认预测天数\' AFTER `default_loss_rate`');
CALL `p_add_col_if_missing`('t_stock_prep_config','history_days','`history_days` int NOT NULL DEFAULT 30 COMMENT \'默认回溯天数\' AFTER `forecast_days`');
CALL `p_add_col_if_missing`('t_stock_prep_config','weather_factor','`weather_factor` decimal(5,2) NOT NULL DEFAULT 1.00 COMMENT \'天气修正上限参考/扩展用\' AFTER `history_days`');
CALL `p_add_col_if_missing`('t_stock_prep_config','holiday_factor','`holiday_factor` decimal(5,2) NOT NULL DEFAULT 1.20 COMMENT \'节假日参考系数/扩展用\' AFTER `weather_factor`');
CALL `p_add_col_if_missing`('t_stock_prep_config','member_factor','`member_factor` decimal(5,2) NOT NULL DEFAULT 1.00 COMMENT \'会员客流热度系数(充值不计销量，仅乘在预测上)\' AFTER `holiday_factor`');
CALL `p_add_col_if_missing`('t_stock_prep_config','is_enabled','`is_enabled` tinyint NOT NULL DEFAULT 1 AFTER `member_factor`');
CALL `p_add_col_if_missing`('t_stock_prep_config','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `is_enabled`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','run_id','`run_id` bigint NOT NULL COMMENT \'批次ID\' AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','stat_date','`stat_date` date NOT NULL COMMENT \'预测自然日\' AFTER `run_id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','iso_day_of_week','`iso_day_of_week` tinyint NOT NULL COMMENT \'周一=1…周日=7\' AFTER `stat_date`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','day_kind','`day_kind` varchar(64) NOT NULL COMMENT \'工作日/周末/调休工作日(含补班说明)等\' AFTER `iso_day_of_week`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','is_holiday','`is_holiday` tinyint NOT NULL DEFAULT 0 COMMENT \'是否按法定节假日休息并施加节假日系数\' AFTER `day_kind`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','holiday_name','`holiday_name` varchar(64) NULL DEFAULT NULL COMMENT \'节假日名称或自定义\' AFTER `is_holiday`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','factor_holiday','`factor_holiday` decimal(8,4) NOT NULL DEFAULT 1.0000 AFTER `holiday_name`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','factor_weather','`factor_weather` decimal(8,4) NOT NULL DEFAULT 1.0000 AFTER `factor_holiday`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','factor_composite','`factor_composite` decimal(8,4) NOT NULL DEFAULT 1.0000 AFTER `factor_weather`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','weather_available','`weather_available` tinyint NOT NULL DEFAULT 0 AFTER `factor_composite`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','weather_summary','`weather_summary` varchar(256) NULL DEFAULT NULL AFTER `weather_available`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','weather_code','`weather_code` int NULL DEFAULT NULL AFTER `weather_summary`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','weather_precip_prob','`weather_precip_prob` int NULL DEFAULT NULL COMMENT \'降水概率max %\' AFTER `weather_code`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','weather_temp_max','`weather_temp_max` decimal(5,1) NULL DEFAULT NULL COMMENT \'预报最高温℃\' AFTER `weather_precip_prob`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','predicted_servings_sum','`predicted_servings_sum` int NULL DEFAULT NULL COMMENT \'本批次当日预测菜品份数合计(预测范围内)\' AFTER `weather_temp_max`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','actual_servings_forecast_dishes','`actual_servings_forecast_dishes` int NULL DEFAULT NULL COMMENT \'预测范围内菜品当日实际份数合计\' AFTER `predicted_servings_sum`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','actual_servings_all_dishes','`actual_servings_all_dishes` int NULL DEFAULT NULL COMMENT \'当日全店订单明细销量合计(所有菜品)\' AFTER `actual_servings_forecast_dishes`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','actual_order_count','`actual_order_count` int NULL DEFAULT NULL COMMENT \'当日成功单数\' AFTER `actual_servings_all_dishes`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','daily_stat_total_amount','`daily_stat_total_amount` decimal(12,2) NULL DEFAULT NULL COMMENT \'日结表营业额 t_daily_stat.total_amount\' AFTER `actual_order_count`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','daily_stat_discount_amount','`daily_stat_discount_amount` decimal(12,2) NULL DEFAULT NULL COMMENT \'日结优惠合计\' AFTER `daily_stat_total_amount`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','daily_stat_refund_amount','`daily_stat_refund_amount` decimal(12,2) NULL DEFAULT NULL COMMENT \'日结退款合计\' AFTER `daily_stat_discount_amount`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','daily_stat_material_cost','`daily_stat_material_cost` decimal(12,2) NULL DEFAULT NULL COMMENT \'日结原料成本\' AFTER `daily_stat_refund_amount`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','daily_stat_settled','`daily_stat_settled` tinyint NULL DEFAULT NULL COMMENT \'1=日结已 settled_at 非空\' AFTER `daily_stat_material_cost`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_day','day_validated_at','`day_validated_at` datetime NULL DEFAULT NULL COMMENT \'该预测日本行校验完成时间\' AFTER `daily_stat_settled`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','run_id','`run_id` bigint NOT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','stat_date','`stat_date` date NOT NULL AFTER `run_id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','dish_id','`dish_id` int NULL DEFAULT NULL COMMENT \'匹配 t_dish.id，可能为空\' AFTER `stat_date`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','dish_name','`dish_name` varchar(100) NOT NULL AFTER `dish_id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','baseline_avg','`baseline_avg` decimal(14,4) NOT NULL DEFAULT 0.0000 COMMENT \'该日星期几基线日均份数\' AFTER `dish_name`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','predicted_servings','`predicted_servings` int NOT NULL DEFAULT 0 COMMENT \'预测备货份数\' AFTER `baseline_avg`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','actual_quantity','`actual_quantity` int NULL DEFAULT NULL COMMENT \'当日该菜品实际销量(订单明细汇总)\' AFTER `predicted_servings`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_dish','validated_at','`validated_at` datetime NULL DEFAULT NULL COMMENT \'写入实际销量的时间\' AFTER `actual_quantity`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID，与订单统计一致；NULL 表示未按店过滤的汇总\' AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'生成时间\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','history_days','`history_days` int NOT NULL COMMENT \'回溯天数\' AFTER `created_at`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','forecast_days','`forecast_days` int NOT NULL COMMENT \'预测天数\' AFTER `history_days`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','history_start_date','`history_start_date` date NOT NULL COMMENT \'历史统计起始日\' AFTER `forecast_days`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','history_end_at','`history_end_at` datetime NOT NULL COMMENT \'历史统计结束时刻\' AFTER `history_start_date`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','model_notes','`model_notes` varchar(500) NULL DEFAULT NULL COMMENT \'模型说明\' AFTER `history_end_at`');
CALL `p_add_col_if_missing`('t_stock_prep_forecast_run','last_validated_at','`last_validated_at` datetime NULL DEFAULT NULL COMMENT \'最近一次校验写入时间\' AFTER `model_notes`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'备货计划ID\' FIRST');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','shop_id','`shop_id` int NOT NULL COMMENT \'门店ID\' AFTER `id`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','run_id','`run_id` bigint NOT NULL COMMENT \'预测批次ID(t_stock_prep_forecast_run.id)\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','prepare_date','`prepare_date` date NOT NULL COMMENT \'备货日期(与预测 stat_date 对齐)\' AFTER `run_id`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','material_id','`material_id` int NOT NULL COMMENT \'原材料ID\' AFTER `prepare_date`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','current_stock','`current_stock` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'生成时 t_material.stock 快照\' AFTER `material_id`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','forecast_consume','`forecast_consume` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'预测消耗总量\' AFTER `current_stock`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','safe_stock','`safe_stock` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'安全库存\' AFTER `forecast_consume`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','suggest_qty','`suggest_qty` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'系统建议备货量\' AFTER `safe_stock`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','manual_adjust','`manual_adjust` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'人工调整量(±)\' AFTER `suggest_qty`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','final_qty','`final_qty` decimal(12,3) NOT NULL DEFAULT 0.000 COMMENT \'最终确认备货量\' AFTER `manual_adjust`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','status','`status` tinyint NOT NULL DEFAULT 0 COMMENT \'0待确认 1已确认 2已采购 3已入库\' AFTER `final_qty`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','operator_id','`operator_id` int NULL DEFAULT NULL COMMENT \'操作员 t_admin.id\' AFTER `status`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `operator_id`');
CALL `p_add_col_if_missing`('t_stock_prepare_plan','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_system_config','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_system_config','shop_id','`shop_id` int NOT NULL DEFAULT 0 COMMENT \'0=全门店默认，>0=t_shop.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_system_config','config_key','`config_key` varchar(100) NOT NULL COMMENT \'配置键，如 feieyun.user、invite.poster.qr.x\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_system_config','config_value','`config_value` varchar(500) NULL DEFAULT NULL COMMENT \'配置值\' AFTER `config_key`');
CALL `p_add_col_if_missing`('t_system_config','remark','`remark` varchar(255) NULL DEFAULT NULL COMMENT \'说明\' AFTER `config_value`');
CALL `p_add_col_if_missing`('t_table','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_table','shop_id','`shop_id` int NULL DEFAULT NULL COMMENT \'门店ID；NULL 表示未迁移的历史数据\' AFTER `id`');
CALL `p_add_col_if_missing`('t_table','number','`number` varchar(20) NULL DEFAULT NULL COMMENT \'桌号\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_table','open_time','`open_time` datetime NULL DEFAULT NULL COMMENT \'开台时间\' AFTER `number`');
CALL `p_add_col_if_missing`('t_table','qrcode','`qrcode` varchar(100) NULL DEFAULT NULL COMMENT \'二维码\' AFTER `open_time`');
CALL `p_add_col_if_missing`('t_table','status','`status` int(1) unsigned zerofill NOT NULL AFTER `qrcode`');
CALL `p_add_col_if_missing`('t_table','out_time','`out_time` datetime NULL DEFAULT NULL COMMENT \'结账时间\' AFTER `status`');
CALL `p_add_col_if_missing`('t_table','amount','`amount` decimal(6,2) NULL DEFAULT NULL COMMENT \'金额\' AFTER `out_time`');
CALL `p_add_col_if_missing`('t_table','order_no','`order_no` varchar(22) NULL DEFAULT NULL COMMENT \'订单号\' AFTER `amount`');
CALL `p_add_col_if_missing`('t_takeout_delivery','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_takeout_delivery','order_id','`order_id` int NOT NULL COMMENT \'t_order.id\' AFTER `id`');
CALL `p_add_col_if_missing`('t_takeout_delivery','order_no','`order_no` varchar(32) NOT NULL AFTER `order_id`');
CALL `p_add_col_if_missing`('t_takeout_delivery','shop_id','`shop_id` int NULL DEFAULT NULL AFTER `order_no`');
CALL `p_add_col_if_missing`('t_takeout_delivery','user_address_id','`user_address_id` bigint NULL DEFAULT NULL COMMENT \'下单时选用的 t_user_address.id\' AFTER `shop_id`');
CALL `p_add_col_if_missing`('t_takeout_delivery','receiver_name','`receiver_name` varchar(32) NULL DEFAULT NULL AFTER `user_address_id`');
CALL `p_add_col_if_missing`('t_takeout_delivery','receiver_phone','`receiver_phone` varchar(20) NOT NULL AFTER `receiver_name`');
CALL `p_add_col_if_missing`('t_takeout_delivery','address_full','`address_full` varchar(512) NOT NULL AFTER `receiver_phone`');
CALL `p_add_col_if_missing`('t_takeout_delivery','lng','`lng` decimal(10,6) NULL DEFAULT NULL AFTER `address_full`');
CALL `p_add_col_if_missing`('t_takeout_delivery','lat','`lat` decimal(10,6) NULL DEFAULT NULL AFTER `lng`');
CALL `p_add_col_if_missing`('t_takeout_delivery','delivery_fee','`delivery_fee` decimal(10,2) NOT NULL DEFAULT 0.00 AFTER `lat`');
CALL `p_add_col_if_missing`('t_takeout_delivery','dispatch_status','`dispatch_status` varchar(24) NOT NULL DEFAULT \'submitted\' COMMENT \'submitted|paid|accepted|delivering|completed|cancelled\' AFTER `delivery_fee`');
CALL `p_add_col_if_missing`('t_takeout_delivery','merchant_remark','`merchant_remark` varchar(500) NULL DEFAULT NULL AFTER `dispatch_status`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_open_order_id','`zsq_open_order_id` bigint NULL DEFAULT NULL COMMENT \'真省钱 openOrderId（ZsqCreateOrderResult.id）\' AFTER `merchant_remark`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_order_id','`zsq_order_id` varchar(64) NULL DEFAULT NULL COMMENT \'真省钱业务订单号\' AFTER `zsq_open_order_id`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_shop_number','`zsq_shop_number` varchar(32) NULL DEFAULT NULL COMMENT \'真省钱发单店铺编号\' AFTER `zsq_order_id`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_parent_order_no','`zsq_parent_order_no` varchar(64) NULL DEFAULT NULL COMMENT \'真省钱配送母单号\' AFTER `zsq_shop_number`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_delivery_codes_json','`zsq_delivery_codes_json` varchar(256) NULL DEFAULT NULL COMMENT \'已选配送渠道 deliveryCode JSON 数组\' AFTER `zsq_parent_order_no`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_quote_json','`zsq_quote_json` text NULL DEFAULT NULL COMMENT \'最近一次询价快照 JSON\' AFTER `zsq_delivery_codes_json`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_dispatch_json','`zsq_dispatch_json` text NULL DEFAULT NULL COMMENT \'最近一次发配送响应 JSON\' AFTER `zsq_quote_json`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_delivery_send_status','`zsq_delivery_send_status` int NULL DEFAULT NULL COMMENT \'真省钱 deliverySendStatus 原始值\' AFTER `zsq_dispatch_json`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_phase','`zsq_phase` varchar(32) NULL DEFAULT NULL COMMENT \'归一化阶段 WAITING_RIDER/TO_SHOP/TO_USER/DELIVERED/CANCELLED\' AFTER `zsq_delivery_send_status`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_dispatch_status','`zsq_dispatch_status` varchar(32) NOT NULL DEFAULT \'none\' COMMENT \'none|pending|dispatched|failed|rider_cancelled|completed\' AFTER `zsq_phase`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_rider_name','`zsq_rider_name` varchar(64) NULL DEFAULT NULL AFTER `zsq_dispatch_status`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_rider_phone','`zsq_rider_phone` varchar(32) NULL DEFAULT NULL AFTER `zsq_rider_name`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_rider_lat','`zsq_rider_lat` decimal(10,6) NULL DEFAULT NULL AFTER `zsq_rider_phone`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_rider_lng','`zsq_rider_lng` decimal(10,6) NULL DEFAULT NULL AFTER `zsq_rider_lat`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_rider_updated_at','`zsq_rider_updated_at` datetime NULL DEFAULT NULL AFTER `zsq_rider_lng`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_last_error','`zsq_last_error` varchar(512) NULL DEFAULT NULL COMMENT \'最近一次 ZSQ 错误文案\' AFTER `zsq_rider_updated_at`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_dispatch_attempts','`zsq_dispatch_attempts` int NOT NULL DEFAULT 0 COMMENT \'发配送尝试次数（含重发）\' AFTER `zsq_last_error`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_liability_fee','`zsq_liability_fee` decimal(10,2) NULL DEFAULT NULL COMMENT \'真省钱取消责任扣费（元）\' AFTER `zsq_dispatch_attempts`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_actual_fee','`zsq_actual_fee` decimal(10,2) NULL DEFAULT NULL COMMENT \'真省钱实际跑腿费用（元，来自 shopActualCost/discountLastMoney）\' AFTER `zsq_liability_fee`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_delivery_supplier_name','`zsq_delivery_supplier_name` varchar(64) NULL DEFAULT NULL COMMENT \'真省钱实际配送运力渠道（如京东特惠、美团等，来自 deliverySupplierName）\' AFTER `zsq_actual_fee`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_cancel_prompt','`zsq_cancel_prompt` varchar(512) NULL DEFAULT NULL COMMENT \'真省钱取消提示文案\' AFTER `zsq_delivery_supplier_name`');
CALL `p_add_col_if_missing`('t_takeout_delivery','zsq_cancel_json','`zsq_cancel_json` text NULL DEFAULT NULL COMMENT \'真省钱取消响应 JSON\' AFTER `zsq_cancel_prompt`');
CALL `p_add_col_if_missing`('t_takeout_delivery','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `zsq_cancel_json`');
CALL `p_add_col_if_missing`('t_takeout_delivery','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_unit','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_unit','label','`label` varchar(100) NULL DEFAULT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_unit','value','`value` varchar(100) NULL DEFAULT NULL AFTER `label`');
CALL `p_add_col_if_missing`('t_user','id','`id` int NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_user','name','`name` varchar(100) NULL DEFAULT NULL AFTER `id`');
CALL `p_add_col_if_missing`('t_user','openid','`openid` varchar(100) NULL DEFAULT NULL AFTER `name`');
CALL `p_add_col_if_missing`('t_user','phone','`phone` varchar(11) NULL DEFAULT NULL AFTER `openid`');
CALL `p_add_col_if_missing`('t_user','points','`points` int NULL DEFAULT NULL AFTER `phone`');
CALL `p_add_col_if_missing`('t_user','balance','`balance` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'账户余额(元)\' AFTER `points`');
CALL `p_add_col_if_missing`('t_user','gift_balance','`gift_balance` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'赠送金余额(元)，与 balance 本金分开\' AFTER `balance`');
CALL `p_add_col_if_missing`('t_user','principal_balance','`principal_balance` decimal(12,2) NOT NULL DEFAULT 0.00 COMMENT \'本金(元)；balance=principal_balance+gift_balance\' AFTER `gift_balance`');
CALL `p_add_col_if_missing`('t_user','session_key','`session_key` varchar(255) NULL DEFAULT NULL AFTER `principal_balance`');
CALL `p_add_col_if_missing`('t_user','avatar','`avatar` varchar(255) NULL DEFAULT NULL AFTER `session_key`');
CALL `p_add_col_if_missing`('t_user','time','`time` datetime NULL DEFAULT NULL COMMENT \'注册时间\' AFTER `avatar`');
CALL `p_add_col_if_missing`('t_user','user_type','`user_type` int NULL DEFAULT NULL COMMENT \'用户类型：0普通/1会员\' AFTER `time`');
CALL `p_add_col_if_missing`('t_user','invite_code','`invite_code` varchar(10) NULL DEFAULT NULL AFTER `user_type`');
CALL `p_add_col_if_missing`('t_user','level','`level` int NULL DEFAULT NULL COMMENT \'会员等级\' AFTER `invite_code`');
CALL `p_add_col_if_missing`('t_user','birthday','`birthday` varchar(10) NULL DEFAULT NULL COMMENT \'生日\' AFTER `level`');
CALL `p_add_col_if_missing`('t_user_activity_interaction','id','`id` int NOT NULL FIRST');
CALL `p_add_col_if_missing`('t_user_activity_interaction','user_id','`user_id` varchar(255) NULL DEFAULT NULL COMMENT \'用户ID（与用户表id对应）\' AFTER `id`');
CALL `p_add_col_if_missing`('t_user_activity_interaction','activity_id','`activity_id` varchar(255) NULL DEFAULT NULL COMMENT \'活动ID（与活动表id对应）\' AFTER `user_id`');
CALL `p_add_col_if_missing`('t_user_activity_interaction','interaction_type','`interaction_type` varchar(255) NULL DEFAULT NULL COMMENT \'交互类型：show(展示)/click(点击)/close(关闭)\' AFTER `activity_id`');
CALL `p_add_col_if_missing`('t_user_activity_interaction','interaction_time','`interaction_time` varchar(255) NULL DEFAULT NULL COMMENT \'交互时间\' AFTER `interaction_type`');
CALL `p_add_col_if_missing`('t_user_activity_interaction','date','`date` datetime NULL DEFAULT NULL COMMENT \'交互日期（用于按日过滤）\' AFTER `interaction_time`');
CALL `p_add_col_if_missing`('t_user_address','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_user_address','openid','`openid` varchar(100) NOT NULL COMMENT \'t_user.openid\' AFTER `id`');
CALL `p_add_col_if_missing`('t_user_address','contact_name','`contact_name` varchar(32) NULL DEFAULT NULL AFTER `openid`');
CALL `p_add_col_if_missing`('t_user_address','contact_phone','`contact_phone` varchar(20) NOT NULL AFTER `contact_name`');
CALL `p_add_col_if_missing`('t_user_address','tag','`tag` varchar(20) NULL DEFAULT NULL COMMENT \'家/公司/学校等\' AFTER `contact_phone`');
CALL `p_add_col_if_missing`('t_user_address','province','`province` varchar(32) NULL DEFAULT NULL AFTER `tag`');
CALL `p_add_col_if_missing`('t_user_address','city','`city` varchar(32) NULL DEFAULT NULL AFTER `province`');
CALL `p_add_col_if_missing`('t_user_address','district','`district` varchar(32) NULL DEFAULT NULL AFTER `city`');
CALL `p_add_col_if_missing`('t_user_address','detail_address','`detail_address` varchar(255) NOT NULL AFTER `district`');
CALL `p_add_col_if_missing`('t_user_address','lng','`lng` decimal(10,6) NULL DEFAULT NULL AFTER `detail_address`');
CALL `p_add_col_if_missing`('t_user_address','lat','`lat` decimal(10,6) NULL DEFAULT NULL AFTER `lng`');
CALL `p_add_col_if_missing`('t_user_address','is_default','`is_default` tinyint NOT NULL DEFAULT 0 AFTER `lat`');
CALL `p_add_col_if_missing`('t_user_address','created_at','`created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER `is_default`');
CALL `p_add_col_if_missing`('t_user_address','updated_at','`updated_at` datetime NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP AFTER `created_at`');
CALL `p_add_col_if_missing`('t_user_coupon','id','`id` bigint NOT NULL AUTO_INCREMENT COMMENT \'主键ID\' FIRST');
CALL `p_add_col_if_missing`('t_user_coupon','user_openid','`user_openid` varchar(100) NOT NULL COMMENT \'用户微信openid\' AFTER `id`');
CALL `p_add_col_if_missing`('t_user_coupon','coupon_id','`coupon_id` bigint NOT NULL COMMENT \'关联优惠券主表ID\' AFTER `user_openid`');
CALL `p_add_col_if_missing`('t_user_coupon','get_time','`get_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT \'领取时间\' AFTER `coupon_id`');
CALL `p_add_col_if_missing`('t_user_coupon','use_time','`use_time` datetime NULL DEFAULT NULL COMMENT \'使用时间（NULL为未使用）\' AFTER `get_time`');
CALL `p_add_col_if_missing`('t_user_coupon','order_no','`order_no` varchar(50) NULL DEFAULT NULL COMMENT \'关联订单号（使用后填充）\' AFTER `use_time`');
CALL `p_add_col_if_missing`('t_user_coupon','status','`status` tinyint NOT NULL DEFAULT 0 COMMENT \'状态：0-未使用 1-已使用 2-已失效\' AFTER `order_no`');
CALL `p_add_col_if_missing`('t_user_coupon','expire_time','`expire_time` datetime NULL DEFAULT NULL COMMENT \'优惠券失效时间（程序关联主表end_time填充）\' AFTER `status`');
CALL `p_add_col_if_missing`('t_user_last_shop','id','`id` bigint NOT NULL AUTO_INCREMENT FIRST');
CALL `p_add_col_if_missing`('t_user_last_shop','openid','`openid` varchar(100) NOT NULL COMMENT \'t_user.openid\' AFTER `id`');
CALL `p_add_col_if_missing`('t_user_last_shop','shop_id','`shop_id` int NOT NULL AFTER `openid`');
CALL `p_add_col_if_missing`('t_user_last_shop','updated_at','`updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER `shop_id`');

DROP PROCEDURE IF EXISTS `p_add_col_if_missing`;
SET FOREIGN_KEY_CHECKS=1;

-- KDS 设备可见岗（D026）：统一看板设备级岗分流
CREATE TABLE IF NOT EXISTS `t_kds_device_screen` (
  `device_id` bigint NOT NULL COMMENT 't_kds_device.id',
  `screen_tags` varchar(128) NOT NULL COMMENT '可见烤制岗，逗号分隔：meat_grill,veg_grill,seafood_special',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`device_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='KDS 设备可见岗';

-- 不可变支付账本（POS-SDC-101）
CREATE TABLE IF NOT EXISTS `t_payment_ledger` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '流水自增ID',
  `ledger_no` varchar(64) NOT NULL COMMENT '权威资金流水号',
  `request_id` varchar(64) NOT NULL COMMENT '幂等请求ID',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `order_id` bigint NOT NULL COMMENT '订单ID',
  `order_no` varchar(64) NOT NULL COMMENT '订单号',
  `terminal_id` varchar(32) DEFAULT NULL COMMENT '收银机终端编号',
  `drawer_session_id` bigint DEFAULT NULL COMMENT '钱箱会话ID',
  `employee_shift_id` bigint DEFAULT NULL COMMENT '员工班次ID',
  `operator_id` int DEFAULT NULL COMMENT '操作人管理员ID',
  `entry_type` varchar(24) NOT NULL COMMENT '流水类型：PAYMENT/REFUND/REVERSAL/ADJUSTMENT',
  `channel` varchar(32) NOT NULL COMMENT '支付渠道：CASH/WECHAT/ALIPAY/BALANCE_PRINCIPAL/GIFT/OTHER',
  `amount_fen` int NOT NULL COMMENT '资金金额(分)，正数为收入，负数为退款或冲正',
  `status` varchar(24) NOT NULL DEFAULT 'SUCCEEDED' COMMENT '流水状态：SUCCEEDED/FAILED/PENDING',
  `provider_transaction_id` varchar(128) DEFAULT NULL COMMENT '三方支付交易凭证号',
  `original_ledger_id` bigint DEFAULT NULL COMMENT '关联原流水ID(退款或冲正必填)',
  `occurred_at` datetime NOT NULL COMMENT '业务发生时间',
  `business_day` varchar(10) NOT NULL COMMENT '归属营业日(YYYY-MM-DD)',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '落账时间(不可修改)',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE KEY `uk_payment_ledger_no` (`ledger_no`) USING BTREE,
  UNIQUE KEY `uk_payment_ledger_req` (`shop_id`, `request_id`, `entry_type`, `channel`) USING BTREE,
  KEY `idx_payment_ledger_order` (`shop_id`, `order_no`) USING BTREE,
  KEY `idx_payment_ledger_day_channel` (`shop_id`, `business_day`, `channel`) USING BTREE,
  KEY `idx_payment_ledger_operator` (`shop_id`, `operator_id`, `occurred_at`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='不可变支付流水账本';

CREATE TABLE IF NOT EXISTS `t_drawer_session` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '钱箱会话自增ID',
  `session_no` varchar(64) NOT NULL COMMENT '会话流水号',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `terminal_id` varchar(64) NOT NULL DEFAULT 'POS-01' COMMENT '收银机终端编号',
  `drawer_code` varchar(32) NOT NULL DEFAULT 'DEFAULT' COMMENT '钱箱代码',
  `state` varchar(32) NOT NULL DEFAULT 'OPEN' COMMENT '状态：OPEN/CLOSING/CLOSED/REOPENED',
  `opened_by` int NOT NULL COMMENT '开班操作人管理员ID',
  `opened_at` datetime NOT NULL COMMENT '开班时间',
  `opening_float_fen` int NOT NULL DEFAULT 0 COMMENT '备用金初始金额(分)',
  `expected_cash_fen` int DEFAULT NULL COMMENT '系统计算应有现金(分)',
  `counted_cash_fen` int DEFAULT NULL COMMENT '实盘现金(分)',
  `variance_fen` int DEFAULT NULL COMMENT '差额(分) = counted - expected',
  `closed_by` int DEFAULT NULL COMMENT '关班人管理员ID',
  `closed_at` datetime DEFAULT NULL COMMENT '关班时间',
  `variance_reason_code` varchar(64) DEFAULT NULL COMMENT '长短款差额原因代码',
  `variance_note` varchar(255) DEFAULT NULL COMMENT '差额详细说明',
  `approved_by` int DEFAULT NULL COMMENT '审批主管管理员ID',
  `approved_at` datetime DEFAULT NULL COMMENT '审批时间',
  `business_day` varchar(16) NOT NULL COMMENT '归属营业日(YYYY-MM-DD)',
  `request_id` varchar(64) DEFAULT NULL COMMENT '开班幂等请求键',
  `close_request_id` varchar(64) DEFAULT NULL COMMENT '交班关箱幂等请求键',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本',
  `active_slot` int GENERATED ALWAYS AS (CASE WHEN `state` IN ('OPEN', 'CLOSING') THEN 1 ELSE NULL END) STORED COMMENT '活动会话槽位(唯一索引)',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_drawer_session_no` (`session_no`),
  UNIQUE KEY `uk_active_drawer` (`shop_id`, `terminal_id`, `drawer_code`, `active_slot`),
  KEY `idx_drawer_shop_day` (`shop_id`, `business_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='终端钱箱会话';

CREATE TABLE IF NOT EXISTS `t_cash_movement` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '现金动作流水ID',
  `movement_no` varchar(64) NOT NULL COMMENT '动作流水号',
  `drawer_session_id` bigint NOT NULL COMMENT '关联钱箱会话ID',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `movement_type` varchar(32) NOT NULL COMMENT '类型：OPENING_FLOAT/CASH_SALE/CASH_REFUND/CASH_IN/CASH_OUT/CASH_DROP/COUNT/ADJUSTMENT/NO_SALE',
  `amount_fen` int NOT NULL COMMENT '金额(分)，流入为正，流出为负',
  `current_balance_fen` int NOT NULL DEFAULT 0 COMMENT '动作发生后推导钱箱当前现金余额(分)',
  `reason_code` varchar(64) DEFAULT NULL COMMENT '原因代码',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `operator_id` int NOT NULL COMMENT '经办人管理员ID',
  `approver_id` int DEFAULT NULL COMMENT '审批人管理员ID',
  `order_id` bigint DEFAULT NULL COMMENT '关联订单ID',
  `order_no` varchar(64) DEFAULT NULL COMMENT '关联订单号',
  `payment_ledger_id` bigint DEFAULT NULL COMMENT '关联支付台账ID',
  `request_id` varchar(64) DEFAULT NULL COMMENT '幂等请求键',
  `occurred_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '动作发生时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '落账时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_cash_movement_no` (`movement_no`),
  KEY `idx_cm_session` (`drawer_session_id`),
  KEY `idx_cm_shop_time` (`shop_id`, `occurred_at`),
  KEY `idx_cm_order` (`shop_id`, `order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='不可表现金动作账本';

SET @dbname = DATABASE();
SET @tablename = 't_shift';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'drawer_session_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `drawer_session_id` bigint DEFAULT NULL COMMENT ''关联钱箱会话ID'''
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
  'ALTER TABLE `t_shift` ADD COLUMN `version` int DEFAULT 1 COMMENT ''乐观锁版本'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;


CREATE TABLE IF NOT EXISTS `t_daily_close_snapshot` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '快照自增主键',
  `snapshot_no` varchar(64) NOT NULL COMMENT '快照业务流水号',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `business_day` varchar(16) NOT NULL COMMENT '归属营业日 (YYYY-MM-DD)',
  `cutoff_ledger_id` bigint DEFAULT NULL COMMENT '截止支付台账最大主键ID',
  `cutoff_movement_id` bigint DEFAULT NULL COMMENT '截止现金动作流水最大主键ID',
  `cutoff_order_id` bigint DEFAULT NULL COMMENT '截止订单最大主键ID',
  `gross_sales_fen` bigint NOT NULL DEFAULT 0 COMMENT '总销售额（分）',
  `discount_fen` bigint NOT NULL DEFAULT 0 COMMENT '折扣折让总额（分）',
  `refund_fen` bigint NOT NULL DEFAULT 0 COMMENT '退款总额（分）',
  `net_sales_fen` bigint NOT NULL DEFAULT 0 COMMENT '净销售额（分）',
  `order_count` int NOT NULL DEFAULT 0 COMMENT '关账包含的已结算订单笔数',
  `status` varchar(32) NOT NULL DEFAULT 'CLOSED' COMMENT '状态: CLOSED/REOPENED',
  `integrity_hash` varchar(128) DEFAULT NULL COMMENT '快照防篡改哈希签名',
  `settled_by` int NOT NULL COMMENT '日结经办管理员ID',
  `settled_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '日结时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '落库时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_daily_snapshot` (`shop_id`, `business_day`),
  KEY `idx_snapshot_time` (`shop_id`, `settled_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='不可变日结关账快照';

CREATE TABLE IF NOT EXISTS `t_daily_adjustment` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '自增主键',
  `adjustment_no` varchar(64) NOT NULL COMMENT '调整单号',
  `snapshot_id` bigint NOT NULL COMMENT '关联日结快照ID',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `business_day` varchar(16) NOT NULL COMMENT '归属营业日',
  `adjustment_type` varchar(32) NOT NULL COMMENT '类型: POST_CLOSE_REFUND/POST_CLOSE_CASH/MANUAL_ADJUSTMENT',
  `amount_fen` int NOT NULL COMMENT '金额（分）',
  `order_id` bigint DEFAULT NULL COMMENT '关联订单ID',
  `payment_ledger_id` bigint DEFAULT NULL COMMENT '关联支付流水ID',
  `reason` varchar(255) DEFAULT NULL COMMENT '调整原因',
  `operator_id` int NOT NULL COMMENT '经办人ID',
  `approved_by` int DEFAULT NULL COMMENT '授权人ID',
  `occurred_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '发生时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_daily_adjustment_no` (`adjustment_no`),
  KEY `idx_adjustment_snapshot` (`snapshot_id`),
  KEY `idx_adjustment_shop_day` (`shop_id`, `business_day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='营业日关账后调整台账';

SET @dbname = DATABASE();
SET @tablename = 't_daily_stat';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'snapshot_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_daily_stat` ADD COLUMN `snapshot_id` bigint DEFAULT NULL COMMENT ''关联日结快照ID'''
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;


CREATE TABLE IF NOT EXISTS `t_channel_statement_batch` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '批次自增主键',
  `batch_no` varchar(64) NOT NULL COMMENT '批次流水号',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `channel` varchar(32) NOT NULL COMMENT '渠道类型: WECHAT/ALIPAY',
  `statement_date` date NOT NULL COMMENT '账单所属日期',
  `file_name` varchar(255) NOT NULL COMMENT '原始文件名',
  `file_hash_sha256` char(64) NOT NULL COMMENT '文件内容 SHA-256 摘要',
  `total_count` int NOT NULL DEFAULT 0 COMMENT '解析交易笔数',
  `total_amount_fen` bigint NOT NULL DEFAULT 0 COMMENT '交易总金额（分）',
  `fee_fen` bigint NOT NULL DEFAULT 0 COMMENT '手续费总额（分）',
  `net_amount_fen` bigint NOT NULL DEFAULT 0 COMMENT '结算净额（分）',
  `status` varchar(32) NOT NULL DEFAULT 'PARSED' COMMENT '状态: PARSED/FAILED',
  `error_summary` text DEFAULT NULL COMMENT '解析错误摘要',
  `imported_by` int DEFAULT NULL COMMENT '导入操作人ID',
  `imported_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '导入时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_statement_file_hash` (`shop_id`, `file_hash_sha256`),
  KEY `idx_statement_batch_day` (`shop_id`, `statement_date`),
  KEY `idx_statement_batch_no` (`batch_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='渠道对账单导入批次表';

CREATE TABLE IF NOT EXISTS `t_channel_statement_entry` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '明细自增主键',
  `batch_id` bigint NOT NULL COMMENT '所属导入批次ID',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `channel` varchar(32) NOT NULL COMMENT '渠道类型: WECHAT/ALIPAY',
  `channel_trade_no` varchar(128) NOT NULL COMMENT '渠道流水号',
  `merchant_order_no` varchar(128) NOT NULL COMMENT '商户订单号',
  `entry_type` varchar(32) NOT NULL COMMENT '交易类型: PAYMENT/REFUND',
  `amount_fen` int NOT NULL COMMENT '交易金额（分）',
  `fee_fen` int NOT NULL DEFAULT 0 COMMENT '手续费（分）',
  `net_amount_fen` int NOT NULL DEFAULT 0 COMMENT '应结净额（分）',
  `trade_time` datetime NOT NULL COMMENT '渠道交易发生时间',
  `matched_ledger_id` bigint DEFAULT NULL COMMENT '匹配内部支付台账ID',
  `match_status` varchar(32) NOT NULL DEFAULT 'UNMATCHED' COMMENT '匹配状态: MATCHED/UNMATCHED/AMOUNT_MISMATCH/TIMING_DIFFERENCE',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_statement_entry_batch` (`batch_id`),
  KEY `idx_statement_entry_order` (`shop_id`, `merchant_order_no`),
  KEY `idx_statement_entry_trade` (`shop_id`, `channel_trade_no`),
  KEY `idx_statement_entry_status` (`shop_id`, `match_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='渠道对账单明细表';

CREATE TABLE IF NOT EXISTS `t_reconciliation_case` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '自增主键',
  `case_no` varchar(64) NOT NULL COMMENT '差异单号',
  `shop_id` int NOT NULL COMMENT '门店ID',
  `business_day` date NOT NULL COMMENT '营业日',
  `channel` varchar(32) NOT NULL COMMENT '渠道类型: WECHAT/ALIPAY/INTERNAL',
  `layer` int NOT NULL COMMENT '差异层级: 1/2/3',
  `discrepancy_type` varchar(64) NOT NULL COMMENT '差异类型',
  `status` varchar(32) NOT NULL DEFAULT 'OPEN' COMMENT '状态: OPEN/INVESTIGATING/ADJUSTED/WRITTEN_OFF/CLOSED',
  `order_id` int DEFAULT NULL COMMENT '关联订单ID',
  `ledger_id` bigint DEFAULT NULL COMMENT '关联内部支付台账ID',
  `statement_entry_id` bigint DEFAULT NULL COMMENT '关联渠道对账明细ID',
  `internal_amount_fen` int NOT NULL DEFAULT 0 COMMENT '内部金额（分）',
  `channel_amount_fen` int NOT NULL DEFAULT 0 COMMENT '外部金额（分）',
  `difference_fen` int NOT NULL DEFAULT 0 COMMENT '差异金额（分）',
  `reason` varchar(255) DEFAULT NULL COMMENT '差异初步原因',
  `resolution_note` text DEFAULT NULL COMMENT '处置说明',
  `responsible_person` varchar(64) DEFAULT NULL COMMENT '责任人',
  `assigned_to` int DEFAULT NULL COMMENT '分派跟进人ID',
  `resolved_by` int DEFAULT NULL COMMENT '平账/关闭人ID',
  `resolved_at` datetime DEFAULT NULL COMMENT '处置完成时间',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_reconciliation_case_no` (`case_no`),
  KEY `idx_reconciliation_case_day` (`shop_id`, `business_day`, `status`),
  KEY `idx_reconciliation_case_type` (`shop_id`, `discrepancy_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC COMMENT='对账差异处理单表';
