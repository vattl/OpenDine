package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 菜品明细 KDS 制作状态解析（D011 方案 A：接口层联查，不落主库）。
 *
 * <p>单一事实源为 {@code t_kds_ticket}（KDS 厨显工单，一行=一条 t_order_detail，detail_id 关联）。
 * 对外订单明细接口在返回前按 order_id 批量联查，折叠出每个 detail 的最新工单，
 * 填充到 OrderDetail 的非表字段（kds_item_status / kds_status_text / kds_served_quantity）。
 * 无工单（print_only 门店、未接单、历史遗留）的明细保持 null，前端不展示。</p>
 */
@Component
public class KdsDetailStatusResolver {

    @Autowired
    private KdsTicketMapper ticketMapper;

    /**
     * 按订单批量取 KDS 厨显工单（复用索引 idx_kds_ticket_order），按 detail_id 折叠取最新一条。
     * 同明细因重复加菜可能存在多条工单，created_at 升序遍历、后写覆盖，保留最新。
     *
     * @return detail_id → 最新 KdsTicket；无工单的明细不在 map 中
     */
    public Map<Integer, KdsTicket> resolveByOrderIds(Collection<Integer> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return Collections.emptyMap();
        }
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .in("order_id", orderIds)
                .orderByAsc("created_at"));
        if (tickets == null || tickets.isEmpty()) {
            return Collections.emptyMap();
        }
        Map<Integer, KdsTicket> latest = new HashMap<>();
        for (KdsTicket t : tickets) {
            if (t == null || t.getDetail_id() == null) {
                continue;
            }
            latest.put(t.getDetail_id(), t);
        }
        return latest;
    }

    /** 单订单便捷入口：按 order_id 查一次并填充。 */
    public void enrichDetails(List<OrderDetail> details, Integer orderId) {
        if (details == null || details.isEmpty() || orderId == null) {
            return;
        }
        enrichDetails(details, resolveByOrderIds(Collections.singletonList(orderId)));
    }

    /** 批量填充：ticketByDetail 来自 {@link #resolveByOrderIds}；无工单明细置 null。 */
    public void enrichDetails(List<OrderDetail> details, Map<Integer, KdsTicket> ticketByDetail) {
        if (details == null || ticketByDetail == null) {
            return;
        }
        for (OrderDetail d : details) {
            if (d == null || d.getId() == null) {
                continue;
            }
            KdsTicket t = ticketByDetail.get(d.getId());
            if (t == null) {
                if ("refunded".equalsIgnoreCase(d.getLine_status())) {
                    d.setKds_item_status(KdsItemStatus.VOID);
                    d.setKds_status_text(statusText(KdsItemStatus.VOID));
                    d.setKds_served_quantity(0);
                } else {
                    d.setKds_item_status(null);
                    d.setKds_status_text(null);
                    d.setKds_served_quantity(null);
                }
            } else {
                int lineQty = com.lanf.kds.support.KdsTicketQuantityUtil.lineQuantity(d.getQuantity());
                int served = com.lanf.kds.support.KdsTicketQuantityUtil.servedQuantity(t);
                int status;
                String text;
                if (Integer.valueOf(KdsItemStatus.VOID).equals(t.getItem_status())
                        || "refunded".equalsIgnoreCase(d.getLine_status())) {
                    status = KdsItemStatus.VOID;
                    text = "已退菜";
                } else if ((t.getArchived() != null && t.getArchived() == 1) || (lineQty > 0 && served >= lineQty)) {
                    // 只有进入已完成队列（传菜完成），才叫已完成/已出餐
                    status = KdsItemStatus.DONE;
                    text = "已完成";
                } else if (com.lanf.kds.support.KdsTicketQuantityUtil.serveRemaining(t, lineQty) > 0
                        || (Integer.valueOf(KdsItemStatus.DONE).equals(t.getItem_status()) && served < lineQty)) {
                    // 菜品在待传菜中不属于已出餐，标记为制作中/待传菜
                    status = KdsItemStatus.COOKING;
                    text = "待传菜";
                } else if (Integer.valueOf(KdsItemStatus.COOKING).equals(t.getItem_status())
                        || com.lanf.kds.support.KdsTicketQuantityUtil.cookRemaining(t, lineQty) > 0
                        || com.lanf.kds.support.KdsTicketQuantityUtil.prepQuantity(t) > 0) {
                    status = KdsItemStatus.COOKING;
                    text = "制作中";
                } else {
                    status = KdsItemStatus.PENDING;
                    text = "待制作";
                }
                d.setKds_item_status(status);
                d.setKds_status_text(text);
                d.setKds_served_quantity(served);
            }
        }
    }

    /** 状态码 → 中文文案；未知/null 返回 null。 */
    public static String statusText(Integer status) {
        if (status == null) {
            return null;
        }
        switch (status) {
            case KdsItemStatus.PENDING:
                return "待制作";
            case KdsItemStatus.COOKING:
                return "制作中";
            case KdsItemStatus.DONE:
                return "已完成";
            case KdsItemStatus.VOID:
                return "已退菜";
            default:
                return null;
        }
    }
}
