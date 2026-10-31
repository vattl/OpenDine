package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.service.KdsOrderHook;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.order.OrderDetailQuantityParser;
import com.lanf.order.OrderDetailQueryHelper;
import com.lanf.order.RefundStockAction;
import com.lanf.payment.service.WechatJsapiPaymentService;
import com.lanf.service.IDishShopStockService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.OrderAmountRecalculationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.Collections;
import java.util.List;

/**
 * 退菜：标记 line_status、按指定策略处理库存（回退/损耗/估清）、同步 KDS void。
 */
@Service
public class OrderDetailRefundService {

    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IDishShopStockService dishShopStockService;
    @Autowired
    private KdsOrderHook kdsOrderHook;
    @Autowired
    private OrderAmountRecalculationService orderAmountRecalculationService;
    @Autowired
    private WechatJsapiPaymentService wechatJsapiPaymentService;
    @Autowired
    private com.lanf.marketing.mapper.FirstOrderRedemptionMapper firstOrderRedemptionMapper;

    /**
     * 整行退菜（默认回退库存）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void refundFullLine(OrderDetail detail, Order order) {
        refundFullLine(detail, order, RefundStockAction.RESTORE, null, null);
    }

    /**
     * 整行退菜（支持指定库存动作：RESTORE, NO_RESTORE, OUT_OF_STOCK）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void refundFullLine(OrderDetail detail, Order order, RefundStockAction stockAction, String operator, String remark) {
        order = wechatJsapiPaymentService.prepareForAmountMutation(order);
        assertRefundable(detail, order);
        int currentQty = OrderDetailQuantityParser.parsePositive(detail.getQuantity());
        dishShopStockService.handleRefundStock(detail, order.getShop_id(), currentQty, stockAction, operator, remark);
        detail.setRefunded_quantity(nz(detail.getRefunded_quantity()) + currentQty);
        markRefunded(detail);
        voidKds(order, detail.getId());

        // 若退的是套餐头行，级联将该套餐实例下的所有子菜一同退菜并作废 KDS
        if ("combo_header".equalsIgnoreCase(detail.getLine_type())
                && StringUtils.hasText(detail.getCombo_instance_id())
                && order != null && order.getId() != null) {
            List<OrderDetail> components = orderDetailService.list(new QueryWrapper<OrderDetail>()
                    .eq("mId", order.getId())
                    .eq("combo_instance_id", detail.getCombo_instance_id())
                    .eq("line_type", "combo_component"));
            for (OrderDetail comp : components) {
                if (comp != null && OrderDetailQueryHelper.isActiveLine(comp)) {
                    int compQty = OrderDetailQuantityParser.parsePositive(comp.getQuantity());
                    dishShopStockService.handleRefundStock(comp, order.getShop_id(), compQty, stockAction, operator, remark);
                    comp.setRefunded_quantity(nz(comp.getRefunded_quantity()) + compQty);
                    markRefunded(comp);
                    voidKds(order, comp.getId());
                }
            }
        }

        orderAmountRecalculationService.recalcFromActiveDetails(order);
        restoreFirstOrderEligibilityIfFullyRefunded(order);
    }

    /**
     * 首单资格恢复（系统设置协调文档 §5）：整单明细全部退完时，把该订单的 USED 首单核销
     * 记录恢复为 RESTORED（reason=full_refund）。幂等（仅命中 USED 行）；
     * 营销表缺失等异常静默忽略，绝不阻断退款主流程。
     */
    private void restoreFirstOrderEligibilityIfFullyRefunded(Order order) {
        try {
            if (order == null || order.getId() == null || order.getShop_id() == null) {
                return;
            }
            List<OrderDetail> details = orderDetailService.list(
                    new QueryWrapper<OrderDetail>().eq("mId", order.getId()));
            if (details.isEmpty()) {
                return;
            }
            boolean allRefunded = details.stream().allMatch(d ->
                    OrderDetailLineStatus.REFUNDED.equals(d.getLine_status()));
            if (!allRefunded) {
                return;
            }
            com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<com.lanf.marketing.entity.FirstOrderRedemption> uw =
                    new com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper<>();
            uw.eq("order_id", order.getId()).eq("status", "USED")
                    .set("status", "RESTORED")
                    .set("restored_reason", "full_refund")
                    .set("restored_at", java.time.LocalDateTime.now());
            firstOrderRedemptionMapper.update(null, uw);
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(OrderDetailRefundService.class)
                    .warn("[first-order] 全额退款资格恢复失败（不影响退款）: {}", e.getMessage());
        }
    }

    /**
     * 部分退菜（默认回退库存）：减少数量并回退对应库存；若退完则等同整行退菜。
     */
    @Transactional(rollbackFor = Exception.class)
    public void refundPartial(OrderDetail detail, Order order, int refundQty) {
        refundPartial(detail, order, refundQty, RefundStockAction.RESTORE, null, null);
    }

