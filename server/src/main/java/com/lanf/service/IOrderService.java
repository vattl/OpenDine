package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.dto.CategorySalesDTO;
import com.lanf.dto.DishSalesDTO;
import com.lanf.entity.Order;
import com.lanf.entity.SalesVolume;

import java.util.Date;
import java.util.List;
import java.util.Map;


/**
 * 订单主表Service接口
 */
public interface
IOrderService extends IService<Order> {

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
     * 查询当天订单数（按 order_time 所在日期为当天）
     */
    long getTodayOrderCount();

    /**
     * 按营业日窗口统计订单数；{@code shopId} 非空时仅统计该门店。
     */
    long getTodayOrderCount(Integer shopId);

    /**
     * 按营业日窗口统计订单数；{@code date}（yyyy-MM-dd，营业日开台日）为空 → 当前营业日（settle_time 口径）；
     * 非空 → 指定营业日窗口。
     */
    long getTodayOrderCount(Integer shopId, String date);

    /**
     * 按晚间特殊时间段（18:00-次日02:00）统计销售额
     * @param period 时间周期
     * @return 统计结果列表
     */
    List<SalesVolume> getSalesVolumeByEveningPeriod(String period);

    /**
     * 同上；{@code shopId} 非空时仅统计该门店订单。
     */
    List<SalesVolume> getSalesVolumeByEveningPeriod(String period, Integer shopId);

    /**
     * 同上；{@code paymentMethod} 非空时仅统计 {@code t_order.payment_method} 与之相等的订单。
     */
    List<SalesVolume> getSalesVolumeByEveningPeriod(String period, Integer shopId, String paymentMethod);

    /**
     * 营业额统计；period=day 且 date 为空时实时统计当前活动营业班次。
     * {@code date}（yyyy-MM-dd，历史结算日）非空时按 {@code [date-1天 settle_time, date settle_time)} 查询。
     */
    List<SalesVolume> getSalesVolumeByEveningPeriod(String period, Integer shopId, String paymentMethod, String date);

    /**
     * 当前营业日按支付方式汇总净收入（与 {@link #getSalesVolumeByEveningPeriod} day 口径、门店过滤一致）。
     */
    List<Map<String, Object>> listRevenueByPaymentMethodCurrentBusinessDay(Integer shopId);

    /**
     * 当前营业日已结订单汇总：营业收入（实付净额）、退款与优惠合计、各支付渠道列（{@code pay_amount_*}）实收、已结单量。
     */
    Map<String, Object> aggregateCurrentBusinessDayPaidOrderMetrics(Integer shopId);

    /**
     * 指定营业班次起始日的实时已结订单汇总；{@code operationalDate} 为空时取当前活动营业班次。
     */
    Map<String, Object> aggregateOperationalDayPaidOrderMetrics(Integer shopId, String operationalDate);

    /**
     * 指定结算日的已结订单汇总；{@code settlementDate} 格式为 yyyy-MM-dd。
     */
    Map<String, Object> aggregateSettlementDayPaidOrderMetrics(Integer shopId, String settlementDate);

    /**
     * 有效订单数（与 {@link #countUnfinishedOrders(Integer)} 在 shopId 为 null 时等价，兼容旧调用）。
     * 规则：仅统计 order_receiving in (rec_order, mis_order)。
     */
    int countUnfinishedOrders();

    /**
     * 有效订单数；{@code shopId} 非空时仅统计该门店。
     * 规则：仅统计 order_receiving in (rec_order, mis_order)。
     * 说明：order_receiving == off_order 视为完成订单，不计入有效订单。
     */
    int countUnfinishedOrders(Integer shopId);

    /**
     * 当前订单之前的有效订单数（用于出餐时间估算）。
     * 规则：先按门店过滤，再按 order_receiving in (rec_order, mis_order) 过滤，
     * 最后仅统计当前锚点之前的订单（不包含当前及之后的订单）。
     *
     * @param shopId 门店 ID（可空）
     * @param anchorTime 当前订单时间锚点；为空时不做时间截断
     * @param anchorOrderId 当前订单 ID（可空）；与 anchorTime 同时提供时用于同秒内稳定排序
     */
    int countUnfinishedOrdersBefore(Integer shopId, Date anchorTime, Integer anchorOrderId);

    /**
     * 分类销售额统计（与 openapi GET /admin/order/statisticsCategorySales 一致）
     * @param params 需包含 startTime、endTime（必填），cidList（可选）
     * @return 按 total_sales 降序的 CategorySalesDTO 列表
     */
    List<CategorySalesDTO> statisticsCategorySales(Map<String, Object> params);

    /**
     * 订单级汇总：单独统计 service_fee、discount_amount、sett_amount（与 statisticsCategorySales 同一筛选条件）
     * @param params 同 statisticsCategorySales
     * @return 单行 Map：total_service_fee、total_discount_amount、total_sett_amount
     */
    Map<String, Object> statisticsOrderSummary(Map<String, Object> params);

    /**
     * 按时间范围查询各菜品销售额（仅已支付订单）
     * @param params 需包含 startTime、endTime（必填），nameList（可选）
     * @return 按 total_sales 降序的 DishSalesDTO 列表
     */
    List<DishSalesDTO> statisticsDishSales(Map<String, Object> params);

    /**
     * 换新订单号：将订单及关联的明细、优惠券中的订单号统一更新为 newOrderNo，便于前端用新订单号访问。
     * @param oldOrderNo 原订单号
     * @param newOrderNo 新订单号
     * @return 被更新的订单（含 id），若订单不存在返回 null
     */
    Order replaceOrderNo(String oldOrderNo, String newOrderNo);

}
