package com.lanf.service;

import com.lanf.entity.StockPreparePlan;

import java.util.List;
import java.util.Map;

/**
 * 由预测批次 + BOM 生成原材料备货计划（t_stock_prepare_plan）
 */
public interface IStockPreparePlanService {

    Map<String, Object> generateFromForecastRun(Long runId);

    List<StockPreparePlan> listPlans(Integer shopId, String prepareDate, Long runId);

    void updatePlan(Long id, java.math.BigDecimal manualAdjust, java.math.BigDecimal finalQty, Integer status, Integer operatorId, Integer requestShopId, boolean skipAdjustRatioCheck);

    /** 批量更新状态（不修改数量）；单条失败记入 errors，不中断整批 */
    Map<String, Object> updatePlanBatchStatus(List<Long> ids, Integer status, Integer operatorId, Integer requestShopId);
}
