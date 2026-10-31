ALTER TABLE `t_access_approval`
    ADD COLUMN `binding_version` int NOT NULL DEFAULT 1
        COMMENT '审批上下文绑定策略版本: 1兼容, 2严格'
        AFTER `token_hash`;
