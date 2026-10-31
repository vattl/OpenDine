package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.support.KdsPushPayloadBuilder;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.delivery.CashierKdsProjectionService;
import com.lanf.kds.support.KdsTicketQuantityUtil;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 出餐屏：按菜品名分批确认传菜（按 done_at 从早到晚扣减）。
 */
@Service
public class KdsExpeditionServeService {

    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private KdsPushService pushService;
    @Autowired
    private KdsServePrintService servePrintService;
    @Autowired
    private KdsFlowBatchService flowBatchService;
    @Autowired
    private CashierKdsProjectionService projectionService;

    @Transactional
    public Map<String, Object> serveByDish(int shopId, String dishName, int quantity, String screenTag) {
        if (!StringUtils.hasText(dishName)) {
            throw new IllegalArgumentException("dish_name 不能为空");
        }
        if (quantity <= 0) {
            throw new IllegalArgumentException("quantity 必须大于 0");
        }
        String targetName = dishName.trim();
        String tagFilter = StringUtils.hasText(screenTag) ? screenTag.trim() : null;

        QueryWrapper<KdsTicket> qw = new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .in("screen_tag", KdsScreenTag.PRODUCTION_GRILL_TAGS)
                .eq("item_status", KdsItemStatus.DONE)
                .eq("archived", 0);
        if (tagFilter != null) {
            qw.eq("screen_tag", tagFilter);
        }
        qw.orderByAsc("done_at").orderByAsc("created_at");
        List<KdsTicket> tickets = ticketMapper.selectList(qw);
        if (tickets == null || tickets.isEmpty()) {
            throw new IllegalArgumentException("该菜品暂无待传菜工单");
        }

        Set<Integer> detailIds = tickets.stream()
                .map(KdsTicket::getDetail_id)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        Map<Integer, OrderDetail> detailMap = detailIds.isEmpty() ? Collections.emptyMap()
                : orderDetailService.listByIds(detailIds).stream()
                .collect(Collectors.toMap(OrderDetail::getId, d -> d, (a, b) -> a));

        List<KdsTicket> matched = new ArrayList<>();
        for (KdsTicket t : tickets) {
            OrderDetail d = detailMap.get(t.getDetail_id());
            if (d == null || !StringUtils.hasText(d.getName())) {
                continue;
            }
            if (!targetName.equals(d.getName().trim())) {
                continue;
            }
            matched.add(t);
        }
        if (matched.isEmpty()) {
            throw new IllegalArgumentException("未找到待传菜的「" + targetName + "」");
        }

        int remainingBefore = sumRemaining(matched, detailMap);
        if (quantity > remainingBefore) {
            throw new IllegalArgumentException("传菜数量不能超过待传 " + remainingBefore
                    + (detailMap.get(matched.get(0).getDetail_id()).getUnit() != null
                    ? detailMap.get(matched.get(0).getDetail_id()).getUnit() : "份"));
        }

        int left = quantity;
        int updatedLines = 0;
        Date now = new Date();
        List<KdsServePrintService.ServeLine> printLines = new ArrayList<>();
        for (KdsTicket t : matched) {
            if (left <= 0) {
                break;
            }
            OrderDetail d = detailMap.get(t.getDetail_id());
            int lineQty = parseQty(d != null ? d.getQuantity() : null);
            flowBatchService.ensureInitialized(t, lineQty);
            int currentServeRem = Math.max(0, KdsTicketQuantityUtil.serveRemaining(t, lineQty));
            if (currentServeRem <= 0) {
                continue;
            }
            int take = Math.min(left, currentServeRem);
            int moved = flowBatchService.advanceServe(shopId, t.getId(), take);
            if (moved <= 0) {
                continue;
            }
            updatedLines++;
            KdsTicket refreshed = ticketMapper.selectById(t.getId());
            if (refreshed != null) {
                t = refreshed;
            }
            int newServed = t.getServed_quantity() != null ? t.getServed_quantity() : 0;
            String toQueue = t.getArchived() != null && t.getArchived() == 1
                    ? KdsWorkflowQueue.DONE : KdsWorkflowQueue.READY_SERVE;

            pushWorkflowQuantity(shopId, t, t.getDetail_id(), lineQty, toQueue);
            publishLineStatus(shopId, t, t.getDetail_id());

            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("detail_id", t.getDetail_id());
            payload.put("dish_name", targetName);
            payload.put("served_quantity", take);
            payload.put("served_total", newServed);
            payload.put("line_quantity", lineQty);
            payload.put("archived", t.getArchived());
            payload.put("screen_tag", t.getScreen_tag());
            if (d != null && d.getMId() != null) {
                Order order = orderService.getById(d.getMId());
                KdsPushPayloadBuilder.enrichOrder(payload, order);
            }
            KdsPushPayloadBuilder.enrichDetail(payload, d);
            pushService.updateOrder(shopId, KdsScreenTag.EXPEDITION, payload);
            pushService.updateOrder(shopId, KdsScreenTag.BOSS_OVERVIEW, payload);
            if (t.getDetail_id() != null && take > 0) {
                printLines.add(new KdsServePrintService.ServeLine(t.getDetail_id(), take, now.getTime()));
            }
            left -= take;
        }
        if (!printLines.isEmpty()) {
            servePrintService.printByDetails(shopId, printLines);
        }

        int remainingAfter = remainingBefore - quantity;
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("dish_name", targetName);
        result.put("screen_tag", tagFilter);
        result.put("requested", quantity);
        result.put("served", quantity);
        result.put("updated_lines", updatedLines);
        result.put("remaining_quantity", remainingAfter);
        return result;
    }

