package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 等叫：明细 order_rece 为空/mis_order 视为等叫，起菜后写 rec_order。
 */
@Service
public class KdsWorkflowHoldService {

    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired(required = false)
    private IOrderService orderService;
    @Autowired(required = false)
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsPushService pushService;

    @Transactional
    public Map<String, Object> hold(int shopId, int detailId) {
        OrderDetail detail = requireDetail(shopId, detailId);
        if ("refunded".equalsIgnoreCase(detail.getLine_status()) || "refunded".equalsIgnoreCase(detail.getOrder_rece())) {
            throw new IllegalArgumentException("已退菜品无法设为等叫");
        }
        if (ticketMapper != null) {
            List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>().eq("detail_id", detailId));
            if (tickets != null && !tickets.isEmpty()) {
                boolean allServed = true;
                int lineQty = 1;
                try {
                    if (detail.getQuantity() != null) {
                        lineQty = Integer.parseInt(detail.getQuantity().trim());
                    }
                } catch (Exception ignored) {}
                for (KdsTicket t : tickets) {
                    if (t.getItem_status() != null && t.getItem_status() == 2) {
                        continue;
                    }
                    Integer served = t.getServed_quantity();
                    if (served != null && served >= lineQty) {
                        continue;
                    }
                    allServed = false;
                    break;
                }
                if (allServed) {
                    throw new IllegalArgumentException("菜品已制作完成/已出餐，无法设为等叫");
                }
            }
        }
        detail.setOrder_rece("mis_order");
        orderDetailService.updateById(detail);
        pushDishHoldFlags(shopId, detailId, detail, 1);
        Map<String, Object> result = new HashMap<>();
        result.put("detail_id", detailId);
        result.put("hold_flag", 1);
        result.put("order_rece", detail.getOrder_rece());
        return result;
    }

    @Transactional
    public Map<String, Object> release(int shopId, int detailId) {
        OrderDetail detail = requireDetail(shopId, detailId);
        detail.setOrder_rece("rec_order");
        orderDetailService.updateById(detail);
        pushDishHoldFlags(shopId, detailId, detail, 0);
        Map<String, Object> result = new HashMap<>();
        result.put("detail_id", detailId);
        result.put("hold_flag", 0);
        result.put("order_rece", detail.getOrder_rece());
        return result;
    }

    public static boolean isHold(OrderDetail detail) {
        if (detail == null) {
            return false;
        }
        String r = detail.getOrder_rece();
        return r == null || r.trim().isEmpty() || "mis_order".equals(r.trim());
    }

    private OrderDetail requireDetail(int shopId, int detailId) {
        OrderDetail detail = orderDetailService.getById(detailId);
        if (detail == null) {
            throw new IllegalArgumentException("明细不存在");
        }
        if (orderService != null && detail.getMId() != null) {
            Order order = orderService.getById(detail.getMId());
            if (order == null) {
                throw new IllegalArgumentException("订单不存在");
            }
            if (order.getShop_id() != null && order.getShop_id() != shopId && !(shopId == 1 && order.getShop_id() == null)) {
                throw new IllegalArgumentException("无权操作其他门店的订单明细");
            }
        }
        return detail;
    }

    private void pushDishHoldFlags(int shopId, int detailId, OrderDetail detail, int holdFlag) {
        Map<String, Object> ticketRow = new LinkedHashMap<>();
        ticketRow.put("detail_id", detailId);
        ticketRow.put("order_id", detail != null ? detail.getMId() : null);
        ticketRow.put("hold_flag", holdFlag);
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("detail_id", detailId);
        payload.put("order_id", detail != null ? detail.getMId() : null);
        payload.put("hold_flag", holdFlag);
        payload.put("tickets", Collections.singletonList(ticketRow));
        pushService.dishFlagsChanged(shopId, payload);
    }
}
