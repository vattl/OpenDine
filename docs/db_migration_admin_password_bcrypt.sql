-- 管理员密码 BCrypt 迁移所需：BCrypt 字符串约 60 字符，历史库 t_admin.password 常为 varchar(22) 会报错 Data too long。
-- 在目标库执行一次后重启应用即可。

ALTER TABLE `t_admin`
  MODIFY COLUMN `password` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL DEFAULT NULL COMMENT '密码（BCrypt 或历史明文）';
