-- ====================================================================
-- 增量迁移：AI 智能配餐与点餐系统数据表
-- 版本：V044
-- 说明：满足真实菜单属性增强、餐桌协同会话、智能方案与订单草稿全生命周期
-- ====================================================================

-- 1. 菜品食材与风味画像表 (扩展现有 t_dish)
CREATE TABLE IF NOT EXISTS `t_dish_food_profile` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `dish_id` INT NOT NULL COMMENT '关联 t_dish.id',
  `shop_id` INT NOT NULL DEFAULT 1 COMMENT '门店ID，支持多店独立覆盖',
  `ingredients` TEXT NULL COMMENT '主要食材原料清单（逗号分隔或JSON）',
  `seasonings` VARCHAR(500) NULL COMMENT '调味料成分',
  `non_spicy_available` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '后厨是否支持做不辣：1 支持，0 无法做不辣',
  `spice_options` VARCHAR(255) NOT NULL DEFAULT '["不辣","微辣","中辣","特辣"]' COMMENT '可用辣度选项JSON',
  `verified_allergens` VARCHAR(500) NULL COMMENT '已核验过敏原JSON，如 ["PEANUT","SEAFOOD"]',
  `cross_contact_risk` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否存在后厨交叉接触风险：0 无/未知，1 明确存在',
  `is_suitable_fitness` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否适合健身/减脂：1 是，0 否',
  `calories_kcal` DECIMAL(8,2) NULL COMMENT '每份卡路里(千卡)，未知则NULL',
  `protein_g` DECIMAL(8,2) NULL COMMENT '每份蛋白质(克)，未知则NULL',
  `fat_g` DECIMAL(8,2) NULL COMMENT '每份脂肪(克)，未知则NULL',
  `edible_weight_g` INT NULL COMMENT '可食部位净重(克)，未知则NULL',
  `nutrition_source` VARCHAR(100) NOT NULL DEFAULT 'UNVERIFIED' COMMENT '数据来源：UNVERIFIED(未核验), LAB_TEST(检测报告), ESTIMATED(食材估算)',
  `verified_at` DATETIME NULL COMMENT '核验认证时间',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dish_shop` (`dish_id`, `shop_id`),
  INDEX `idx_shop_fitness` (`shop_id`, `is_suitable_fitness`),
  INDEX `idx_non_spicy` (`shop_id`, `non_spicy_available`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='菜品食材、营养与风味画像扩展表';

-- 2. 餐桌多人协同点餐会话表
CREATE TABLE IF NOT EXISTS `t_dining_session` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `session_id` VARCHAR(64) NOT NULL COMMENT '会话业务唯一ID (UUID)',
  `shop_id` INT NOT NULL DEFAULT 1 COMMENT '关联门店ID',
  `table_number` VARCHAR(32) NOT NULL COMMENT '桌号',
  `party_size` INT NOT NULL COMMENT '用餐人数 (1~20)',
  `budget_fen` INT NOT NULL COMMENT '总预算 (整型分，如15000代表150元)',
  `currency` VARCHAR(8) NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `dining_mode` VARCHAR(16) NOT NULL DEFAULT 'dine_in' COMMENT '用餐模式：dine_in(堂食), take_out(自营外卖)',
  `include_drinks` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '预算是否包含酒水饮料：0 否，1 是',
  `strategy` VARCHAR(32) NOT NULL DEFAULT 'balanced' COMMENT '求解策略：balanced(均衡), budget_first(预算), satiety_first(吃饱), high_protein(高蛋白)',
  `table_goals` VARCHAR(255) NULL COMMENT '全桌共享目标JSON，如 ["fitness","weightloss"]',
  `revision` INT NOT NULL DEFAULT 1 COMMENT '乐观锁版本号，每次修改递增',
  `status` VARCHAR(32) NOT NULL DEFAULT 'COLLECTING' COMMENT '状态机：COLLECTING, PROPOSED, INFEASIBLE, CONFIRMED, EXPIRED',
  `active_plan_id` VARCHAR(64) NULL COMMENT '当前选中的方案ID',
  `expires_at` DATETIME NOT NULL COMMENT '会话失效时间 (默认2小时)',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_session_id` (`session_id`),
  INDEX `idx_shop_table` (`shop_id`, `table_number`, `status`),
  INDEX `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='餐桌协同点餐会话表';

-- 3. 餐桌成员偏好详情表 (餐桌 DNA)
CREATE TABLE IF NOT EXISTS `t_dining_session_member` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `session_id` VARCHAR(64) NOT NULL COMMENT '关联会话ID',
  `diner_id` VARCHAR(32) NOT NULL COMMENT '成员代号，如 P1, P2',
  `alias` VARCHAR(64) NULL COMMENT '成员昵称或标签',
  `is_non_spicy` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否不吃辣：1 是，0 否',
  `disliked_ingredients` VARCHAR(500) NULL COMMENT '忌口食材JSON，如 ["牛肉","葱"]',
  `verified_allergens` VARCHAR(500) NULL COMMENT '过敏原JSON，如 ["PEANUT"]',
  `portion_target` VARCHAR(16) NOT NULL DEFAULT 'normal' COMMENT '食量要求：small, normal, large',
  `fitness_goals` VARCHAR(255) NULL COMMENT '个人健身目标JSON，如 ["high_protein","low_fat"]',
  `join_shared_dishes` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否参与共享菜：1 是，0 否',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_session_diner` (`session_id`, `diner_id`),
  INDEX `idx_session_spicy` (`session_id`, `is_non_spicy`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='餐桌成员偏好画像表(餐桌DNA)';

-- 4. 智能推荐配餐方案表
CREATE TABLE IF NOT EXISTS `t_meal_plan` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `plan_id` VARCHAR(64) NOT NULL COMMENT '方案唯一ID',
  `session_id` VARCHAR(64) NOT NULL COMMENT '关联会话ID',
  `revision` INT NOT NULL COMMENT '生成该方案时的会话版本号',
  `menu_version` VARCHAR(64) NOT NULL COMMENT '依赖的菜单数据版本Hash',
  `strategy` VARCHAR(32) NOT NULL COMMENT '对应策略',
  `price_total_fen` INT NOT NULL COMMENT '方案核算总价(分)',
  `remaining_budget_fen` INT NOT NULL COMMENT '剩余预算(分)',
  `feasible` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否完全可行：1 是，0 否',
  `line_items_json` MEDIUMTEXT NOT NULL COMMENT '推荐商品列表JSON (sku, variant, quantity, unit_price_fen, subtotal_fen)',
  `allocation_matrix_json` MEDIUMTEXT NULL COMMENT '成员分配矩阵JSON (记录哪道菜服务哪位成员)',
  `explanation_cards_json` MEDIUMTEXT NULL COMMENT '每道菜与整桌的解释卡文案JSON',
  `score_details_json` TEXT NULL COMMENT '各项打分明细JSON',
  `conflict_details_json` TEXT NULL COMMENT '不可行时的冲突诊断与最小可行预算JSON',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_plan_id` (`plan_id`),
  INDEX `idx_session_revision` (`session_id`, `revision`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI智能配餐候选方案表';

-- 5. 待确认订单草稿表 (Order Draft)
CREATE TABLE IF NOT EXISTS `t_order_draft` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  `draft_id` VARCHAR(64) NOT NULL COMMENT '草稿唯一ID',
  `plan_id` VARCHAR(64) NOT NULL COMMENT '来源方案ID',
  `session_id` VARCHAR(64) NOT NULL COMMENT '关联会话ID',
  `shop_id` INT NOT NULL DEFAULT 1 COMMENT '门店ID',
  `table_number` VARCHAR(32) NOT NULL COMMENT '桌号',
  `openid` VARCHAR(64) NULL COMMENT '发起确认人微信OpenID',
  `menu_version` VARCHAR(64) NOT NULL COMMENT '校验时的菜单版本',
  `price_total_fen` INT NOT NULL COMMENT '最终应付金额(分)',
  `items_snapshot_json` MEDIUMTEXT NOT NULL COMMENT '锁定快照商品列表',
  `validation_status` VARCHAR(32) NOT NULL DEFAULT 'PENDING' COMMENT '校验状态：PENDING, PASSED, PRICE_CHANGED, OUT_OF_STOCK, EXPIRED',
  `idempotency_key` VARCHAR(64) NULL COMMENT '下单幂等键',
  `formal_order_no` VARCHAR(64) NULL COMMENT '转为正式单后的 t_order.order_no',
  `expires_at` DATETIME NOT NULL COMMENT '草稿有效期(默认5分钟)',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_draft_id` (`draft_id`),
  UNIQUE KEY `uk_idempotency` (`idempotency_key`),
  INDEX `idx_session_status` (`session_id`, `validation_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='AI配餐待确认订单草稿表';
