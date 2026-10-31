package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.util.TakeoutZsqDispatchRecovery;
import com.lanf.entity.Order;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.event.TakeoutOrderAcceptedEvent;
import com.lanf.mapper.TakeoutDeliveryMapper;
import com.lanf.service.IOrderService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.TakeoutDeliveryStatusNotifier;
import com.lanf.util.TakeoutRefundGate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.Collection;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

@Service
public class TakeoutDeliveryServiceImpl extends ServiceImpl<TakeoutDeliveryMapper, TakeoutDelivery> implements ITakeoutDeliveryService {

    @Autowired
    private IOrderService orderService;

    @Autowired
    private ApplicationEventPublisher eventPublisher;

    @Autowired
    private TakeoutDeliveryStatusNotifier deliveryStatusNotifier;

    @Override
    public boolean updateById(TakeoutDelivery entity) {
        if (entity == null) {
            return false;
        }
        TakeoutDelivery before = resolveExisting(entity);
        boolean ok = super.updateById(entity);
        if (ok) {
            TakeoutDelivery after = entity.getId() != null ? getById(entity.getId()) : resolveExisting(entity);
            if (after == null) {
                after = entity;
            }
            deliveryStatusNotifier.notifyIfChanged(before, after);
        }
        return ok;
    }

    @Override
    public void insertForNewOrder(TakeoutDelivery row) {
        if (row == null || row.getOrder_id() == null) {
            return;
        }
        save(row);
        deliveryStatusNotifier.notifyChanged(row);
    }

