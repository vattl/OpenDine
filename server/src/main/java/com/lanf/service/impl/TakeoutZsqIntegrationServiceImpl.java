package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Order;
import com.lanf.entity.Shop;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.entity.UserAddress;
import com.lanf.event.TakeoutOrderAcceptedEvent;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.exception.ZsqPartialDispatchException;
import com.lanf.integration.exception.ZsqRemoteOrderMissingException;
import com.lanf.integration.remote.dto.ZsqCancelResult;
import com.lanf.integration.remote.dto.ZsqCreateOrderResult;
import com.lanf.integration.remote.dto.ZsqDeliveryBillingChannel;
import com.lanf.integration.service.ZsqDeliveryService;
import com.lanf.integration.web.dto.CreateTakeawayDispatchRequest;
import com.lanf.integration.web.dto.CreateTakeawayOrderRequest;
import com.lanf.integration.util.ZsqAddressTextHelper;
import com.lanf.integration.web.dto.ZsqDispatchOptionsRequest;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.integration.web.dto.ZsqTakeawayDispatchResult;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.ITakeoutZsqIntegrationService;
import com.lanf.service.IUserAddressService;
import com.lanf.service.TakeoutDispatchAlertService;
import com.lanf.config.ZsqSystemSettings;
import com.lanf.util.TakeoutZsqDispatchRecovery;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.HttpStatusCodeException;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class TakeoutZsqIntegrationServiceImpl implements ITakeoutZsqIntegrationService {

    private static final Logger log = LoggerFactory.getLogger(TakeoutZsqIntegrationServiceImpl.class);

    private static final Set<String> REDISPATCH_ALLOWED = new HashSet<>(
            Arrays.asList("none", "failed", "rider_cancelled", "cancelled", "order_missing", "completed"));

    private final ITakeoutDeliveryService takeoutDeliveryService;
    private final IOrderService orderService;
    private final IShopTakeoutConfigService shopTakeoutConfigService;
    private final IShopService shopService;
    private final IUserAddressService userAddressService;
    private final ZsqDeliveryService zsqDeliveryService;
    private final ObjectMapper objectMapper;
    private final TakeoutDispatchAlertService takeoutDispatchAlertService;
    private final ZsqSystemSettings zsqSystemSettings;

    public TakeoutZsqIntegrationServiceImpl(ITakeoutDeliveryService takeoutDeliveryService,
                                            IOrderService orderService,
                                            IShopTakeoutConfigService shopTakeoutConfigService,
                                            IShopService shopService,
                                            IUserAddressService userAddressService,
                                            ZsqDeliveryService zsqDeliveryService,
                                            ObjectMapper objectMapper,
                                            TakeoutDispatchAlertService takeoutDispatchAlertService,
                                            ZsqSystemSettings zsqSystemSettings) {
        this.takeoutDeliveryService = takeoutDeliveryService;
        this.orderService = orderService;
        this.shopTakeoutConfigService = shopTakeoutConfigService;
        this.shopService = shopService;
        this.userAddressService = userAddressService;
        this.zsqDeliveryService = zsqDeliveryService;
        this.objectMapper = objectMapper;
        this.takeoutDispatchAlertService = takeoutDispatchAlertService;
        this.zsqSystemSettings = zsqSystemSettings;
    }

    @EventListener
    public void onTakeoutAccepted(TakeoutOrderAcceptedEvent event) {
        if (event == null || event.getOrderId() == null) {
            return;
        }
        tryAutoDispatchAfterAccepted(event.getOrderId());
    }

    @Override
    public void tryAutoDispatchAfterAccepted(Integer orderId) {
        Order order = orderService.getById(orderId);
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            return;
        }
        if (!zsqSystemSettings.isAutoDispatchEnabled(order.getShop_id())) {
            return;
        }
        TakeoutDelivery delivery = takeoutDeliveryService.getByOrderId(orderId);
        if (delivery == null) {
            return;
        }
        if ("dispatched".equals(delivery.getZsq_dispatch_status())
                || "completed".equals(delivery.getZsq_dispatch_status())) {
            return;
        }
        if ("pending".equals(delivery.getZsq_dispatch_status())) {
            return;
        }
        try {
            dispatchToZsq(orderId, false);
        } catch (Exception e) {
            log.warn("真省钱自动发配送失败 orderId={}: {}", orderId, e.getMessage());
        }
    }

    @Override
    public void tryAutoDispatchOnKdsCompleted(Integer orderId) {
        Order order = orderService.getById(orderId);
        if (order == null) {
            return;
        }
        if (!"外卖".equals(order.getDineInOrTakeOut())) {
            log.debug("[kds-auto-dispatch] 订单非外卖订单，跳过自动叫骑手 orderId={}, type={}", orderId, order.getDineInOrTakeOut());
            return;
        }
        TakeoutDelivery delivery = takeoutDeliveryService.getByOrderId(orderId);
        if (delivery == null) {
            log.warn("[kds-auto-dispatch] 外卖订单缺少配送记录，无法叫骑手 orderId={}", orderId);
            return;
        }
        String zsqStatus = normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status());
        String dispatchStatus = normalizeDispatchStatus(delivery.getDispatch_status());
        if ("dispatched".equals(zsqStatus) || "completed".equals(zsqStatus)
                || "delivering".equals(dispatchStatus) || "completed".equals(dispatchStatus)) {
            log.info("[kds-auto-dispatch] 外卖订单已发配送或已在履约中，跳过自动叫骑手 orderId={}, zsqStatus={}, dispatchStatus={}",
                    orderId, zsqStatus, dispatchStatus);
            return;
        }
        if ("pending".equals(zsqStatus)) {
            log.info("[kds-auto-dispatch] 外卖订单正在发起配送中，跳过重复呼叫 orderId={}", orderId);
            return;
        }
        try {
            log.info("[kds-auto-dispatch] KDS 厨显整单出餐完成，自动触发呼叫骑手 orderId={}, shopId={}, orderNo={}",
                    orderId, order.getShop_id(), order.getOrder_no());
            dispatchToZsq(orderId, false);
        } catch (Exception e) {
            log.warn("[kds-auto-dispatch] KDS 整单完成自动叫骑手异常（不阻断KDS出餐） orderId={}: {}", orderId, e.getMessage());
        }
    }

    @Override
    public TakeoutDelivery dispatchToZsq(Integer orderId, boolean forceRedispatch) {
        Order order = requireWaimaiOrder(orderId);
        TakeoutDelivery delivery = requireDelivery(orderId);
        ShopTakeoutConfig cfg = shopTakeoutConfigService.resolveForShop(order.getShop_id());
        String zsqStatus = normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status());
        if (!forceRedispatch) {
            if ("dispatched".equals(zsqStatus) || "completed".equals(zsqStatus)) {
                throw new IllegalStateException("该订单已发配送，如需重发请使用重发接口");
            }
            if ("pending".equals(zsqStatus)) {
                throw new IllegalStateException("配送发起中，请稍后再试");
            }
            if ("cancelled".equals(zsqStatus)
                    || "cancelled".equals(normalizeDispatchStatus(delivery.getDispatch_status()))) {
                throw new IllegalStateException("配送已取消，请使用重发配送（POST /admin/takeout/delivery/zsq/redispatch）");
            }
        } else {
            String dispatchStatus = normalizeDispatchStatus(delivery.getDispatch_status());
            if ("pending".equals(zsqStatus) || "dispatched".equals(zsqStatus)
                    || "delivering".equals(dispatchStatus)) {
                throw new IllegalStateException("当前配送仍在进行中，不能重新叫骑手");
            }
            TakeoutZsqDispatchRecovery.prepareLocalForRedispatch(delivery);
            delivery.setUpdated_at(new Date());
            takeoutDeliveryService.updateById(delivery);
        }

        boolean reuseExistingOpenOrder = shouldDispatchExistingOpenOrder(delivery, forceRedispatch);
        markDispatchPending(delivery);

        try {
            CreateTakeawayDispatchRequest request = buildDispatchRequest(order, delivery, cfg);
            ZsqTakeawayDispatchResult result;
            if (reuseExistingOpenOrder) {
                Long reusedOpenOrderId = delivery.getZsq_open_order_id();
                try {
                    result = zsqDeliveryService.dispatchOpenOrderWithConfig(
                            reusedOpenOrderId, request.getDispatch());
                } catch (RuntimeException reuseError) {
                    if (!isRemoteOrderMissing(reuseError)) {
                        throw reuseError;
                    }
                    log.info("真省钱原订单已不存在，改为重新创单 orderId={} openOrderId={}",
                            orderId, reusedOpenOrderId);
                    clearRemoteOrderIdentity(delivery);
                    result = zsqDeliveryService.createTakeawayAndDispatchWithConfig(request);
                }
            } else {
                result = zsqDeliveryService.createTakeawayAndDispatchWithConfig(request);
            }
            applyDispatchResult(delivery, result);
            delivery.setZsq_dispatch_status("dispatched");
            delivery.setDispatch_status("accepted");
            delivery.setZsq_last_error(null);
            int attempts = delivery.getZsq_dispatch_attempts() != null ? delivery.getZsq_dispatch_attempts() : 0;
            delivery.setZsq_dispatch_attempts(attempts + 1);
            delivery.setUpdated_at(new Date());
            takeoutDeliveryService.updateById(delivery);

            ZsqRiderTrackingResponse tracking = zsqDeliveryService.getRiderTrackingWithConfig(
                    delivery.getZsq_open_order_id());
            normalizeTrackingToSystemCoordinates(delivery, tracking);
            syncTrackingOntoDelivery(delivery, tracking);
            takeoutDeliveryService.updateById(delivery);
            return delivery;
        } catch (ZsqPartialDispatchException e) {
            persistPartialZsqOrder(delivery, e.getCreatedOrder());
            delivery.setZsq_dispatch_status("failed");
            delivery.setZsq_last_error(truncateError(e));
            delivery.setUpdated_at(new Date());
            takeoutDeliveryService.updateById(delivery);
            throw e;
        } catch (Exception e) {
            delivery.setZsq_dispatch_status("failed");
            delivery.setZsq_last_error(truncateError(e));
            delivery.setUpdated_at(new Date());
            takeoutDeliveryService.updateById(delivery);
            if (e instanceof ZsqApiException) {
                throw (ZsqApiException) e;
            }
            throw new ZsqApiException(truncateError(e));
        }
    }

    @Override
    public ZsqCancelResult cancelZsqForOrder(Integer orderId, String reason, boolean strict) {
        Order order = orderService.getById(orderId);
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            ZsqCancelResult skip = new ZsqCancelResult();
            skip.setSuccess(true);
            skip.setMessage("非外卖或无关联");
            return skip;
        }
        TakeoutDelivery delivery = takeoutDeliveryService.getByOrderId(orderId);
        if (delivery == null || delivery.getZsq_open_order_id() == null) {
            ZsqCancelResult skip = new ZsqCancelResult();
            skip.setSuccess(true);
            skip.setMessage("未关联真省钱订单");
            return skip;
        }
        // 管理端会先落本地 cancelled 再调用这里；本地状态不能作为远端已经取消的凭据。
        boolean dispatched = isZsqDispatched(delivery);
        try {
            ZsqCancelResult result = zsqDeliveryService.cancelTakeawayOrderWithConfig(
                    delivery.getZsq_open_order_id(),
                    delivery.getZsq_parent_order_no(),
                    dispatched);
            applyCancelResult(delivery, result, reason);
            takeoutDeliveryService.updateById(delivery);
            return result;
        } catch (Exception e) {
            if (strict) {
                if (e instanceof ZsqApiException) {
                    throw (ZsqApiException) e;
                }
                throw new ZsqApiException(truncateError(e));
            }
            log.warn("真省钱取消失败 orderId={}: {}", orderId, e.getMessage());
            ZsqCancelResult fail = new ZsqCancelResult();
            fail.setSuccess(false);
            fail.setMessage(e.getMessage());
            delivery.setZsq_last_error(truncateError(e));
            if ("cancelled".equals(normalizeDispatchStatus(delivery.getDispatch_status()))) {
                TakeoutZsqDispatchRecovery.finalizeOperatorCancel(delivery);
                TakeoutZsqDispatchRecovery.appendCancelRemark(delivery, reason);
                delivery.setZsq_last_error(truncateError(e));
            }
            takeoutDeliveryService.updateById(delivery);
            return fail;
        }
    }

    private void applyCancelResult(TakeoutDelivery delivery, ZsqCancelResult result, String reason) {
        delivery.setZsq_cancel_prompt(result.getCancelPrompt());
        delivery.setZsq_liability_fee(result.getLiabilityFeeYuan());
        delivery.setZsq_cancel_json(toJson(result.getRawCancel()));
        TakeoutZsqDispatchRecovery.finalizeOperatorCancel(delivery);
        TakeoutZsqDispatchRecovery.appendCancelRemark(delivery, reason);
        delivery.setUpdated_at(new Date());
    }

    private static boolean isZsqDispatched(TakeoutDelivery delivery) {
        String st = normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status());
        return "dispatched".equals(st) || "completed".equals(st) || "rider_cancelled".equals(st)
                || StringUtils.hasText(delivery.getZsq_parent_order_no());
    }

    @Override
    public TakeoutDelivery syncFromZsq(Integer orderId) {
        TakeoutDelivery delivery = requireDelivery(orderId);
        if ("order_missing".equals(normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status()))) {
            throw new ZsqRemoteOrderMissingException(null, null);
        }
        if (delivery.getZsq_open_order_id() == null) {
            throw new IllegalStateException("该外卖单尚未关联真省钱订单");
        }
        ZsqRiderTrackingResponse tracking = fetchTrackingOrMarkRemoteMissing(delivery);
        normalizeTrackingToSystemCoordinates(delivery, tracking);
        syncTrackingFromZsqOntoDelivery(delivery, tracking);
        delivery.setUpdated_at(new Date());
        takeoutDeliveryService.updateById(delivery);
        return delivery;
    }

    private void syncTrackingFromZsqOntoDelivery(TakeoutDelivery delivery) {
        if (delivery.getZsq_open_order_id() == null) {
            return;
        }
        try {
            ZsqRiderTrackingResponse tracking = fetchTrackingOrMarkRemoteMissing(delivery);
            syncTrackingFromZsqOntoDelivery(delivery, tracking);
        } catch (Exception e) {
            log.debug("同步真省钱追踪失败 orderId={}: {}", delivery.getOrder_id(), e.getMessage());
        }
    }

    private void syncTrackingFromZsqOntoDelivery(TakeoutDelivery delivery, ZsqRiderTrackingResponse tracking) {
        syncTrackingOntoDelivery(delivery, tracking);
        attachLocalDispatchStatus(tracking, delivery);
    }

    private static void attachLocalDispatchStatus(ZsqRiderTrackingResponse tracking, TakeoutDelivery delivery) {
        if (tracking == null || delivery == null) {
            return;
        }
        tracking.setDispatchStatus(delivery.getDispatch_status());
        tracking.setZsqDispatchStatus(delivery.getZsq_dispatch_status());
    }

    @Override
    public ZsqRiderTrackingResponse getTrackingForUser(String openid, String orderNo) {
        if (!StringUtils.hasText(openid) || !StringUtils.hasText(orderNo)) {
            throw new IllegalArgumentException("openid 与 order_no 不能为空");
        }
        Order order = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", orderNo.trim())
                .eq("openid", openid.trim())
                .last("LIMIT 1"));
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            throw new IllegalArgumentException("外卖订单不存在");
        }
        return fetchAndPersistTracking(order);
    }

    @Override
    public ZsqRiderTrackingResponse getTrackingForOrder(Integer orderId) {
        if (orderId == null) {
            throw new IllegalArgumentException("orderId 不能为空");
        }
        Order order = orderService.getById(orderId);
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            throw new IllegalArgumentException("外卖订单不存在");
        }
        return fetchAndPersistTracking(order);
    }

    private ZsqRiderTrackingResponse fetchAndPersistTracking(Order order) {
        TakeoutDelivery delivery = takeoutDeliveryService.getByOrderId(order.getId());
        if (delivery != null
                && "order_missing".equals(normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status()))) {
            throw new ZsqRemoteOrderMissingException(null, null);
        }
        if (delivery == null || delivery.getZsq_open_order_id() == null) {
            throw new IllegalStateException("配送信息尚未就绪");
        }
        ZsqRiderTrackingResponse tracking = fetchTrackingOrMarkRemoteMissing(delivery);
        normalizeTrackingToSystemCoordinates(delivery, tracking);
        try {
            List<Object> previousState = trackingPersistenceState(delivery);
            Date previousRiderUpdatedAt = delivery.getZsq_rider_updated_at();
            syncTrackingFromZsqOntoDelivery(delivery, tracking);
            if (!previousState.equals(trackingPersistenceState(delivery))) {
                delivery.setUpdated_at(new Date());
                takeoutDeliveryService.updateById(delivery);
                if ("completed".equals(delivery.getDispatch_status())) {
                    if (order != null && !"off_order".equals(order.getOrder_receiving())) {
                        order.setOrder_receiving("off_order");
                        if (order.getOff_time() == null) {
                            order.setOff_time(new Date());
                        }
                        orderService.updateById(order);
                    }
                }
            } else {
                delivery.setZsq_rider_updated_at(previousRiderUpdatedAt);
            }
        } catch (Exception e) {
            log.debug("同步追踪落库失败 orderId={}: {}", order.getId(), e.getMessage());
        }
        attachLocalDispatchStatus(tracking, delivery);
        return tracking;
    }

    private ZsqRiderTrackingResponse fetchTrackingOrMarkRemoteMissing(TakeoutDelivery delivery) {
        Long openOrderId = delivery.getZsq_open_order_id();
        try {
            return zsqDeliveryService.getRiderTrackingWithConfig(openOrderId);
        } catch (RuntimeException e) {
            if (!isRemoteOrderMissing(e)) {
                throw e;
            }
            markRemoteOrderMissing(delivery, openOrderId);
            throw new ZsqRemoteOrderMissingException(openOrderId, e);
        }
    }

    private void markRemoteOrderMissing(TakeoutDelivery delivery, Long missingOpenOrderId) {
        delivery.setDispatch_status("dispatch_failed");
        delivery.setZsq_dispatch_status("order_missing");
        delivery.setZsq_phase("ORDER_MISSING");
        delivery.setZsq_last_error(ZsqRemoteOrderMissingException.USER_MESSAGE);
        delivery.setZsq_open_order_id(null);
        delivery.setZsq_order_id(null);
        delivery.setZsq_parent_order_no(null);
        delivery.setZsq_shop_number(null);
        delivery.setZsq_rider_name(null);
        delivery.setZsq_rider_phone(null);
        delivery.setZsq_rider_lat(null);
        delivery.setZsq_rider_lng(null);
        delivery.setZsq_rider_updated_at(null);
        delivery.setUpdated_at(new Date());
        takeoutDeliveryService.updateById(delivery);
        try {
            takeoutDispatchAlertService.onRemoteOrderMissing(delivery, missingOpenOrderId);
        } catch (Exception e) {
            log.warn("真省钱订单失效告警发送失败 orderId={}: {}",
                    delivery.getOrder_id(), e.getMessage());
        }
    }

    private static boolean isRemoteOrderMissing(Throwable error) {
        for (Throwable current = error; current != null; current = current.getCause()) {
            if (current instanceof ZsqApiException
                    && ((ZsqApiException) current).getCode() == 404) {
                return true;
            }
            if (current instanceof HttpStatusCodeException
                    && ((HttpStatusCodeException) current).getRawStatusCode() == 404) {
                return true;
            }
            String message = current.getMessage();
            if (message != null) {
                String normalized = message.trim().toLowerCase();
                if (normalized.contains("订单不存在")
                        || normalized.contains("配送单不存在")
                        || normalized.contains("订单已删除")
                        || normalized.contains("order not found")
                        || normalized.contains("order deleted")) {
                    return true;
                }
            }
        }
        return false;
    }

    private static List<Object> trackingPersistenceState(TakeoutDelivery delivery) {
        return Arrays.asList(
                delivery.getDispatch_status(),
                delivery.getZsq_dispatch_status(),
                delivery.getZsq_phase(),
                delivery.getZsq_delivery_send_status(),
                delivery.getZsq_rider_name(),
                delivery.getZsq_rider_phone(),
                comparableDecimal(delivery.getZsq_rider_lat()),
                comparableDecimal(delivery.getZsq_rider_lng()),
                delivery.getZsq_last_error(),
                comparableDecimal(delivery.getZsq_actual_fee()),
                delivery.getZsq_delivery_supplier_name());
    }

    private static BigDecimal comparableDecimal(BigDecimal value) {
        return value != null ? value.stripTrailingZeros() : null;
    }

    private void normalizeTrackingToSystemCoordinates(TakeoutDelivery delivery,
                                                       ZsqRiderTrackingResponse tracking) {
        if (delivery == null || tracking == null) {
            return;
        }
        Order order = delivery.getOrder_id() != null ? orderService.getById(delivery.getOrder_id()) : null;
        Shop shop = order != null && order.getShop_id() != null ? shopService.getById(order.getShop_id()) : null;
        Double shopLat = shop != null && shop.getLatitude() != null ? shop.getLatitude().doubleValue() : null;
        Double shopLng = shop != null && shop.getLongitude() != null ? shop.getLongitude().doubleValue() : null;
        Double userLat = delivery.getLat() != null ? delivery.getLat().doubleValue() : null;
        Double userLng = delivery.getLng() != null ? delivery.getLng().doubleValue() : null;
        zsqDeliveryService.normalizeTrackingToGcj02(
                tracking, shopLat, shopLng, userLat, userLng);
    }

    @Override
    public int syncActiveDeliveries() {
        return syncActiveDeliveriesAfter(0, 20, Long.MAX_VALUE).processed;
    }

    @Override
    public DeliverySyncBatch syncActiveDeliveriesAfter(long afterId, int limit, long deadlineNanos) {
        int batchSize = Math.max(1, Math.min(limit, 100));
        List<TakeoutDelivery> list = takeoutDeliveryService.list(new QueryWrapper<TakeoutDelivery>()
                .isNotNull("zsq_open_order_id")
                .in("zsq_dispatch_status", "dispatched", "pending")
                .in("dispatch_status", "accepted", "delivering", "dispatch_failed")
                .gt("id", Math.max(0, afterId))
                .orderByAsc("id")
                .last("LIMIT " + batchSize));
        int n = 0;
        long lastId = afterId;
        boolean budgetExhausted = false;
        for (TakeoutDelivery d : list) {
            if (System.nanoTime() >= deadlineNanos) { budgetExhausted = true; break; }
            if (d.getId() != null) lastId = d.getId();
            if (!zsqSystemSettings.isTakeoutSyncEnabled(d.getShop_id())) {
                continue;
            }
            try {
                syncFromZsq(d.getOrder_id());
                n++;
            } catch (Exception e) {
                log.warn("真省钱状态同步失败 orderId={}: {}", d.getOrder_id(), e.getMessage());
            }
        }
        return new DeliverySyncBatch(n, lastId, !budgetExhausted && list.size() < batchSize);
    }

    private void markDispatchPending(TakeoutDelivery delivery) {
        TakeoutZsqDispatchRecovery.clearStaleTrackingForNewDispatch(delivery);
        delivery.setZsq_dispatch_status("pending");
        delivery.setZsq_last_error(null);
        delivery.setUpdated_at(new Date());
        takeoutDeliveryService.updateById(delivery);
    }

    /** 已有真省钱 open 订单时只重新询价+发配送；仅远端订单不存在时重新 create。 */
    private static boolean shouldDispatchExistingOpenOrder(TakeoutDelivery delivery, boolean forceRedispatch) {
        if (delivery.getZsq_open_order_id() == null) {
            return false;
        }
        String st = normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status());
        if ("dispatched".equals(st) || "completed".equals(st) || "pending".equals(st)) {
            return false;
        }
        if ("failed".equals(st)) {
            return true;
        }
        if ("none".equals(st) && delivery.getZsq_open_order_id() != null) {
            return true;
        }
        return forceRedispatch && REDISPATCH_ALLOWED.contains(st);
    }

    private void persistPartialZsqOrder(TakeoutDelivery delivery, ZsqCreateOrderResult created) {
        if (created == null) {
            return;
        }
        ZsqTakeawayDispatchResult partial = new ZsqTakeawayDispatchResult();
        partial.setOrder(created);
        applyDispatchResult(delivery, partial);
    }

    private static void clearRemoteOrderIdentity(TakeoutDelivery delivery) {
        delivery.setZsq_open_order_id(null);
        delivery.setZsq_order_id(null);
        delivery.setZsq_shop_number(null);
        delivery.setZsq_parent_order_no(null);
    }

    private CreateTakeawayDispatchRequest buildDispatchRequest(Order order, TakeoutDelivery delivery,
                                                               ShopTakeoutConfig cfg) {
        UserAddress addr = delivery.getUser_address_id() != null
                ? userAddressService.getById(delivery.getUser_address_id()) : null;

        CreateTakeawayOrderRequest orderReq = new CreateTakeawayOrderRequest();
        if (cfg.getZsq_from_address_id() != null) {
            orderReq.setFromAddressId(cfg.getZsq_from_address_id());
        } else {
            Shop shop = order.getShop_id() != null ? shopService.getById(order.getShop_id()) : null;
            if (shop != null && StringUtils.hasText(shop.getName())) {
                orderReq.setFromAddressShopName(shop.getName().trim());
            }
            if (shop != null && shop.getLatitude() != null && shop.getLongitude() != null) {
                orderReq.setFromAddressLatitude(shop.getLatitude().doubleValue());
                orderReq.setFromAddressLongitude(shop.getLongitude().doubleValue());
                orderReq.setFromAddressCoordinateType("gcj02");
            }
        }
        orderReq.setReceiverName(delivery.getReceiver_name());
        orderReq.setReceiverPhone(normalizePhone(delivery.getReceiver_phone()));
        orderReq.setReceiverAddress(buildAddressKeywords(addr, delivery));
        orderReq.setReceiverDetail(buildAddressDetail(addr, delivery));
        if (addr != null && StringUtils.hasText(addr.getDistrict())) {
            orderReq.setDistrict(addr.getDistrict().trim());
        }
        orderReq.setCityName(resolveCityName(cfg, addr, order.getShop_id()));
        setReceiverCoords(orderReq, delivery, addr);
        orderReq.setProductName("外卖订单");
        orderReq.setProductAmount(order.getSett_amount() != null
                ? String.valueOf(Math.max(1, (int) Math.round(order.getSett_amount()))) : "50");
        orderReq.setProductCount(1);
        orderReq.setWeight(3);
        orderReq.setRemark(StringUtils.hasText(order.getRemark()) ? order.getRemark()
                : (delivery.getMerchant_remark() != null ? delivery.getMerchant_remark() : ""));

        CreateTakeawayDispatchRequest req = new CreateTakeawayDispatchRequest();
        req.setOrder(orderReq);
        req.setDispatch(new ZsqDispatchOptionsRequest());
        return req;
    }

    private void applyDispatchResult(TakeoutDelivery delivery, ZsqTakeawayDispatchResult result) {
        ZsqCreateOrderResult created = result.getOrder();
        if (created != null) {
            delivery.setZsq_open_order_id(created.getId());
            delivery.setZsq_order_id(created.getOrderId());
            delivery.setZsq_shop_number(created.getShopNumber());
        }
        if (result.getSelectedDeliveryCodes() != null) {
            delivery.setZsq_delivery_codes_json(toJson(result.getSelectedDeliveryCodes()));
        }
        if (result.getQuotedChannels() != null) {
            delivery.setZsq_quote_json(toJson(result.getQuotedChannels()));
        }
        if (result.getDispatch() != null) {
            delivery.setZsq_dispatch_json(toJson(result.getDispatch()));
            Object parentNo = result.getDispatch().get("parentOrderNo");
            if (parentNo == null) {
                parentNo = result.getDispatch().get("orderNo");
            }
            if (parentNo != null) {
                delivery.setZsq_parent_order_no(String.valueOf(parentNo));
            }
        }
    }

    private void syncTrackingOntoDelivery(TakeoutDelivery delivery, ZsqRiderTrackingResponse tracking) {
        if (tracking == null) {
            return;
        }
        String prevZsqStatus = normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status());
        String phase = tracking.getPhase();
        boolean operatorCancelled = isOperatorCancelled(delivery);
        if (TakeoutZsqDispatchRecovery.shouldRecoverFromActiveZsqPhase(delivery, phase)) {
            TakeoutZsqDispatchRecovery.applyRecoveryFromActiveZsqPhase(delivery);
            operatorCancelled = false;
        } else if (operatorCancelled || TakeoutZsqDispatchRecovery.hasOperatorCancelLock(delivery)) {
            TakeoutZsqDispatchRecovery.finalizeOperatorCancel(delivery);
            if (StringUtils.hasText(phase)) {
                delivery.setZsq_delivery_send_status(tracking.getDeliverySendStatus());
            }
            return;
        }
        delivery.setZsq_phase(phase);
        delivery.setZsq_delivery_send_status(tracking.getDeliverySendStatus());
        if (tracking.getActualFee() != null) {
            delivery.setZsq_actual_fee(tracking.getActualFee());
        }
        if (StringUtils.hasText(tracking.getDeliverySupplierName())) {
            delivery.setZsq_delivery_supplier_name(tracking.getDeliverySupplierName());
        }

        if (tracking.getRider() != null) {
            ZsqRiderTrackingResponse.RiderPoint rider = tracking.getRider();
            delivery.setZsq_rider_name(rider.getName());
            delivery.setZsq_rider_phone(rider.getPhone());
            if (rider.getLat() != null) {
                delivery.setZsq_rider_lat(BigDecimal.valueOf(rider.getLat()));
            }
            if (rider.getLng() != null) {
                delivery.setZsq_rider_lng(BigDecimal.valueOf(rider.getLng()));
            }
            if (rider.getLat() != null || rider.getLng() != null) {
                delivery.setZsq_rider_updated_at(new Date());
            }
        }

        if (operatorCancelled || TakeoutZsqDispatchRecovery.hasOperatorCancelLock(delivery)) {
            TakeoutZsqDispatchRecovery.finalizeOperatorCancel(delivery);
            return;
        }

        if ("TO_SHOP".equals(phase) || "TO_USER".equals(phase)) {
            delivery.setDispatch_status("delivering");
            delivery.setZsq_dispatch_status("dispatched");
        } else if ("DELIVERED".equals(phase)) {
            delivery.setDispatch_status("completed");
            delivery.setZsq_dispatch_status("completed");
        } else if ("CANCELLED".equals(phase)) {
            if ("cancelled".equals(prevZsqStatus)) {
                delivery.setDispatch_status("cancelled");
                delivery.setZsq_dispatch_status("cancelled");
                delivery.setZsq_last_error(null);
            } else {
                delivery.setDispatch_status("dispatch_failed");
                delivery.setZsq_dispatch_status("rider_cancelled");
                delivery.setZsq_last_error("骑手或平台取消配送，可重发配送");
                if (!"rider_cancelled".equals(prevZsqStatus)) {
                    takeoutDispatchAlertService.onRiderCancelled(delivery, tracking);
                }
            }
        } else if ("WAITING_RIDER".equals(phase)) {
            if (!"completed".equals(delivery.getDispatch_status())
                    && !"cancelled".equals(delivery.getDispatch_status())) {
                delivery.setDispatch_status("accepted");
            }
        }
    }

    private static boolean isOperatorCancelled(TakeoutDelivery delivery) {
        return "cancelled".equals(normalizeDispatchStatus(delivery.getDispatch_status()))
                || "cancelled".equals(normalizeZsqDispatchStatus(delivery.getZsq_dispatch_status()));
    }

    private static String normalizeDispatchStatus(String status) {
        return status == null || status.trim().isEmpty() ? "none" : status.trim().toLowerCase();
    }

    private Order requireWaimaiOrder(Integer orderId) {
        Order order = orderService.getById(orderId);
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            throw new IllegalArgumentException("非外卖订单");
        }
        return order;
    }

    private TakeoutDelivery requireDelivery(Integer orderId) {
        TakeoutDelivery delivery = takeoutDeliveryService.getByOrderId(orderId);
        if (delivery == null) {
            throw new IllegalArgumentException("外卖配送扩展不存在");
        }
        return delivery;
    }

    private String resolveCityName(ShopTakeoutConfig cfg, UserAddress addr, Integer shopId) {
        String configured = cfg != null ? cfg.getZsq_city_name() : null;
        String userCity = addr != null ? addr.getCity() : null;
        String district = addr != null ? addr.getDistrict() : null;
        return ZsqAddressTextHelper.resolveCityName(configured, userCity, district, "江门市");
    }

    private static void setReceiverCoords(CreateTakeawayOrderRequest orderReq,
                                          TakeoutDelivery delivery, UserAddress addr) {
        if (delivery.getLat() != null && delivery.getLng() != null) {
            orderReq.setReceiverLatitude(delivery.getLat().doubleValue());
            orderReq.setReceiverLongitude(delivery.getLng().doubleValue());
            orderReq.setReceiverCoordinateType("gcj02");
            return;
        }
        if (addr != null && addr.getLat() != null && addr.getLng() != null) {
            orderReq.setReceiverLatitude(addr.getLat().doubleValue());
            orderReq.setReceiverLongitude(addr.getLng().doubleValue());
            orderReq.setReceiverCoordinateType("gcj02");
        }
    }

    private static String buildAddressKeywords(UserAddress addr, TakeoutDelivery delivery) {
        String district = addr != null ? addr.getDistrict() : null;
        String detail = addr != null ? addr.getDetail_address() : null;
        String fallback = delivery.getAddress_full();
        return ZsqAddressTextHelper.buildKeywords(district, detail, fallback);
    }

    private static String buildAddressDetail(UserAddress addr, TakeoutDelivery delivery) {
        String detail = addr != null ? addr.getDetail_address() : null;
        return ZsqAddressTextHelper.buildDetail(detail, delivery.getAddress_full());
    }

    private static String normalizePhone(String phone) {
        if (phone == null) {
            return "";
        }
        String p = phone.trim();
        int idx = p.indexOf('_');
        if (idx > 0) {
            p = p.substring(0, idx);
        }
        return p.length() >= 11 ? p.substring(0, 11) : p;
    }

    private static String normalizeZsqDispatchStatus(String status) {
        return status == null || status.trim().isEmpty() ? "none" : status.trim().toLowerCase();
    }

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (JsonProcessingException e) {
            return null;
        }
    }

    private static String truncateError(Exception e) {
        String msg = e.getMessage();
        if (msg == null) {
            msg = e.getClass().getSimpleName();
        }
        return msg.length() > 500 ? msg.substring(0, 500) : msg;
    }
}
