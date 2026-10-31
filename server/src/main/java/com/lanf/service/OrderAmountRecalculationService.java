package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.entity.Coupon;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Table;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.order.OrderDetailQueryHelper;
import com.lanf.util.OrderPackagingFeeCalculator;
import com.lanf.util.OrderNetRevenue;
import com.lanf.payment.service.WechatJsapiPaymentService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Recalculates order and table amounts from active detail lines. */
@Service
public class OrderAmountRecalculationService {

    private static final Set<String> BARBECUE_CIDS = new HashSet<>(Arrays.asList(
            "a20250523022119000000933", "a20250523022125000000142"));

    @Autowired private IOrderDetailService orderDetailService;
    @Autowired private IOrderService orderService;
    @Autowired private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired private ITableService tableService;
    @Autowired private ServiceFeeConfig serviceFeeConfig;
    @Autowired private UserCouponMapper userCouponMapper;
    @Autowired private ICouponService couponService;
    @Autowired private WechatJsapiPaymentService wechatJsapiPaymentService;

    @Transactional(rollbackFor = Exception.class)
    public Order recalcFromActiveDetails(Order order) {
        if (order == null || order.getId() == null) {
            throw new IllegalArgumentException("订单不存在");
        }
        order = wechatJsapiPaymentService.prepareForAmountMutation(order);
        QueryWrapper<OrderDetail> query = new QueryWrapper<OrderDetail>().eq("mId", order.getId());
        OrderDetailQueryHelper.onlyActive(query);
        List<OrderDetail> details = orderDetailService.list(query);

        double goodsSubtotal = 0d;
        double barbecueSubtotal = 0d;
        for (OrderDetail detail : details) {
            double lineTotal = nz(detail.getTotal_price());
            goodsSubtotal += lineTotal;
            if (detail.getCid() != null && BARBECUE_CIDS.contains(detail.getCid().trim())) {
                barbecueSubtotal += lineTotal;
            }
        }
        double settAmount = resolveSettAmount(order, round(goodsSubtotal), resolveDeliveryFee(order));
        order.setSett_amount(settAmount);
        order.setService_fee(details.isEmpty() ? 0d : calcServiceFee(settAmount));
        order.setDiscount_amount(details.isEmpty() ? 0d : calcCouponDiscount(order, round(barbecueSubtotal)));
        if (!orderService.updateById(order)) {
            throw new IllegalStateException("订单金额更新失败");
        }
        syncTableAmount(order);
        return order;
    }

    private double resolveSettAmount(Order order, double goodsSubtotal, double deliveryFee) {
        if (goodsSubtotal <= 0d) return 0d;
        if ("外卖".equals(trim(order.getDineInOrTakeOut()))) {
            return OrderPackagingFeeCalculator.resolveSettForWaimai(goodsSubtotal, null, deliveryFee);
        }
        if ("打包".equals(trim(order.getDineInOrTakeOut()))) {
            return OrderPackagingFeeCalculator.resolveSettForTakeOut(goodsSubtotal, null);
        }
        return OrderPackagingFeeCalculator.resolveSettForDineIn(goodsSubtotal, null);
    }

    private double resolveDeliveryFee(Order order) {
        if (!"外卖".equals(trim(order.getDineInOrTakeOut()))) return 0d;
        TakeoutDelivery delivery = takeoutDeliveryService.getByOrderId(order.getId());
        if (delivery != null && delivery.getDelivery_fee() != null) return round(delivery.getDelivery_fee().doubleValue());
        return round(nz(order.getDelivery_fee()));
    }

    private double calcServiceFee(double amount) {
        return serviceFeeConfig.isServiceFeeCharged() ? round(amount * 0.05d) : 0d;
    }

    private double calcCouponDiscount(Order order, double barbecueSubtotal) {
        UserCoupon used = userCouponMapper.selectOne(new QueryWrapper<UserCoupon>()
                .eq("order_no", order.getOrder_no()).last("LIMIT 1"));
        if (used == null || used.getCoupon_id() == null) return 0d;
        Coupon coupon = couponService.selectByCouponById(used.getCoupon_id());
        return round(couponService.calcDiscountAmount(barbecueSubtotal, coupon));
    }

    private void syncTableAmount(Order order) {
        if (!"堂食".equals(trim(order.getDineInOrTakeOut())) || !StringUtils.hasText(order.getTable_number())) return;
        QueryWrapper<Table> query = new QueryWrapper<Table>().eq("number", order.getTable_number());
        if (order.getShop_id() != null) query.eq("shop_id", order.getShop_id());
        Table table = tableService.getOne(query);
        if (table == null) return;
        List<Order> unsettled = orderService.list(new QueryWrapper<Order>()
                .eq("table_number", order.getTable_number())
                .eq("transac_status", "unsettled")
                .eq(order.getShop_id() != null, "shop_id", order.getShop_id()));
        double tableAmount = 0d;
        for (Order item : unsettled) {
            tableAmount += OrderNetRevenue.netRevenueYuan(item);
        }
        table.setAmount(round(Math.max(0d, tableAmount)));
        if (!tableService.updateById(table)) throw new IllegalStateException("桌台金额更新失败");
    }

    private static String trim(String value) { return value == null ? null : value.trim(); }
    private static double nz(Double value) { return value == null ? 0d : value; }
    private static double round(double value) {
        return BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_UP).doubleValue();
    }
}
