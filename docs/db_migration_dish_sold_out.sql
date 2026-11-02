-- t_dish：已售罄标记（0=否，1=是）；C 端菜单与 onsale 一并过滤
ALTER TABLE `t_dish`
  ADD COLUMN `sold_out` tinyint NOT NULL DEFAULT 0 COMMENT '是否已售罄：0-否 1-是' AFTER `onsale`;
