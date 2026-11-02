-- 将菜品表历史字段 quantity 统一置为 0（与可售库存 stock 解耦后的清理/归位）
-- 按需执行；若需保留部分行的 quantity，请先备份或改为带 WHERE 条件更新

UPDATE `t_dish`
SET `quantity` = 0
WHERE `quantity` IS NULL OR `quantity` <> 0;

-- 若需无条件整表归 0（含已是 0 的行也执行一次），可改用：
-- UPDATE `t_dish` SET `quantity` = 0;
