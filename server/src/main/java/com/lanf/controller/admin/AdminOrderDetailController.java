package com.lanf.controller.admin;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.audit.diff.DishStockDiffProvider;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.ServiceFeeConfig;
import com.lanf.controller.OrderController;
import com.lanf.entity.Coupon;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.order.OrderDetailQueryHelper;
import com.lanf.service.ICouponService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.ITableService;
import com.lanf.service.impl.OrderDetailRefundService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderCheckoutChangeHelper;
import com.lanf.util.OrderPackagingFeeCalculator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 管理端-订单详情Controller控制器
 */
@RestController
@RequestMapping("/admin/orderDetail")
public class AdminOrderDetailController {

    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private ICouponService couponService;
    @Autowired
    private OrderDetailRefundService orderDetailRefundService;
    @Autowired
    private ITableService tableService;
    @Autowired
    private ServiceFeeConfig serviceFeeConfig;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private com.lanf.kds.service.KdsDetailStatusResolver kdsDetailStatusResolver;
    @Autowired
    private com.lanf.kds.service.KdsOrderEnrichService kdsOrderEnrichService;
    @Autowired(required = false)
    private com.lanf.service.IAdminService adminService;
    private static final Logger log = LoggerFactory.getLogger(OrderController.class);

    /** 优惠券仅限烧烤类目使用的 cid（与 OrderController 一致，重算优惠时按此类目金额） */
    private static final Set<String> BARBECUE_CIDS = new HashSet<>(Arrays.asList(
            "a20250523022119000000933",
            "a20250523022125000000142"
    ));

