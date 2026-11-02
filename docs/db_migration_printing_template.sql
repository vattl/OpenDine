-- ============================================================
-- 打印模板配置表（可视化小票模板设计器 C004）
-- 幂等：可重复执行。已有数据零影响。
-- ============================================================

CREATE TABLE IF NOT EXISTS `t_printing_template` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '模板 ID',
  `shop_id` int NOT NULL DEFAULT 0 COMMENT '门店 ID（0 表示总部系统内置通用模板，>0 为门店自定义模板）',
  `template_code` varchar(64) NOT NULL COMMENT '模板唯一标识编码',
  `template_name` varchar(128) NOT NULL COMMENT '模板名称（如：默认前台结账单、精简后厨单）',
  `scenario` varchar(32) NOT NULL COMMENT '适用场景：ORDER/KITCHEN/SERVE/REFUND/SHIFT/LABEL/TEST',
  `paper_size` varchar(16) NOT NULL DEFAULT '58mm' COMMENT '纸张规格：58mm / 80mm',
  `is_system` tinyint NOT NULL DEFAULT 0 COMMENT '是否系统内置模板：1 是（只读/支持克隆），0 否（自定义）',
  `is_default` tinyint NOT NULL DEFAULT 0 COMMENT '是否场景默认模板：1 是，0 否',
  `template_json` longtext NOT NULL COMMENT '模板排版设计 JSON 配置（包含 blocks 列表、样式属性及字段开关）',
  `version` int NOT NULL DEFAULT 1 COMMENT '乐观锁版本号',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_shop_template_code` (`shop_id`, `template_code`),
  KEY `idx_shop_scenario` (`shop_id`, `scenario`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='打印小票排版模板配置表';

-- 注册模板管理权限与接口映射
INSERT IGNORE INTO t_api_permission (`method`, `path_pattern`, `permission_code`) VALUES
('GET',    '/admin/printing/templates',          'printing:view|printing:manage'),
('GET',    '/admin/printing/templates/*',        'printing:view|printing:manage'),
('POST',   '/admin/printing/templates',          'printing:manage'),
('PUT',    '/admin/printing/templates/*',        'printing:manage'),
('DELETE', '/admin/printing/templates/*',        'printing:manage'),
('POST',   '/admin/printing/templates/*/set-default', 'printing:manage');
