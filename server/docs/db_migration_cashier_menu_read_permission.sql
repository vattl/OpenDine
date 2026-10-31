-- POS cashiers need this read-only menu catalog to open a table and order.
-- Category/dish write endpoints remain restricted to dish:manage.
UPDATE `t_api_permission`
SET `permission_code` = 'dish:manage|cashier:operate'
WHERE `path_pattern` IN ('/admin/category/listAll', '/admin/dish/list');
