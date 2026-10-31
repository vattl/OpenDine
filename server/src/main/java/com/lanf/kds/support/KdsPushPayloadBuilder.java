package com.lanf.kds.support;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * KDS WebSocket 推送载荷：订单备注、菜品备注与明细摘要。
 */
public final class KdsPushPayloadBuilder {

    private KdsPushPayloadBuilder() {
    }

    /** new_order：订单摘要 + 本批 items（可为空）。 */
    public static Map<String, Object> newOrder(Order order, Integer kdsOrderStatus, List<OrderDetail> items) {
        Map<String, Object> payload = orderHeader(order);
        if (kdsOrderStatus != null) {
            payload.put("kds_order_status", kdsOrderStatus);
        }
        List<Map<String, Object>> itemRows = toItemList(items);
        if (!itemRows.isEmpty()) {
            payload.put("items", itemRows);
        }
        return payload;
    }

    /** update_order / cancel_item：在已有字段上补充订单与明细备注。 */
    public static void enrichOrder(Map<String, Object> payload, Order order) {
        if (payload == null || order == null) {
            return;
        }
        if (!payload.containsKey("order_id") && order.getId() != null) {
            payload.put("order_id", order.getId());
        }
        if (!payload.containsKey("order_no")) {
            payload.put("order_no", order.getOrder_no());
        }
        if (!payload.containsKey("table_number")) {
            payload.put("table_number", order.getTable_number());
        }
        if (!payload.containsKey("dineInOrTakeOut")) {
            payload.put("dineInOrTakeOut", order.getDineInOrTakeOut());
        }
        payload.put("remark", order.getRemark());
    }

    public static void enrichDetail(Map<String, Object> payload, OrderDetail detail) {
        if (payload == null || detail == null) {
            return;
        }
        if (!payload.containsKey("detail_id") && detail.getId() != null) {
            payload.put("detail_id", detail.getId());
        }
        if (!payload.containsKey("dish_id") && detail.getDish_id() != null) {
            payload.put("dish_id", detail.getDish_id());
        }
        if (!payload.containsKey("name")) {
            payload.put("name", detail.getName());
        }
        if (!payload.containsKey("quantity")) {
            payload.put("quantity", detail.getQuantity());
        }
        if (!payload.containsKey("unit")) {
            payload.put("unit", detail.getUnit());
        }
        payload.put("detail_remark", detail.getRemark());
        if (!payload.containsKey("selectedSpicy")) {
            payload.put("selectedSpicy", detail.getSelectedSpicy());
        }
        payload.put("line_type", detail.getLine_type());
        payload.put("combo_id", detail.getCombo_id());
        payload.put("combo_instance_id", detail.getCombo_instance_id());
        payload.put("parent_detail_id", detail.getParent_detail_id());
    }

    /** 划菜/状态变更 update_order。 */
    public static Map<String, Object> itemStatusChange(Order order, OrderDetail detail, int detailId,
                                                     int itemStatus, int kdsOrderStatus,
                                                     Map<String, Object> extra) {
        Map<String, Object> payload = new LinkedHashMap<>();
        enrichOrder(payload, order);
        payload.put("detail_id", detail != null && detail.getId() != null ? detail.getId() : detailId);
        payload.put("item_status", itemStatus);
        payload.put("kds_order_status", kdsOrderStatus);
        enrichDetail(payload, detail);
        if (extra != null && !extra.isEmpty()) {
            payload.putAll(extra);
        }
        return payload;
    }

    public static List<Map<String, Object>> toItemList(List<OrderDetail> items) {
        if (items == null || items.isEmpty()) {
            return Collections.emptyList();
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (OrderDetail d : items) {
            if (d == null || d.getId() == null) {
                continue;
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("detail_id", d.getId());
            row.put("dish_id", d.getDish_id());
            row.put("name", d.getName());
            row.put("quantity", d.getQuantity());
            row.put("unit", d.getUnit());
            row.put("remark", d.getRemark());
            row.put("selectedSpicy", d.getSelectedSpicy());
            row.put("line_type", d.getLine_type());
            row.put("combo_id", d.getCombo_id());
            row.put("combo_instance_id", d.getCombo_instance_id());
            row.put("parent_detail_id", d.getParent_detail_id());
            out.add(row);
        }
        return out;
    }

    private static Map<String, Object> orderHeader(Order order) {
        Map<String, Object> payload = new LinkedHashMap<>();
        enrichOrder(payload, order);
        return payload;
    }
}