    @Override
    public void markPaidIfPresent(String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return;
        }
        TakeoutDelivery before = getOne(new QueryWrapper<TakeoutDelivery>()
                .eq("order_no", orderNo.trim()).last("LIMIT 1"));
        if (update(new UpdateWrapper<TakeoutDelivery>()
                .set("dispatch_status", "paid")
                .eq("order_no", orderNo.trim())
                .eq("dispatch_status", "submitted"))) {
            notifyAfterOrderNo(orderNo.trim(), before);
        }
    }

    @Override
    public void markAcceptedIfPresent(String orderNo, Integer orderId) {
        if (!StringUtils.hasText(orderNo) && orderId == null) {
            return;
        }
        TakeoutDelivery before = resolveByOrderNoOrId(orderNo, orderId);
        UpdateWrapper<TakeoutDelivery> uw = new UpdateWrapper<TakeoutDelivery>()
                .set("dispatch_status", "accepted")
                .in("dispatch_status", "paid", "submitted");
        if (StringUtils.hasText(orderNo)) {
            uw.eq("order_no", orderNo.trim());
        } else {
            uw.eq("order_id", orderId);
        }
        if (update(uw)) {
            notifyAfterOrderNoOrId(orderNo, orderId, before);
            publishAcceptedIfWaimai(orderId, orderNo);
            return;
        }
        if (StringUtils.hasText(orderNo) && orderId != null) {
            TakeoutDelivery before2 = getByOrderId(orderId);
            if (update(new UpdateWrapper<TakeoutDelivery>()
                    .set("dispatch_status", "accepted")
                    .in("dispatch_status", "paid", "submitted")
                    .eq("order_id", orderId))) {
                notifyAfterOrderNoOrId(orderNo, orderId, before2);
                publishAcceptedIfWaimai(orderId, orderNo);
            }
        }
    }

    private void publishAcceptedIfWaimai(Integer orderId, String orderNo) {
        Integer oid = orderId;
        if (oid == null && StringUtils.hasText(orderNo)) {
            Order o = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", orderNo.trim()).last("LIMIT 1"));
            if (o != null) {
                oid = o.getId();
            }
        }
        if (oid != null) {
            eventPublisher.publishEvent(new TakeoutOrderAcceptedEvent(oid));
        }
    }

    @Override
    public void markCancelledIfPresent(String orderNo) {
        if (!StringUtils.hasText(orderNo)) {
            return;
        }
        TakeoutDelivery before = getOne(new QueryWrapper<TakeoutDelivery>()
                .eq("order_no", orderNo.trim()).last("LIMIT 1"));
        if (update(new UpdateWrapper<TakeoutDelivery>()
                .set("dispatch_status", "cancelled")
                .eq("order_no", orderNo.trim())
                .eq("dispatch_status", "submitted"))) {
            notifyAfterOrderNo(orderNo.trim(), before);
        }
    }

    @Override
    public boolean markDeliveryCancelled(Integer orderId, Integer shopId, String reason) {
        if (orderId == null) {
            return false;
        }
        Order o = orderService.getById(orderId);
        if (o == null || !"外卖".equals(o.getDineInOrTakeOut())) {
            return false;
        }
        if (shopId != null && o.getShop_id() != null && !shopId.equals(o.getShop_id())) {
            return false;
        }
        TakeoutDelivery d = getByOrderId(orderId);
        if (d == null) {
            return false;
        }
        TakeoutZsqDispatchRecovery.finalizeOperatorCancel(d);
        TakeoutZsqDispatchRecovery.appendCancelRemark(d, reason);
        d.setUpdated_at(new java.util.Date());
        return updateById(d);
    }

    @Override
    public boolean updateDispatchStatus(Integer orderId, String newStatus, Integer shopId) {
        if (orderId == null || !StringUtils.hasText(newStatus)) {
            return false;
        }
        Order o = orderService.getById(orderId);
        if (o == null || !"外卖".equals(o.getDineInOrTakeOut())) {
            return false;
        }
        if (shopId != null && o.getShop_id() != null && !shopId.equals(o.getShop_id())) {
            return false;
        }
        TakeoutDelivery d = getByOrderId(orderId);
        if (d == null) {
            return false;
        }
        String normalized = newStatus.trim().toLowerCase();
        d.setDispatch_status(normalized);
        if ("cancelled".equals(normalized)) {
            TakeoutZsqDispatchRecovery.finalizeOperatorCancel(d);
        } else if ("completed".equals(normalized)) {
            if (!"off_order".equals(o.getOrder_receiving())) {
                o.setOrder_receiving("off_order");
                if (o.getOff_time() == null) {
                    o.setOff_time(new Date());
                }
                orderService.updateById(o);
            }
        }
        return updateById(d);
    }

    @Override
    public TakeoutDelivery getByOrderId(Integer orderId) {
        if (orderId == null) {
            return null;
        }
        return getOne(new QueryWrapper<TakeoutDelivery>().eq("order_id", orderId).last("LIMIT 1"));
    }

    @Override
    public IPage<TakeoutDelivery> pageByShop(Integer shopId, int pageNum, int pageSize, String dispatchStatus) {
        return pageByShop(shopId, pageNum, pageSize, dispatchStatus, null, null);
    }

    @Override
    public IPage<TakeoutDelivery> pageByShop(Integer shopId, int pageNum, int pageSize, String dispatchStatus, Date startTime, Date endTime) {
        QueryWrapper<TakeoutDelivery> q = new QueryWrapper<TakeoutDelivery>().orderByDesc("id");
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        if (StringUtils.hasText(dispatchStatus) && !"all".equalsIgnoreCase(dispatchStatus.trim())) {
            q.eq("dispatch_status", dispatchStatus.trim().toLowerCase());
        }
        if (startTime != null) {
            q.ge("created_at", startTime);
        }
        if (endTime != null) {
            q.lt("created_at", endTime);
        }
        IPage<TakeoutDelivery> page = page(new Page<>(pageNum, pageSize), q);
        if (page != null && page.getRecords() != null) {
            for (TakeoutDelivery td : page.getRecords()) {
                if (td != null && td.getActual_delivery_fee() == null) {
                    td.setActual_delivery_fee(td.getZsq_actual_fee());
                }
            }
        }
        return page;
    }

    @Override
    public void enrichOrder(Order order) {
        if (order == null) {
            return;
        }
        if (order.getId() == null) {
            clearTakeoutOnOrder(order);
            return;
        }
        applyTakeoutToOrder(order, getByOrderId(order.getId()));
    }

    @Override
    public void enrichOrders(Collection<Order> orders) {
        if (orders == null || orders.isEmpty()) {
            return;
        }
        List<Integer> ids = orders.stream()
                .map(Order::getId)
                .filter(Objects::nonNull)
                .distinct()
                .collect(Collectors.toList());
        if (ids.isEmpty()) {
            for (Order o : orders) {
                clearTakeoutOnOrder(o);
            }
            return;
        }
        List<TakeoutDelivery> deliveries = list(new QueryWrapper<TakeoutDelivery>().in("order_id", ids));
        Map<Integer, TakeoutDelivery> byOrderId = new HashMap<>();
        for (TakeoutDelivery td : deliveries) {
            if (td.getOrder_id() != null) {
                byOrderId.put(td.getOrder_id(), td);
            }
        }
        for (Order o : orders) {
            applyTakeoutToOrder(o, o.getId() == null ? null : byOrderId.get(o.getId()));
        }
    }

    private static void clearTakeoutOnOrder(Order order) {
        order.setTakeout_delivery_id(null);
        order.setDelivery_fee(null);
        order.setActual_delivery_fee(null);
        order.setTakeout_dispatch_status(null);
    }

    private static void applyTakeoutToOrder(Order order, TakeoutDelivery d) {
        if (d == null) {
            clearTakeoutOnOrder(order);
            return;
        }
        order.setTakeout_delivery_id(d.getId());
        order.setDelivery_fee(d.getDelivery_fee() != null ? d.getDelivery_fee().doubleValue() : 0d);
        order.setActual_delivery_fee(d.getZsq_actual_fee() != null ? d.getZsq_actual_fee().doubleValue() : null);
        order.setTakeout_dispatch_status(d.getDispatch_status());
    }

    @Override
    public String getOrderDeleteBlockReason(TakeoutDelivery delivery) {
        if (delivery == null) {
            return null;
        }
        String ds = normalizeStatus(delivery.getDispatch_status());
        if ("cancelled".equals(ds) || "dispatch_failed".equals(ds)) {
            return null;
        }
        if ("delivering".equals(ds)) {
            return "配送进行中，请先取消配送后再删除订单";
        }
        if ("completed".equals(ds)) {
            return "配送已完成，无法删除订单";
        }
        String zsq = normalizeStatus(delivery.getZsq_dispatch_status());
        if ("pending".equals(zsq) || "dispatched".equals(zsq)) {
            return "配送进行中，请先取消配送后再删除订单";
        }
        if (delivery.getZsq_open_order_id() != null && StringUtils.hasText(delivery.getZsq_phase())) {
            String phase = delivery.getZsq_phase().trim().toUpperCase();
            if ("TO_SHOP".equals(phase) || "TO_USER".equals(phase) || "DELIVERED".equals(phase)) {
                return "配送进行中，请先取消配送后再删除订单";
            }
            if ("WAITING_RIDER".equals(phase) && ("pending".equals(zsq) || "dispatched".equals(zsq))) {
                return "配送进行中，请先取消配送后再删除订单";
            }
        }
        return null;
    }

    @Override
    public void deleteByOrderId(Integer orderId) {
        if (orderId == null) {
            return;
        }
        remove(new QueryWrapper<TakeoutDelivery>().eq("order_id", orderId));
    }

    @Override
    public String getRefundBlockReason(Order order) {
        if (order == null || order.getId() == null) {
            return TakeoutRefundGate.blockReason(order, null);
        }
        return TakeoutRefundGate.blockReason(order, getByOrderId(order.getId()));
    }

    private TakeoutDelivery resolveExisting(TakeoutDelivery entity) {
        if (entity.getId() != null) {
            return getById(entity.getId());
        }
        if (entity.getOrder_id() != null) {
            return getByOrderId(entity.getOrder_id());
        }
        return null;
    }

    private TakeoutDelivery resolveByOrderNoOrId(String orderNo, Integer orderId) {
        if (orderId != null) {
            return getByOrderId(orderId);
        }
        if (StringUtils.hasText(orderNo)) {
            return getOne(new QueryWrapper<TakeoutDelivery>().eq("order_no", orderNo.trim()).last("LIMIT 1"));
        }
        return null;
    }

    private void notifyAfterOrderNo(String orderNo, TakeoutDelivery before) {
        TakeoutDelivery after = getOne(new QueryWrapper<TakeoutDelivery>()
                .eq("order_no", orderNo).last("LIMIT 1"));
        deliveryStatusNotifier.notifyIfChanged(before, after);
    }

    private void notifyAfterOrderNoOrId(String orderNo, Integer orderId, TakeoutDelivery before) {
        TakeoutDelivery after = resolveByOrderNoOrId(orderNo, orderId);
        deliveryStatusNotifier.notifyIfChanged(before, after);
    }

    private static String normalizeStatus(String status) {
        return status == null ? "" : status.trim().toLowerCase();
    }
}
