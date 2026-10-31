package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.dto.CategorySalesDTO;
import com.lanf.dto.DishDayActualDTO;
import com.lanf.dto.DishDowDemandStatDTO;
import com.lanf.dto.DishSalesDTO;
import com.lanf.entity.Order;
import com.lanf.entity.SalesVolume;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;
import java.util.Map;


/**
 * 订单主表Mapper接口
 */
public interface OrderMapper extends BaseMapper<Order> {

    /**
     * 根据条件 分页查询
     * @param map
     * @return
     */
    public List<Order> list(Map<String,Object> map);

    /**
     * 根据条件，查询订单总记录数
     * @param map
     * @return
     */
    public Long getTotal(Map<String,Object> map);

    /**
     * 查询指定时间范围内订单数（order_time 在 [startTime, endTime] 闭区间）
     * @param startTime 开始时间
     * @param endTime 结束时间
     * @return 订单条数
     */
    Long countByTimeRange(@Param("startTime") java.util.Date startTime, @Param("endTime") java.util.Date endTime,
                          @Param("shopId") Integer shopId);

    List<SalesVolume> getSalesVolumeByEveningPeriod(@Param("period") String period, @Param("shopId") Integer shopId,
                                                    @Param("payment_method") String payment_method,
                                                    @Param("openTime") String openTime,
                                                    @Param("settleTime") String settleTime,
                                                    @Param("date") String date);

    /**
     * 当前活动营业班次（与 salesvolume period=day 默认口径一致）内，按 {@code t_order.payment_method} 汇总净收入与单量。
     * 金额口径：sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift；订单范围与营业额统计一致。
     * startTime/endTime 为明确的结算窗口边界。
     *
     * @return 每行含 payment_method、revenue、order_count（Map 键与列别名一致）
     */
    List<Map<String, Object>> listRevenueByPaymentMethodCurrentBusinessDay(@Param("shopId") Integer shopId,
                                                                              @Param("startTime") String startTime,
                                                                               @Param("endTime") String endTime);

    /**
     * 当前活动营业班次与 {@link #listRevenueByPaymentMethodCurrentBusinessDay} 同一时间窗内，已结订单一行汇总。
     * 键：{@code business_revenue_net}（实付净额，与单笔公式一致）、{@code total_refund_amount}、{@code total_discount_amount}、
     * {@code pay_channel_wechat/alipay/balance/cash/gift}、{@code paid_order_count}。startTime/endTime 同{@link #listRevenueByPaymentMethodCurrentBusinessDay}。
     */
    Map<String, Object> aggregateCurrentBusinessDayPaidOrderMetrics(@Param("shopId") Integer shopId,
                                                                    @Param("startTime") String startTime,
                                                                               @Param("endTime") String endTime);

    /**
     * 分类销售额统计，与 openapi /admin/order/statisticsCategorySales 一致
     * @param params Map 需包含 startTime、endTime（必填），cidList（可选，分类 id 列表）
     * @return 按 total_sales 降序的 CategorySalesDTO 列表
     */
    List<CategorySalesDTO> statisticsCategorySales(Map<String, Object> params);

    /**
     * 订单级汇总：同一时间范围内单独统计 service_fee、discount_amount、sett_amount
     * @param params 与 statisticsCategorySales 相同（startTime、endTime、cidList）
     * @return 单行 Map，键为 total_service_fee、total_discount_amount、total_sett_amount
     */
    Map<String, Object> statisticsOrderSummary(Map<String, Object> params);

    /**
     * 按时间范围查询各菜品销售额（仅已支付订单）
     * @param params 需包含 startTime、endTime（必填），nameList（可选，限定菜品名称列表）
     * @return 按 total_sales 降序的 DishSalesDTO 列表
     */
    List<DishSalesDTO> statisticsDishSales(Map<String, Object> params);

    /**
     * 历史区间内按 ISO 星期（周一=1…周日=7）与菜品名汇总销量，口径与 statisticsDishSales 一致。
     */
    List<DishDowDemandStatDTO> listDishDowDemandStats(Map<String, Object> params);

    /**
     * 单店自然日内各菜品实际销量（成功单口径与 statisticsDishSales 一致）。
     */
    List<DishDayActualDTO> listDishActualQtyForShopDay(Map<String, Object> params);

    /** 单店自然日内成功订单数 */
    Long countSuccessOrdersForShopDay(Map<String, Object> params);

    /** 单店自然日内订单明细销量合计（所有菜品） */
    Long sumAllDishQtyForShopDay(Map<String, Object> params);

}