    private static int sumRemaining(List<KdsTicket> tickets, Map<Integer, OrderDetail> detailMap) {
        int sum = 0;
        for (KdsTicket t : tickets) {
            OrderDetail d = detailMap.get(t.getDetail_id());
            int lineQty = parseQty(d != null ? d.getQuantity() : null);
            int served = t.getServed_quantity() != null ? t.getServed_quantity() : 0;
            sum += Math.max(0, lineQty - served);
        }
        return sum;
    }

    private static int parseQty(String quantity) {
        if (!StringUtils.hasText(quantity)) {
            return 1;
        }
        try {
            double d = Double.parseDouble(quantity.trim());
            return Math.max(1, (int) Math.round(d));
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    private void pushWorkflowQuantity(int shopId, KdsTicket ticket, int detailId, int lineQty, String workflowQueue) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("order_id", ticket.getOrder_id());
        payload.put("detail_id", detailId);
        payload.put("prep_quantity", KdsTicketQuantityUtil.prepQuantity(ticket));
        payload.put("cooked_quantity", KdsTicketQuantityUtil.cookedQuantity(ticket, lineQty));
        payload.put("served_quantity", KdsTicketQuantityUtil.servedQuantity(ticket));
        payload.put("prep_remaining", KdsTicketQuantityUtil.prepRemaining(ticket, lineQty));
        payload.put("cook_remaining", KdsTicketQuantityUtil.cookRemaining(ticket, lineQty));
        payload.put("serve_remaining", KdsTicketQuantityUtil.serveRemaining(ticket, lineQty));
        payload.put("workflow_queue", workflowQueue);
        payload.put("archived", ticket.getArchived());
        OrderDetail detail = orderDetailService.getById(detailId);
        Order order = detail != null && detail.getMId() != null ? orderService.getById(detail.getMId()) : null;
        KdsPushPayloadBuilder.enrichOrder(payload, order);
        KdsPushPayloadBuilder.enrichDetail(payload, detail);
        pushService.updateOrder(shopId, KdsScreenTag.WORKFLOW_BOARD, payload);
    }

    private void publishLineStatus(int shopId, KdsTicket ticket, int detailId) {
        if (ticket != null && ticket.getOrder_id() != null) {
            try {
                projectionService.publishLineStatus(shopId, ticket.getOrder_id(),
                        Collections.singletonList(
                                CashierKdsProjectionService.LineStatusDelta.from(ticket, detailId)));
            } catch (Exception ex) {
                // Ignore publish failure in non-blocking fashion
            }
        }
    }
}
