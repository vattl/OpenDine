package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderLog;
import com.lanf.entity.R;
import com.lanf.service.IAdminService;
import com.lanf.service.IOrderLogService;
import com.lanf.service.IOrderService;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.*;

/**
 * 订单操作日志（谁点的、谁改的、谁结的）
 */
@RestController
@RequestMapping("/admin/order")
public class AdminOrderLogController {

    @Autowired
    private IOrderLogService orderLogService;
    @Autowired
    private IOrderService orderService;
    @Autowired(required = false)
    private IAdminService adminService;
    @Autowired
    private HttpServletRequest httpServletRequest;

    @GetMapping("/log/{orderId}")
    public R logByOrderId(@PathVariable Integer orderId) {
        Order order = orderService.getById(orderId);
        if (order == null) {
            return R.error("订单不存在");
        }
        R shopErr = assertOrderInCurrentShop(order);
        if (shopErr != null) {
            return shopErr;
        }
        List<OrderLog> list = orderLogService.list(new QueryWrapper<OrderLog>()
                .eq("order_no", order.getOrder_no()).orderByAsc("created_at"));
        if (list != null && !list.isEmpty() && adminService != null) {
            Set<Integer> adminIds = new HashSet<>();
            for (OrderLog ol : list) {
                if (ol != null && ol.getOperator_id() != null) {
                    try {
                        adminIds.add(Integer.parseInt(ol.getOperator_id().trim()));
                    } catch (NumberFormatException ignored) {}
                }
            }
            Map<Integer, String> names = AdminNameResolver.resolveDisplayNames(adminIds, adminService);
            for (OrderLog ol : list) {
                if (ol != null && ol.getOperator_id() != null) {
                    try {
                        Integer aid = Integer.parseInt(ol.getOperator_id().trim());
                        ol.setOperator_name(names.get(aid));
                    } catch (NumberFormatException ignored) {}
                }
            }
        }
        return R.ok().put("list", list);
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
