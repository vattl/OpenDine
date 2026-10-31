package com.lanf.payment.settlement;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.payment.service.PaymentNinefoldService;
import com.lanf.payment.service.WechatMerchantRoutingService;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.BeanUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.Date;
import static com.lanf.util.UserWalletSplitUtil.decimal;
import static com.lanf.util.UserWalletSplitUtil.roundYuan;
import java.util.List;

/**
 * 支付前结算（券、夜间九折、写 discount_amount）；自 {@code OrderController} 迁入，语义不变。
 */
@Service
public class PaymentSettlementService {

    private static final Logger log = LoggerFactory.getLogger(PaymentSettlementService.class);
    private static final double ORDER_LINE_PRICE_EPS = 0.02;

    @Lazy
    @Autowired
    private OrderPaymentBridge orderPaymentBridge;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private PaymentNinefoldService paymentNinefoldService;
    @Autowired
    private WechatMerchantRoutingService merchantRoutingService;

    /** 校验券并填充应付上下文；失败时 {@code R.code != 0} */
    public R fillPayableAmountContext(Order order, Long couponId, String openidForCoupon, PayableAmountContext ctx) {
        OrderDTO orderDTO = new OrderDTO();
        BeanUtils.copyProperties(order, orderDTO);
        if (couponId != null && couponId > 0L) {
            orderDTO.setCoupon_id(couponId);
        }
        if (StringUtils.hasText(order.getOpenid())) {
            orderDTO.setOpenid(order.getOpenid().trim());
        } else if (StringUtils.hasText(openidForCoupon)) {
            orderDTO.setOpenid(openidForCoupon.trim());
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        orderDTO.setGoods_list(details);
        if (details != null && !details.isEmpty()) {
            ctx.goodsItems = new java.util.ArrayList<>();
            for (OrderDetail d : details) {
                Long gid = d.getDish_id() != null ? d.getDish_id().longValue() : null;
                String gname = d.getName();
                Long cid = null;
                if (d.getCid() != null) {
                    try { cid = Long.parseLong(d.getCid().trim()); } catch (NumberFormatException ignored) {}
                }
                java.math.BigDecimal price = d.getTotal_price() != null ? java.math.BigDecimal.valueOf(d.getTotal_price()) : java.math.BigDecimal.ZERO;
                Integer qty = 1;
                if (d.getQuantity() != null) {
                    try { qty = Integer.parseInt(d.getQuantity().trim()); } catch (NumberFormatException ignored) {}
                }
                ctx.goodsItems.add(new com.lanf.payment.routing.PaymentRoutingContext.RoutingGoodsItem(gid, gname, cid, price, qty));
            }
        }
        try {
            orderPaymentBridge.validateCoupon(orderDTO, false);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        ctx.merchantId = orderDTO.getMerchantId();
        double orderSett = orderDTO.getSett_amount() != null ? orderDTO.getSett_amount() : 0d;
        double orderSvcFee = orderDTO.getService_fee() != null ? orderDTO.getService_fee() : 0d;
        ctx.orderOriginalYuan = decimal(orderSett).add(decimal(orderSvcFee)).doubleValue();
        ctx.couponDiscount = orderDTO.getDiscount_amount() != null ? orderDTO.getDiscount_amount() : 0d;
        ctx.basePaidYuan = roundYuan(decimal(ctx.orderOriginalYuan).subtract(decimal(ctx.couponDiscount)));
        if (ctx.basePaidYuan <= 0) {
            return R.error("订单实付金额异常，无法支付");
        }
        ctx.hasPersistedPositiveDiscount = orderHasPositiveDiscount(order);
        ctx.usesCouponForSettlement = orderUsesCouponForSettlement(order, ctx.couponDiscount);
        ctx.nineFoldTimeRef = order.getOrder_time() != null ? order.getOrder_time() : new Date();
        if (order.getOrder_time() == null) {
            log.warn("settleOrderPayableAmounts 九折时间窗: orderTime 为空，回退为当前时刻 orderNo={}", order.getOrder_no());
        }
        ctx.dineInOrTakeOut = order.getDineInOrTakeOut();
        return R.ok();
    }

    /**
     * 与 getPrepayId 一致：校验券、写回订单 discount_amount，并返回应付金额（元）与商户号。
     *
     * @param allowNineFold 是否允许叠加夜间九折（余额支付须传 false）
     */
    public R settle(Order order, Long couponId, String openidForCoupon, boolean allowNineFold) {
        PayableAmountContext ctx = new PayableAmountContext();
        R prep = fillPayableAmountContext(order, couponId, openidForCoupon, ctx);
        Object codeObj = prep.get("code");
        if (codeObj != null && !Integer.valueOf(0).equals(codeObj)) {
            return prep;
        }
        int ninefoldShopId = PaymentNinefoldService.resolveOrderShopId(order);
        PaymentNinefoldService.ResolvedNinefold ninefold = paymentNinefoldService.resolve(ninefoldShopId);
        boolean nineFoldTime = ninefold.isTimeWindowActive(ctx.nineFoldTimeRef);
        boolean nineFoldEligibleDining = ninefold.isEligibleDiningType(ctx.dineInOrTakeOut);
        boolean applyNineFold = allowNineFold && ninefold.qualifiesForNineFold(
                ctx.usesCouponForSettlement, ctx.nineFoldTimeRef, ctx.basePaidYuan, ctx.dineInOrTakeOut);
        double wxPayYuan;
        double totalDiscountYuan;
        if (ctx.hasPersistedPositiveDiscount) {
            double persistedDisc = order.getDiscount_amount() != null ? order.getDiscount_amount() : 0d;
            double payRate = ninefold.payRate;
            if (!allowNineFold && isPersistedDiscountLikelyNineFold(
                    ctx.orderOriginalYuan, ctx.basePaidYuan, persistedDisc, payRate)) {
                wxPayYuan = ctx.basePaidYuan;
                totalDiscountYuan = roundYuan(decimal(ctx.couponDiscount));
            } else {
                wxPayYuan = roundYuan(decimal(ctx.orderOriginalYuan).subtract(decimal(persistedDisc)));
                totalDiscountYuan = roundYuan(decimal(persistedDisc));
            }
        } else if (applyNineFold) {
            wxPayYuan = roundYuan(decimal(ctx.basePaidYuan).multiply(decimal(ninefold.payRate)));
            totalDiscountYuan = roundYuan(decimal(ctx.orderOriginalYuan).subtract(decimal(wxPayYuan)));
        } else {
            wxPayYuan = ctx.basePaidYuan;
            totalDiscountYuan = roundYuan(decimal(ctx.couponDiscount));
        }
        if (wxPayYuan <= 0) {
            return R.error("折后实付金额异常，无法支付");
        }
        order.setDiscount_amount(totalDiscountYuan);
        com.lanf.payment.routing.PaymentRoutingContext routingCtx =
                new com.lanf.payment.routing.PaymentRoutingContext(ninefoldShopId, wxPayYuan, ctx.dineInOrTakeOut, ctx.merchantId);
        routingCtx.orderTime = ctx.nineFoldTimeRef;
        if (ctx.goodsItems != null) {
            routingCtx.goodsItems = ctx.goodsItems;
        }
        String routedMerchantKey = merchantRoutingService.route(routingCtx);
        order.setMerchantId(routedMerchantKey);
        orderService.updateById(order);
        log.info("settleOrderPayableAmounts: orderNo={} ninefoldShopId={} allowNineFold={} nineFoldEnabled={} nineFoldTime={} nineFoldEligibleDining={} usesCoupon={} persistedDisc={} applyNineFold={} payRate={} eligibleTypes={} dineType={} originalYuan={} couponDisc={} basePaidYuan={} wxPayYuan={} totalDiscYuan={}",
                order.getOrder_no(), ninefoldShopId, allowNineFold, ninefold.enabled, nineFoldTime, nineFoldEligibleDining,
                ctx.usesCouponForSettlement, ctx.hasPersistedPositiveDiscount, applyNineFold,
                ninefold.payRate, ninefold.eligibleDiningTypes,
                ctx.dineInOrTakeOut, ctx.orderOriginalYuan, ctx.couponDiscount, ctx.basePaidYuan, wxPayYuan, totalDiscountYuan);
        return R.ok().put("paidYuan", wxPayYuan).put("merchantId", routedMerchantKey);
    }

    static boolean orderHasPositiveDiscount(Order order) {
        return order != null && order.getDiscount_amount() != null && order.getDiscount_amount() > 0d;
    }

    static boolean orderUsesCouponForSettlement(Order order, double couponDiscountAfterValidate) {
        return orderHasPositiveDiscount(order)
                || (couponDiscountAfterValidate > 0d && !Double.isNaN(couponDiscountAfterValidate));
    }

    static boolean isPersistedDiscountLikelyNineFold(double orderOriginalYuan, double basePaidYuan,
                                                     double persistedDiscountYuan, double payRate) {
        if (persistedDiscountYuan <= 0d || basePaidYuan <= 0d) {
            return false;
        }
        double expectedDisc = roundYuan(decimal(orderOriginalYuan).subtract(decimal(basePaidYuan).multiply(decimal(payRate))));
        return Math.abs(persistedDiscountYuan - expectedDisc) <= ORDER_LINE_PRICE_EPS;
    }
}
