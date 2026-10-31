package com.lanf.service;

import java.util.Map;

/**
 * 结合历史订单（按星期几）、公休日规则与天气的菜品备货量预测；支持落库与按批次读取。
 */
public interface StockPrepForecastService {

    /**
     * @param shopId       门店 ID；可为 null 表示不按门店过滤
     * @param historyDays  回溯天数，null 则用配置默认
     * @param forecastDays 预测天数，null 则用配置默认
     * @param persist      为 true 时写入 t_stock_prep_forecast_* 表并返回 runId
     */
    Map<String, Object> buildForecast(Integer shopId, Integer historyDays, Integer forecastDays, boolean persist);

    /** 当前门店（或 shopId 为 null 时的汇总）最近一次落库的预测；无记录返回 null */
    Map<String, Object> getLatestSavedForecast(Integer shopId);

    /** 按批次主键读取落库结果；若传入 shopId 与批次门店不一致则抛错 */
    Map<String, Object> getSavedForecastByRunId(Long runId, Integer shopId);
}
