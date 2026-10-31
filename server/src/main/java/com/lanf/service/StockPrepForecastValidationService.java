package com.lanf.service;

import java.util.Map;

/**
 * 备货预测与实际订单、日结数据对账，产出可用于机器学习训练的结构化样本。
 */
public interface StockPrepForecastValidationService {

    /**
     * 将预测日已过去的自然日与订单实际、日结对账写入预测表（菜品 actual、日汇总、日结字段）。
     *
     * @param force 为 true 时覆盖已校验过的日期
     */
    Map<String, Object> validateRun(Long runId, Integer shopId, boolean force);

    /**
     * 导出单批次的训练样本行（扁平特征 + 标签）；需已执行校验或 actual_quantity 已写入。
     */
    Map<String, Object> exportTrainingRows(Long runId, Integer shopId);
}
