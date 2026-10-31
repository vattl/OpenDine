-- 门店公告（连锁）：表 t_announcement + B 端接口权限映射
-- MySQL 8.0+，utf8mb4。在已有库上执行；若表或权限已存在请跳过对应语句。

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `t_announcement` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NULL DEFAULT NULL COMMENT 'NULL=全部门店可见；非空=仅该门店',
  `title` varchar(200) NOT NULL COMMENT '标题',
  `content` mediumtext NOT NULL COMMENT '正文（纯文本或富文本 HTML，由前端约定）',
  `status` tinyint NOT NULL DEFAULT 1 COMMENT '1=启用 0=停用',
  `sort_order` int NOT NULL DEFAULT 0 COMMENT '越小越靠前',
  `start_time` datetime NULL DEFAULT NULL COMMENT '可见开始时间，NULL=不限制',
  `end_time` datetime NULL DEFAULT NULL COMMENT '可见结束时间，NULL=不限制',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ann_shop_status_sort` (`shop_id`, `status`, `sort_order`, `id`),
  KEY `idx_ann_time` (`start_time`, `end_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='门店公告（连锁）';

-- 权限主数据（若已存在则跳过）
INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('announcement:manage', '门店公告管理', 'announcement', 't_announcement 增删改查', 50);

-- B 端接口权限（与 SysInterceptor + DbApiPermissionMapping 一致；可重复执行）
INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES
('GET', '/admin/announcement/list', 'announcement:manage'),
('GET', '/admin/announcement/get', 'announcement:manage'),
('POST', '/admin/announcement/add', 'announcement:manage'),
('POST', '/admin/announcement/update', 'announcement:manage'),
('GET', '/admin/announcement/delete', 'announcement:manage');

-- ---------------------------------------------------------------------------
-- 角色授权（解决「无权限：announcement:manage」）：可重复执行
-- ---------------------------------------------------------------------------
-- 1) 超级管理员角色
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM t_role r
JOIN t_permission p ON p.permission_code = 'announcement:manage'
WHERE r.role_code = 'super_admin';

-- 2) 凡已有「轮播图」权限的角色，一并授予公告（与运营侧能力对齐）
INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT rp.role_id, p_ann.id
FROM t_role_permission rp
JOIN t_permission p_banner ON p_banner.id = rp.permission_id AND p_banner.permission_code = 'banner:manage'
JOIN t_permission p_ann ON p_ann.permission_code = 'announcement:manage';
