package com.lanf.payment.success;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.*;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.payment.support.OrderPaymentBridge;
import com.lanf.payment.support.PaymentCouponShopScopeValidator;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.payment.support.PaymentTableScopeUtil;
import com.lanf.service.*;
import com.lanf.util.ShopOrderingOpenHelper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * 支付成功后公共处理（核销券、反积分、桌台、打印、KDS、邀请返利）；自 {@code OrderController} 迁入。
 */
@Component
public class PaymentSuccessHandler {

    private static final Logger log = LoggerFactory.getLogger(PaymentSuccessHandler.class);

    @Lazy
    @Autowired
    private OrderPaymentBridge orderPaymentBridge;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private ICouponService couponService;
    @Autowired
    private IUserService userService;
    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private ITableService tableService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private com.lanf.printing.service.PrintDispatcherService printDispatcherService;
    @Autowired
    private InviteService inviteService;
    @Autowired
    private KdsOrderHook kdsOrderHook;
    @Autowired(required = false)
    private com.lanf.notify.service.UnifiedNotificationService unifiedNotificationService;

    public void setUnifiedNotificationService(com.lanf.notify.service.UnifiedNotificationService unifiedNotificationService) {
        this.unifiedNotificationService = unifiedNotificationService;
    }
    public void run(Order latestOrder, double paidYuan) {
        String orderNo = latestOrder.getOrder_no();
        UserCoupon usedCoupon = userCouponMapper.selectOne(
                new QueryWrapper<UserCoupon>().eq("order_no", orderNo).last("LIMIT 1"));
        if (usedCoupon != null) {
            try {
                Coupon usedCouponTemplate = couponService.selectByCouponById(usedCoupon.getCoupon_id());
                PaymentCouponShopScopeValidator.validate(usedCouponTemplate, latestOrder.getShop_id());
                usedCoupon.setUse_time(new Date());
                usedCoupon.setStatus(1);
                userCouponMapper.updateById(usedCoupon);
                log.info("支付成功，优惠券已核销: order_no={}, user_coupon_id={}", orderNo, usedCoupon.getId());
            } catch (Exception e) {
                log.warn("支付成功但优惠券核销门店校验失败，已跳过核销: order_no={}, user_coupon_id={}, shop_id={}, err={}",
                        orderNo, usedCoupon.getId(), latestOrder.getShop_id(), e.getMessage());
            }
        }
        User orderUser = userService.getUserByOpenid(latestOrder.getOpenid());
        if (orderUser != null && orderUser.getId() != null) {
            int pointsToAdd = (int) Math.round(paidYuan);
            if (pointsToAdd > 0) {
                boolean ok = userService.addPoints(orderUser.getId(), pointsToAdd);
                if (ok) {
                    log.info("消费反积分成功: openid={}, 金额={}, 积分={}", latestOrder.getOpenid(), paidYuan, pointsToAdd);
                } else {
                    log.warn("消费反积分失败: openid={}", latestOrder.getOpenid());
                }
            }
        }
        if (PaymentDiningTypeUtil.isWaimaiType(latestOrder.getDineInOrTakeOut())) {
            takeoutDeliveryService.markPaidIfPresent(latestOrder.getOrder_no());
        }
        Integer paidOrderShopId = resolveOrderOwnedShopIdForPrint(latestOrder);
        // 桌台状态仅对堂食订单更新：打包/外卖单扫描同桌二维码下单时携带相同 table_number，
        // 但桌台实体属于堂食场景，不应被打包单的支付回调清台。
        // Bug 场景：20号桌堂食未结账 → 顾客扫20号桌码下打包单结账 → 原代码把桌台清台，
        // 堂食单仍 unsettled 但桌台已显示"已结账"。
        if ("堂食".equals(latestOrder.getDineInOrTakeOut())) {
            QueryWrapper<Table> tableQw = new QueryWrapper<Table>()
                    .eq("number", latestOrder.getTable_number());
            PaymentTableScopeUtil.appendTableShopScope(tableQw, paidOrderShopId);
            Table table = tableService.getOne(tableQw.last("LIMIT 1 FOR UPDATE"));
            if (table != null) {
                // 查该桌是否还有其他未结账的堂食单；若有则保持占用状态
                List<Order> remaining = orderService.list(new QueryWrapper<Order>()
                        .eq(paidOrderShopId != null, "shop_id", paidOrderShopId)
                        .eq("table_number", latestOrder.getTable_number())
                        .eq("dineInOrTakeOut", "堂食")
                        .eq("transac_status", "unsettled")
                        .orderByAsc("id"));
                if (remaining.isEmpty()) {
                    table.setStatus(2);
                    table.setOut_time(new Date());
                    table.setOrder_no(latestOrder.getOrder_no());
                    tableService.updateById(table);
                    log.info("堂食结账，桌台已清台: table={}, order_no={}", latestOrder.getTable_number(), latestOrder.getOrder_no());
                } else {
                    // 还有未结账堂食单，保持占用状态，更新为最早未结账单
                    table.setStatus(1);
                    table.setOut_time(null);
                    table.setOrder_no(remaining.get(0).getOrder_no());
                    tableService.updateById(table);
                    log.info("堂食结账后仍有 {} 张未结账堂食单，桌台保持占用: table={}", remaining.size(), latestOrder.getTable_number());
                }
            } else {
                log.warn("堂食支付成功后未找到桌台: order_no={}, table_number={}, shop_id={}",
                        latestOrder.getOrder_no(), latestOrder.getTable_number(), paidOrderShopId);
            }
        } else {
            log.debug("非堂食订单支付成功，跳过桌台状态更新: order_no={}, type={}, table_number={}",
                    latestOrder.getOrder_no(), latestOrder.getDineInOrTakeOut(), latestOrder.getTable_number());
        }
        if (shouldAutoAcceptForOrder(latestOrder)
                && PaymentDiningTypeUtil.isPackOrDeliveryType(latestOrder.getDineInOrTakeOut())) {
            orderPaymentBridge.doAutoAcceptAndPrint(latestOrder);
            try {
                kdsOrderHook.afterOrderCommitted(latestOrder, null, KdsOrderHook.Trigger.PAID);
            } catch (Exception ex) {
                log.warn("支付成功后 KDS 推送异常，订单号：{}，{}", latestOrder.getOrder_no(), ex.getMessage());
            }
        } else if (Objects.equals(latestOrder.getDineInOrTakeOut(), "堂食")) {
            printDineInTicket(latestOrder);
        }
        try {
            inviteService.tryGrantInviterBalanceForInviteeFirstPaidOrder(latestOrder, paidYuan);
            if (unifiedNotificationService != null) {
                try {
                    unifiedNotificationService.publishNewOrderPaid(latestOrder, paidYuan);
                } catch (Exception ex) {
                    log.warn("新订单实时消息推送异常（不影响支付主流程）: orderNo={}, err={}",
                            orderNo, ex.getMessage());
                }
            }
        } catch (Exception e) {
            log.warn("邀请首单余额返利处理异常（不影响支付主流程）: orderNo={}, err={}",
                    orderNo, e.getMessage(), e);
        }
    }

