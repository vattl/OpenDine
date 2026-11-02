-- 仅授权：公告权限 announcement:manage（表与 t_api_permission 已执行过时，单独跑本脚本即可）
-- MySQL 8.0+。可重复执行。

SET NAMES utf8mb4;

INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES
('announcement:manage', '门店公告管理', 'announcement', 't_announcement 增删改查', 50);

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM t_role r
JOIN t_permission p ON p.permission_code = 'announcement:manage'
WHERE r.role_code = 'super_admin';

INSERT IGNORE INTO t_role_permission (role_id, permission_id)
SELECT rp.role_id, p_ann.id
FROM t_role_permission rp
JOIN t_permission p_banner ON p_banner.id = rp.permission_id AND p_banner.permission_code = 'banner:manage'
JOIN t_permission p_ann ON p_ann.permission_code = 'announcement:manage';
