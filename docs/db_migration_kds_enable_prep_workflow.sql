-- KDS 待配菜流程开关：在门店配置与档口配置中支持 enable_prep_workflow
-- 执行前需已有 t_kds_shop_config / t_kds_station（db_migration_kds.sql）

ALTER TABLE `t_kds_shop_config`
    ADD COLUMN `enable_prep_workflow` tinyint NOT NULL DEFAULT 1 COMMENT '1启用待配菜环节 0跳过待配菜直接进入待制作' AFTER `combo_merge`;

ALTER TABLE `t_kds_station`
    ADD COLUMN `enable_prep_workflow` tinyint NULL DEFAULT NULL COMMENT '1启用待配菜环节 0跳过待配菜 NULL继承门店配置' AFTER `enabled`;