    /**
     * 根据订单号查询订单详情
     * @param id
     * @return
     */
    @GetMapping("/list")
    public R listByOrderId(Integer id){
        if (id == null) {
            return R.error("订单 id 不能为空");
        }
        Order order = orderService.getById(id);
        if (order == null) {
            return R.error("订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }
        takeoutDeliveryService.enrichOrder(order);
        OrderCheckoutChangeHelper.enrichOrderChangeDisplay(order);
        if (adminService != null) {
            com.lanf.util.AdminNameResolver.enrichOrdersCashierInfo(Collections.singletonList(order), adminService);
        }
        List<OrderDetail> orderDetailList = orderDetailService.list(new QueryWrapper<OrderDetail>().eq("mId", id));
        // 打包费派生：打包/外卖单按有效明细反算（与下单计价规则一致，每满 100 元 1 元、有商品最低 1 元）；堂食为 0
        double goodsSubtotal = 0d;
        for (OrderDetail d : orderDetailList) {
            String lineStatus = d.getLine_status();
            if (lineStatus == null || "normal".equals(lineStatus)) {
                Double totalPrice = d.getTotal_price();
                if (totalPrice != null) {
                    goodsSubtotal += totalPrice;
                }
            }
        }
        String dining = order.getDineInOrTakeOut();
        if ("打包".equals(dining) || "外卖".equals(dining) || "自提".equals(dining)) {
            order.setPackaging_fee(OrderPackagingFeeCalculator.calcYuan(goodsSubtotal));
        } else {
            order.setPackaging_fee(0d);
        }
        Map<String,Object> resultMap=new HashMap<>();
        kdsDetailStatusResolver.enrichDetails(orderDetailList, id);
        kdsOrderEnrichService.enrichOrders(Collections.singletonList(order));
        resultMap.put("list",orderDetailList);
        resultMap.put("order",order);
        return R.ok(resultMap);
    }
    /**
     * 退菜（软删除：line_status=refunded），回退库存并同步 KDS void。
     */
    @PostMapping("/delete_menu")
    @AuditLog(module = "order", action = "admin_refund_dish", target = "#p0['id']", diff = DishStockDiffProvider.class)
    public R deleteMenu(@RequestBody Map<String, Object> body) {
        try {
            if (body == null || body.get("id") == null) {
                return R.error("订单明细 id 不能为空");
            }
            int detailId;
            Object idObj = body.get("id");
            if (idObj instanceof Number) {
                detailId = ((Number) idObj).intValue();
            } else {
                try {
                    detailId = Integer.parseInt(idObj.toString().trim());
                } catch (NumberFormatException e) {
                    return R.error("订单明细 id 格式错误");
                }
            }

            OrderDetail existingDetail = orderDetailService.getById(detailId);
            if (existingDetail == null) {
                return R.error("该订单详情不存在");
            }
            if (OrderDetailLineStatus.isRefunded(existingDetail.getLine_status())) {
                return R.error("该明细已退菜");
            }

            Order order = orderService.getById(existingDetail.getMId());
            if (order == null) {
                return R.error("关联订单不存在");
            }
            R shopErr = assertOrderInCurrentShop(order);
            if (shopErr != null) {
                return shopErr;
            }

            String rawStockAction = body.get("stock_action") != null
                    ? body.get("stock_action").toString()
                    : (body.get("stockAction") != null ? body.get("stockAction").toString() : null);
            com.lanf.order.RefundStockAction stockAction = com.lanf.order.RefundStockAction.from(
                    rawStockAction, com.lanf.order.RefundStockAction.RESTORE);
            String remark = body.get("remark") != null ? body.get("remark").toString() : null;

            orderDetailRefundService.refundFullLine(existingDetail, order, stockAction, "admin", remark);

            return R.ok("退菜成功")
                    .put("totalAmount", order.getSett_amount())
                    .put("discount_amount", order.getDiscount_amount())
                    .put("service_fee", order.getService_fee());
        } catch (IllegalStateException | IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            log.error("退菜失败", e);
            return R.error("退菜失败：" + e.getMessage());
        }
    }

    /**
     * 修改订单明细（菜品）数量。
     * 仅未支付订单可改；修改后按单价重算该明细 total_price，并重算整单 sett_amount、服务费、优惠、桌台金额。
     */
    @PostMapping("/updateQuantity")
    public R updateQuantity(@RequestBody Map<String, Object> body) {
        try {
            if (body == null) {
                return R.error("请求体不能为空");
            }
            Object idObj = body.get("id");
            Object quantityObj = body.get("quantity");
            if (idObj == null) {
                return R.error("订单明细 id 不能为空");
            }
            if (quantityObj == null || (quantityObj instanceof String && ((String) quantityObj).trim().isEmpty())) {
                return R.error("数量不能为空");
            }
            int detailId;
            if (idObj instanceof Number) {
                detailId = ((Number) idObj).intValue();
            } else {
                try {
                    detailId = Integer.parseInt(idObj.toString().trim());
                } catch (NumberFormatException e) {
                    return R.error("订单明细 id 格式错误");
                }
            }
            int newQuantity;
            if (quantityObj instanceof Number) {
                newQuantity = ((Number) quantityObj).intValue();
            } else {
                try {
                    newQuantity = Integer.parseInt(quantityObj.toString().trim());
                } catch (NumberFormatException e) {
                    return R.error("数量必须为整数");
                }
            }
            if (newQuantity < 1) {
                return R.error("数量至少为 1，删除请使用删除明细接口");
            }

            OrderDetail existingDetail = orderDetailService.getById(detailId);
            if (existingDetail == null) {
                return R.error("该订单详情不存在");
            }
            Order order = orderService.getById(existingDetail.getMId());
            if (order == null) {
                return R.error("关联订单不存在");
            }
            R shopErr = assertOrderInCurrentShop(order);
            if (shopErr != null) {
                return shopErr;
            }
            if ("success".equals(order.getTransac_status())) {
                return R.error("订单已支付，不允许修改数量");
            }

            if (OrderDetailLineStatus.isRefunded(existingDetail.getLine_status())) {
                return R.error("该明细已退菜，不可修改数量");
            }

            orderDetailRefundService.changeQuantity(existingDetail, order, newQuantity);

            return R.ok("数量修改成功")
                    .put("totalAmount", order.getSett_amount())
                    .put("discount_amount", order.getDiscount_amount())
                    .put("service_fee", order.getService_fee());
        } catch (IllegalStateException | IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            log.error("修改菜品数量失败", e);
            return R.error("修改菜品数量失败：" + e.getMessage());
        }
    }

    /** 按有效明细重算整单金额、服务费、优惠与桌台待结账。 */
    private void recalcOrderFromActiveDetails(Order order) {
        QueryWrapper<OrderDetail> q = new QueryWrapper<OrderDetail>().eq("mId", order.getId());
        OrderDetailQueryHelper.onlyActive(q);
        List<OrderDetail> activeDetails = orderDetailService.list(q);

        double newSettAmount = 0d;
        for (OrderDetail od : activeDetails) {
            newSettAmount += (od.getTotal_price() != null ? od.getTotal_price() : 0d);
        }
        newSettAmount = Math.round(newSettAmount * 100) / 100.0;
        order.setSett_amount(newSettAmount);

        if (activeDetails.isEmpty()) {
            order.setService_fee(0d);
            order.setDiscount_amount(0d);
        } else {
            double newServiceFee = serviceFeeConfig.isServiceFeeCharged()
                    ? Math.round(newSettAmount * 0.05 * 100) / 100.0
                    : 0d;
            order.setService_fee(newServiceFee);
            double totalBarbecueRaw = 0d;
            for (OrderDetail od : activeDetails) {
                if (od.getCid() != null && BARBECUE_CIDS.contains(od.getCid().trim()) && od.getTotal_price() != null) {
                    totalBarbecueRaw += od.getTotal_price();
                }
            }
            double newDiscount = 0d;
            UserCoupon usedUserCoupon = userCouponMapper.selectOne(
                    new QueryWrapper<UserCoupon>().eq("order_no", order.getOrder_no()).last("LIMIT 1"));
            if (usedUserCoupon != null && usedUserCoupon.getCoupon_id() != null) {
                Coupon coupon = couponService.selectByCouponById(usedUserCoupon.getCoupon_id());
                newDiscount = couponService.calcDiscountAmount(totalBarbecueRaw, coupon);
            }
            order.setDiscount_amount(Math.round(newDiscount * 100) / 100.0);
        }
        orderService.updateById(order);

        if ("堂食".equals(order.getDineInOrTakeOut()) && order.getTable_number() != null) {
            Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
            QueryWrapper<Table> tq = new QueryWrapper<Table>().eq("number", order.getTable_number());
            if (shopId != null) {
                tq.eq("shop_id", shopId);
            }
            Table table = tableService.getOne(tq);
            if (table != null) {
                double orderPrice = (order.getSett_amount() != null ? order.getSett_amount() : 0d)
                        + (order.getService_fee() != null ? order.getService_fee() : 0d);
                double paidAmount = Math.round((orderPrice - (order.getDiscount_amount() != null ? order.getDiscount_amount() : 0d)) * 100) / 100.0;
                table.setAmount(paidAmount);
                tableService.updateById(table);
            }
        }
    }

    /**
     * 更新订单总金额
     *
     * @return
     */
    private double updateOrderAmount(Integer orderId) {
        // 查询该订单的所有有效详情
        List<OrderDetail> details = orderDetailService.list(
                new QueryWrapper<OrderDetail>().eq("mId", orderId)
        );

        // 计算总金额
        double totalAmount = 0.0;
        for (OrderDetail detail : details) {
            // 假设OrderDetail有数量和单价字段
            totalAmount += Double.parseDouble(detail.getQuantity()) * detail.getTotal_price();
        }
        return totalAmount;
//        // 更新订单金额
//        Order order = new Order();
//        order.setId(orderId);
//        order.setSett_amount(totalAmount);
//        orderService.updateById(order);
    }

    private R assertOrderInCurrentShop(Order order) {
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid == null || order == null) {
            return null;
        }
        if (order.getShop_id() != null && !order.getShop_id().equals(sid)) {
            return R.error(4003, "订单不属于当前门店");
        }
        return null;
    }
}