    /**
     * 部分退菜（支持指定库存动作：RESTORE, NO_RESTORE, OUT_OF_STOCK）。
     */
    @Transactional(rollbackFor = Exception.class)
    public void refundPartial(OrderDetail detail, Order order, int refundQty, RefundStockAction stockAction, String operator, String remark) {
        if (refundQty <= 0) {
            throw new IllegalArgumentException("退菜数量须大于 0");
        }
        int currentQty = OrderDetailQuantityParser.parsePositive(detail.getQuantity());
        if (refundQty >= currentQty) {
            refundFullLine(detail, order, stockAction, operator, remark);
            return;
        }
        order = wechatJsapiPaymentService.prepareForAmountMutation(order);
        assertRefundable(detail, order);
        dishShopStockService.handleRefundStock(detail, order.getShop_id(), refundQty, stockAction, operator, remark);
        int remain = currentQty - refundQty;
        double unitPrice = detail.getTotal_price() != null ? detail.getTotal_price() / currentQty : 0d;
        detail.setQuantity(String.valueOf(remain));
        detail.setRefunded_quantity(nz(detail.getRefunded_quantity()) + refundQty);
        detail.setTotal_price(Math.round(unitPrice * remain * 100) / 100.0);
        orderDetailService.updateById(detail);
        adjustKdsAfterPartialRefund(order, detail.getId());
        orderAmountRecalculationService.recalcFromActiveDetails(order);
    }

    /**
     * 改数量：增扣库存与 validate 对称。
     */
    @Transactional(rollbackFor = Exception.class)
    public void changeQuantity(OrderDetail detail, Order order, int newQuantity) {
        if (newQuantity < 1) {
            throw new IllegalArgumentException("数量至少为 1，整行退菜请使用退菜接口");
        }
        int oldQty = OrderDetailQuantityParser.parsePositive(detail.getQuantity());
        if (newQuantity == oldQty) {
            return;
        }
        order = wechatJsapiPaymentService.prepareForAmountMutation(order);
        assertRefundable(detail, order);
        if (newQuantity > oldQty) {
            int delta = newQuantity - oldQty;
            OrderDetail probe = cloneForStock(detail, String.valueOf(delta));
            dishShopStockService.validateCanDeduct(Collections.singletonList(probe), order.getShop_id());
            dishShopStockService.deductQuantity(detail, order.getShop_id(), delta);
        } else {
            dishShopStockService.restoreQuantity(detail, order.getShop_id(), oldQty - newQuantity);
        }
        double unitPrice = detail.getTotal_price() != null ? detail.getTotal_price() / oldQty : 0d;
        detail.setQuantity(String.valueOf(newQuantity));
        detail.setTotal_price(Math.round(unitPrice * newQuantity * 100) / 100.0);
        orderDetailService.updateById(detail);
        kdsOrderHook.afterDetailQuantityReduced(order.getShop_id(), detail.getId());
        orderAmountRecalculationService.recalcFromActiveDetails(order);
    }

    private static OrderDetail cloneForStock(OrderDetail src, String quantity) {
        OrderDetail p = new OrderDetail();
        p.setName(src.getName());
        p.setQuantity(quantity);
        p.setLine_type(src.getLine_type());
        p.setLine_status(src.getLine_status());
        return p;
    }

    private void markRefunded(OrderDetail detail) {
        detail.setLine_status(OrderDetailLineStatus.REFUNDED);
        detail.setOrder_rece(OrderDetailLineStatus.REFUNDED);
        orderDetailService.updateById(detail);
    }

    private void voidKds(Order order, Integer detailId) {
        if (order == null || order.getShop_id() == null || detailId == null) {
            return;
        }
        kdsOrderHook.afterRefundDetails(order.getShop_id(), Collections.singletonList(detailId));
    }

    private void adjustKdsAfterPartialRefund(Order order, Integer detailId) {
        if (order == null || order.getShop_id() == null || detailId == null) {
            return;
        }
        kdsOrderHook.afterDetailQuantityReduced(order.getShop_id(), detailId);
    }

    private static void assertRefundable(OrderDetail detail, Order order) {
        if (detail == null) {
            throw new IllegalArgumentException("明细不存在");
        }
        if (order == null) {
            throw new IllegalArgumentException("订单不存在");
        }
        if (OrderDetailLineStatus.isRefunded(detail.getLine_status())) {
            throw new IllegalStateException("该明细已退菜");
        }
        if (!OrderDetailQueryHelper.isActiveLine(detail)) {
            throw new IllegalStateException("该明细不可退菜");
        }
        if ("success".equals(order.getTransac_status())) {
            throw new IllegalStateException("订单已支付，请走退款流程后再退菜");
        }
    }

    private static int nz(Integer value) {
        return value != null ? value : 0;
    }
}
