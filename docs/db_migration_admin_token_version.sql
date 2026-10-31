-- 管理员会话撤销版本。修改密码或主动踢下线时递增，旧 JWT 随即失效。
ALTER TABLE `t_admin`
  ADD COLUMN `token_version` INT NOT NULL DEFAULT 0 COMMENT '管理员令牌版本，递增后旧令牌立即失效' AFTER `password`;
