package com.lanf.order;

import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.service.IOrderService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

/** Owns the optimistic-concurrency contract for business mutations of an order. */
@Service
public class OrderRevisionService {

    public static final String VERSION_CONFLICT = "ORDER_VERSION_CONFLICT";
    public static final String VERSION_INVALID = "ORDER_VERSION_INVALID";

    @Autowired
    private IOrderService orderService;

    public Integer readExpectedVersion(Map<String, Object> body) {
        if (body == null) {
            return null;
        }
        Object camel = body.get("expectedVersion");
        Object snake = body.get("expected_version");
        if (camel != null && snake != null) {
            Integer left = parseVersion(camel);
            Integer right = parseVersion(snake);
            if (!left.equals(right)) {
                throw invalidVersion();
            }
            return left;
        }
        Object raw = camel != null ? camel : snake;
        return raw == null ? null : parseVersion(raw);
    }

    public int currentRevision(Order order) {
        if (order == null || order.getId() == null) {
            throw new IllegalArgumentException("订单不存在");
        }
        return order.getRevision() != null ? order.getRevision() : 0;
    }

    public int assertExpected(Order order, Integer expectedVersion) {
        int current = currentRevision(order);
        if (expectedVersion != null && expectedVersion < 0) {
            throw invalidVersion();
        }
        if (expectedVersion != null && expectedVersion != current) {
            throw conflict(order);
        }
        return current;
    }

    public int increment(Order order, int currentRevision) {
        UpdateWrapper<Order> update = new UpdateWrapper<Order>()
                .eq("id", order.getId());
        if (currentRevision == 0) {
            update.and(w -> w.eq("revision", 0).or().isNull("revision"));
        } else {
            update.eq("revision", currentRevision);
        }
        update.setSql("revision = COALESCE(revision, 0) + 1");
        if (!orderService.update(null, update)) {
            Order latest = orderService.getById(order.getId());
            throw conflict(latest != null ? latest : order);
        }
        int next = currentRevision + 1;
        order.setRevision(next);
        return next;
    }

    private static Integer parseVersion(Object raw) {
        try {
            int value = new BigDecimal(String.valueOf(raw).trim()).intValueExact();
            if (value < 0) {
                throw invalidVersion();
            }
            return value;
        } catch (ApiException ex) {
            throw ex;
        } catch (Exception ex) {
            throw invalidVersion();
        }
    }

    private static ApiException invalidVersion() {
        return new ApiException(400, VERSION_INVALID, "expectedVersion 必须为非负整数");
    }

    private static ApiException conflict(Order latest) {
        Map<String, Object> data = new LinkedHashMap<>();
        if (latest != null) {
            data.put("orderNo", latest.getOrder_no());
            data.put("revision", latest.getRevision() != null ? latest.getRevision() : 0);
            data.put("transacStatus", latest.getTransac_status());
            data.put("settAmount", latest.getSett_amount());
            data.put("discountAmount", latest.getDiscount_amount());
            data.put("serviceFee", latest.getService_fee());
        }
        return new ApiException(409, VERSION_CONFLICT,
                "订单已被其他终端修改，请刷新后重试", data);
    }
}
