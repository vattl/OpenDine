package com.lanf.mapper;

import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

/**
 * 数据分析聚合查询（营业 / 菜品 / 顾客 / 营销）
 */
public interface AnalyticsMapper {

    Map<String, Object> selectBusinessCore(@Param("startTime") String startTime,
                                             @Param("endTime") String endTime,
                                             @Param("shopId") Integer shopId);

    Long selectTableCount(@Param("shopId") Integer shopId);

    List<Map<String, Object>> selectTimeSlotRevenue(@Param("startTime") String startTime,
                                                     @Param("endTime") String endTime,
                                                     @Param("shopId") Integer shopId,
                                                     @Param("openTime") String openTime,
                                                     @Param("settleTime") String settleTime);

    /**
     * 分时段（营业日锚点）：墙钟四段固定分档 [16,22)、[22,24)∪[0,4)、[4,10)、[10,16) 汇总；
     * 该分档是固定墙钟产品定义，与门店营业日窗口（open_time 起点 / settle_time 截止）解耦，不随配置变化。
     */
    List<Map<String, Object>> selectTimeSlotRevenueBusinessAnchor(@Param("startTime") String startTime,
                                                                  @Param("endTime") String endTime,
                                                                  @Param("shopId") Integer shopId,
                                                                  @Param("openTime") String openTime,
                                                                  @Param("settleTime") String settleTime);

    List<Map<String, Object>> selectPaymentChannelMix(@Param("startTime") String startTime,
                                                       @Param("endTime") String endTime,
                                                       @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectBusinessTrend(@Param("startTime") String startTime,
                                                  @Param("endTime") String endTime,
                                                  @Param("shopId") Integer shopId,
                                                  @Param("granularity") String granularity);

    /**
     * 与 {@link #selectBusinessTrend} 相同订单范围，按营业日标签（16:00 为界）分桶。
     */
    List<Map<String, Object>> selectBusinessTrendByBusinessDate(@Param("startTime") String startTime,
                                                                 @Param("endTime") String endTime,
                                                                 @Param("shopId") Integer shopId,
                                                                 @Param("granularity") String granularity,
                                                                    @Param("openTime") String openTime,
                                                                    @Param("settleTime") String settleTime);

    Long selectDistinctBusinessDayCount(@Param("startTime") String startTime,
                                        @Param("endTime") String endTime,
                                        @Param("shopId") Integer shopId,
                                                @Param("openTime") String openTime,
                                                @Param("settleTime") String settleTime);

    List<Map<String, Object>> selectDishSalesAgg(@Param("startTime") String startTime,
                                                  @Param("endTime") String endTime,
                                                  @Param("shopId") Integer shopId);

    Map<String, Object> selectDishComboRatio(@Param("startTime") String startTime,
                                             @Param("endTime") String endTime,
                                             @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectNewDishSalesTrend(@Param("startTime") String startTime,
                                                       @Param("endTime") String endTime,
                                                       @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectNewDishSalesTrendByBusinessDate(@Param("startTime") String startTime,
                                                                    @Param("endTime") String endTime,
                                                                    @Param("shopId") Integer shopId,
                                                                    @Param("openTime") String openTime,
                                                                    @Param("settleTime") String settleTime);

    Map<String, Object> selectCustomerNewOld(@Param("startTime") String startTime,
                                             @Param("endTime") String endTime,
                                             @Param("shopId") Integer shopId);

    Map<String, Object> selectCustomerRepurchaseInPeriod(@Param("startTime") String startTime,
                                                          @Param("endTime") String endTime,
                                                          @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectCustomerVisitBuckets(@Param("startTime") String startTime,
                                                         @Param("endTime") String endTime,
                                                         @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectTastePreference(@Param("startTime") String startTime,
                                                     @Param("endTime") String endTime,
                                                     @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectTabooHints(@Param("startTime") String startTime,
                                               @Param("endTime") String endTime,
                                               @Param("shopId") Integer shopId);

    Map<String, Object> selectMemberOrderContribution(@Param("startTime") String startTime,
                                                       @Param("endTime") String endTime,
                                                       @Param("shopId") Integer shopId,
                                                       @Param("openTime") String openTime,
                                                       @Param("settleTime") String settleTime);

    /**
     * 分时段（墙钟小时）：按 HOUR(order_time) 0–23 逐时汇总净额与单量；
     * 口径与 {@link #selectTimeSlotRevenue}（自然钟点四段）一致，含 businessDayFilter 排除关门时段订单。
     */
    List<Map<String, Object>> selectTimeSlotHourly(@Param("startTime") String startTime,
                                                   @Param("endTime") String endTime,
                                                   @Param("shopId") Integer shopId,
                                                   @Param("openTime") String openTime,
                                                   @Param("settleTime") String settleTime);

    /**
     * 分时段（营业日小时）：以门店 open_time（默认 16:00）为营业日起点，(HOUR - openHour + 24) % 24 得 0–23
     * 营业小时桶（键 bd_hour_00…bd_hour_23），0–15 时订单归入前一日营业日尾段；口径与营业锚点四段一致。
     */
    List<Map<String, Object>> selectTimeSlotBusinessHourly(@Param("startTime") String startTime,
                                                           @Param("endTime") String endTime,
                                                           @Param("shopId") Integer shopId,
                                                           @Param("openTime") String openTime,
                                                           @Param("settleTime") String settleTime);

    List<Map<String, Object>> selectCouponTemplateStats(@Param("startTime") String startTime,
                                                          @Param("endTime") String endTime,
                                                          @Param("shopId") Integer shopId);

    List<Map<String, Object>> selectActivityPopupStats(@Param("startTime") String startTime,
                                                         @Param("endTime") String endTime,
                                                         @Param("shopId") Integer shopId);
}
