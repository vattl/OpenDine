-- 外卖与真省钱（ZSQ）对接：增加实际跑腿费用与运力渠道字段
ALTER TABLE `t_takeout_delivery`
    ADD COLUMN `zsq_actual_fee` decimal(10, 2) NULL DEFAULT NULL COMMENT '真省钱实际跑腿费用（元，来自 shopActualCost/discountLastMoney）' AFTER `zsq_liability_fee`,
    ADD COLUMN `zsq_delivery_supplier_name` varchar(64) NULL DEFAULT NULL COMMENT '真省钱实际配送运力渠道（如京东特惠、美团等，来自 deliverySupplierName）' AFTER `zsq_actual_fee`;
