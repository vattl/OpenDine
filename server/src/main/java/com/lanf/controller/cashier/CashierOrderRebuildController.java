package com.lanf.controller.cashier;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.order.OrderDetailLineStatus;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.util.AdminShopRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Read-only cloud order snapshot used to rebuild cashier-local KDS data. */
@RestController
@RequestMapping("/cashier/orders")
public class CashierOrderRebuildController {

    private final IOrderService orderService;
    private final IOrderDetailService orderDetailService;

    public CashierOrderRebuildController(IOrderService orderService,
                                         IOrderDetailService orderDetailService) {
        this.orderService = orderService;
        this.orderDetailService = orderDetailService;
    }

    @GetMapping("/{orderId}/details")
    public R details(@PathVariable Integer orderId, HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) return R.error(4001, "缺少门店上下文");
        if (orderId == null || orderId <= 0) return R.error(400, "orderId 必须大于 0");
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("id", orderId).eq("shop_id", shopId).last("LIMIT 1"));
        if (order == null) return R.error(404, "订单不存在或不属于当前门店");

        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>()
                .eq("mId", orderId).orderByAsc("id"));
        List<Map<String, Object>> lines = new ArrayList<>();
        for (OrderDetail detail : details) lines.add(line(detail));
        return R.ok().put("order", order(order)).put("lines", lines);
    }

    private static Map<String, Object> order(Order order) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", order.getId());
        out.put("order_no", order.getOrder_no());
        out.put("shop_id", order.getShop_id());
        out.put("table_number", order.getTable_number());
        out.put("fulfillment_type", fulfillmentType(order.getDineInOrTakeOut()));
        out.put("dining_type_label", order.getDineInOrTakeOut());
        out.put("remark", order.getRemark());
        out.put("number_of_diners", parseInt(order.getNumber_of_diners()));
        out.put("created_at_ms", order.getOrder_time() != null ? order.getOrder_time().getTime() : null);
        out.put("transaction_status", order.getTransac_status());
        out.put("acceptance_status", order.getOrder_receiving());
        return out;
    }

    private static Map<String, Object> line(OrderDetail detail) {
        int remaining = parseInt(detail.getQuantity());
        int refunded = detail.getRefunded_quantity() != null ? detail.getRefunded_quantity() : 0;
        if (OrderDetailLineStatus.isRefunded(detail.getLine_status()) && refunded == 0) {
            refunded = remaining;
        }
        boolean fullyRefunded = OrderDetailLineStatus.isRefunded(detail.getLine_status());
        int ordered = fullyRefunded ? Math.max(remaining, refunded) : remaining + refunded;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("detail_id", detail.getId());
        out.put("dish_id", detail.getDish_id());
        out.put("dish_name", detail.getName());
        out.put("specification", detail.getSelectedSpicy());
        out.put("unit", detail.getUnit());
        out.put("quantity", ordered);
        out.put("refunded_quantity", refunded);
        out.put("remaining_quantity", fullyRefunded ? 0 : remaining);
        out.put("line_status", detail.getLine_status() != null
                ? detail.getLine_status() : OrderDetailLineStatus.NORMAL);
        out.put("client_line_id", detail.getClient_line_id());
        out.put("line_type", detail.getLine_type());
        out.put("combo_id", detail.getCombo_id());
        out.put("combo_instance_id", detail.getCombo_instance_id());
        out.put("parent_detail_id", detail.getParent_detail_id());
        out.put("remark", detail.getRemark());
        return out;
    }

    private static String fulfillmentType(String label) {
        if ("堂食".equals(label)) return "dine_in";
        if ("外卖".equals(label)) return "delivery";
        return "pickup";
    }

    private static int parseInt(String value) {
        try { return Math.max(0, Integer.parseInt(value)); }
        catch (Exception ignored) { return 0; }
    }
}