    /** 堂食结账小票：加载明细后经统一打印调度中心派发整单结账单（与微信支付回调堂食分支一致；供个人收款/收银结账 AfterCommit 复用） */
    public void printDineInTicket(Order order) {
        if (order == null) {
            return;
        }
        List<OrderDetail> detail = orderDetailService.list(
                new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
        order.setGoods_list(detail);
        int printShopId = resolveOrderOwnedShopIdForPrint(order);
        if (printDispatcherService != null) {
            printDispatcherService.dispatch(printShopId, com.lanf.printing.model.PrintScenario.ORDER,
                    com.lanf.printing.model.PrintContext.ofOrder(order, false));
        }
    }

    private boolean shouldAutoAcceptForOrder(Order order) {
        if (order == null) {
            return false;
        }
        Integer shopId = order.getShop_id() != null ? order.getShop_id() : 1;
        Shop shop = shopService.getById(shopId);
        return ShopOrderingOpenHelper.isOrderingOpen(shop);
    }

    private Integer resolveOrderOwnedShopIdForPrint(Order order) {
        if (order == null || !StringUtils.hasText(order.getOrder_no())) {
            throw new RuntimeException("订单不存在或订单号为空，无法分发门店打印机");
        }
        Order latest = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", order.getOrder_no().trim())
                .orderByDesc("id")
                .last("LIMIT 1"));
        if (latest == null || latest.getShop_id() == null) {
            throw new RuntimeException("订单未绑定门店，无法分发门店打印机");
        }
        return latest.getShop_id();
    }
}
