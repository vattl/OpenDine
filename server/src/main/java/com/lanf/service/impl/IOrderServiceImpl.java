package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.dto.CategorySalesDTO;
import com.lanf.dto.DishSalesDTO;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.SalesVolume;
import com.lanf.entity.Shop;
import com.lanf.service.IShopService;
import com.lanf.entity.UserActivityInteraction;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Map;


/**
 * 订单主表Service实现类
 */
@Service("orderService")
public class IOrderServiceImpl extends ServiceImpl<OrderMapper,Order> implements IOrderService {

    @Autowired
    private OrderMapper orderMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private IShopService shopService;

    @Override
    public List<Order> list(Map<String, Object> map) {
        return orderMapper.list(map);
    }

    @Override
    public Long getTotal(Map<String, Object> map) {
        return orderMapper.getTotal(map);
    }

    @Override
    public long getTodayOrderCount() {
        return getTodayOrderCount(null);
    }

    @Override
    public long getTodayOrderCount(Integer shopId) {
        return getTodayOrderCount(shopId, null);
    }

    @Override
    public long getTodayOrderCount(Integer shopId, String date) {
        // 实时数据窗口：date 为空 → 当前活动营业班次（settle_time 口径）；非空 → 指定营业班次
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        Date[] win = ShopBusinessWindowResolver.resolveOperationalWindow(shop, date);
        Long n = orderMapper.countByTimeRange(win[0], win[1], shopId);
        return n != null ? n : 0L;
    }

    // 实现缺失的晚间时间段统计方法
    @Override
    public List<SalesVolume> getSalesVolumeByEveningPeriod(String period) {
        return getSalesVolumeByEveningPeriod(period, null, null);
    }

    @Override
    public List<SalesVolume> getSalesVolumeByEveningPeriod(String period, Integer shopId) {
        return getSalesVolumeByEveningPeriod(period, shopId, null);
    }

    @Override
    public List<SalesVolume> getSalesVolumeByEveningPeriod(String period, Integer shopId, String paymentMethod) {
        return getSalesVolumeByEveningPeriod(period, shopId, paymentMethod, null);
    }

    @Override
    public List<SalesVolume> getSalesVolumeByEveningPeriod(String period, Integer shopId, String paymentMethod, String date) {
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        // The mapper's day parameter denotes the settlement boundary D and
        // queries [D-1 settle_time, D settle_time). For a live operational
        // window the boundary is therefore the day after its starting day.
        String settlementDate = date != null && !date.trim().isEmpty()
                ? date.trim()
                : ShopBusinessWindowResolver.operationalBusinessDay(shop, java.time.LocalDateTime.now())
                        .plusDays(1).toString();
        return orderMapper.getSalesVolumeByEveningPeriod(period, shopId, paymentMethod, resolveOpenTime(shopId), resolveSettleTime(shopId), settlementDate);
    }

    @Override
    public List<Map<String, Object>> listRevenueByPaymentMethodCurrentBusinessDay(Integer shopId) {
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        String[] window = ShopBusinessWindowResolver.operationalWindowText(shop);
        return orderMapper.listRevenueByPaymentMethodCurrentBusinessDay(shopId, window[0], window[1]);
    }

    @Override
    public Map<String, Object> aggregateCurrentBusinessDayPaidOrderMetrics(Integer shopId) {
        return aggregateOperationalDayPaidOrderMetrics(shopId, null);
    }

    @Override
    public Map<String, Object> aggregateOperationalDayPaidOrderMetrics(Integer shopId, String operationalDate) {
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        String[] window = ShopBusinessWindowResolver.resolveOperationalWindowText(shop, operationalDate);
        return orderMapper.aggregateCurrentBusinessDayPaidOrderMetrics(shopId, window[0], window[1]);
    }

    @Override
    public Map<String, Object> aggregateSettlementDayPaidOrderMetrics(Integer shopId, String settlementDate) {
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        LocalDate day = ShopBusinessWindowResolver.resolveSettlementDay(
                shop, settlementDate, java.time.LocalDateTime.now());
        String[] window = ShopBusinessWindowResolver.settlementWindowText(shop, day);
        return orderMapper.aggregateCurrentBusinessDayPaidOrderMetrics(shopId, window[0], window[1]);
    }

    @Override
    public int countUnfinishedOrders() {
        return countUnfinishedOrders(null);
    }

    @Override
    public int countUnfinishedOrders(Integer shopId) {
        QueryWrapper<Order> qw = new QueryWrapper<Order>();
        if (shopId != null) {
            qw.eq("shop_id", shopId);
        }
        qw.and(wrapper -> wrapper
                .eq("order_receiving", "rec_order")
                .or()
                .eq("order_receiving", "mis_order")
        );
        return count(qw);
    }

    @Override
    public int countUnfinishedOrdersBefore(Integer shopId, Date anchorTime, Integer anchorOrderId) {
        QueryWrapper<Order> qw = new QueryWrapper<Order>();
        // 仅统计最近 24 小时订单，避免历史单影响实时出餐估算
        Date rangeStart = new Date(System.currentTimeMillis() - 24L * 60L * 60L * 1000L);
        qw.ge("order_time", rangeStart);
        if (shopId != null) {
            qw.eq("shop_id", shopId);
        }
        if (anchorOrderId != null) {
            // 显式排除当前订单，避免任何场景下把自己计入“前面几单”
            qw.ne("id", anchorOrderId);
        }
        qw.and(wrapper -> wrapper
                .eq("order_receiving", "rec_order")
                .or()
                .eq("order_receiving", "mis_order")
        );
        if (anchorTime != null) {
            if (anchorOrderId != null) {
                qw.and(wrapper -> wrapper
                        .lt("order_time", anchorTime)
                        .or(w2 -> w2
                                .eq("order_time", anchorTime)
                                .lt("id", anchorOrderId))
                );
            } else {
                qw.lt("order_time", anchorTime);
            }
        }
        return count(qw);
    }

    @Override
    public List<CategorySalesDTO> statisticsCategorySales(Map<String, Object> params) {
        return orderMapper.statisticsCategorySales(params);
    }

    @Override
    public Map<String, Object> statisticsOrderSummary(Map<String, Object> params) {
        return orderMapper.statisticsOrderSummary(params);
    }

    @Override
    public List<DishSalesDTO> statisticsDishSales(Map<String, Object> params) {
        return orderMapper.statisticsDishSales(params);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Order replaceOrderNo(String oldOrderNo, String newOrderNo) {
        Order order = getOne(new QueryWrapper<Order>().eq("order_no", oldOrderNo));
        if (order == null) return null;
        order.setOrder_no(newOrderNo);
        updateById(order);
        orderDetailService.update(new UpdateWrapper<OrderDetail>().set("Morder_no", newOrderNo).eq("mId", order.getId()));
        userCouponMapper.update(null, new UpdateWrapper<UserCoupon>().set("order_no", newOrderNo).eq("order_no", oldOrderNo));
        return order;
    }


    /** 结算窗口起点：24小时周期起始时间为 settle_time。 */
    private String resolveOpenTime(Integer shopId) {
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        return ShopBusinessWindowResolver.requireSettleTime(shop).toString();
    }
    /** 营业日截止（settle_time）：严格校验门店配置，无默认兜底。 */
    private String resolveSettleTime(Integer shopId) {
        Shop shop = shopId != null ? shopService.getById(shopId) : null;
        return ShopBusinessWindowResolver.requireSettleTime(shop).toString();
    }
}
