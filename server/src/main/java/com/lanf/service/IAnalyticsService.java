package com.lanf.service;

import java.util.Map;

/**
 * 数据分析模块（营业 / 菜品 / 顾客 / 会员 / 营销）
 */
public interface IAnalyticsService {

    /**
     * 默认时间窗口：以当前日 settle_time（门店配置优先，回退 close_time / 04:00）为结束时刻，
     * 向前推 12 小时为开始时刻，返回 {startTime, endTime}（yyyy-MM-dd HH:mm:ss）。
     * 前端显式传入 startTime/endTime 时以传入为准，不走本方法。
     */
    String[] defaultWindow(Integer shopId);

    Map<String, Object> businessOverview(String startTime, String endTime, Integer shopId);

    Map<String, Object> businessTrend(String startTime, String endTime, Integer shopId, String granularity);

    Map<String, Object> dishAnalysis(String startTime, String endTime, Integer shopId, int limit);

    Map<String, Object> customerAnalysis(String startTime, String endTime, Integer shopId);

    Map<String, Object> memberAnalysis(String startTime, String endTime, Integer shopId);

    Map<String, Object> marketingAnalysis(String startTime, String endTime, Integer shopId);
}
