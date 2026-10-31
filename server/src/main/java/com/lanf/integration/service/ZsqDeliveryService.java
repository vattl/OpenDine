package com.lanf.integration.service;

import com.lanf.integration.config.ZsqProperties;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.exception.ZsqPartialDispatchException;
import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.remote.dto.ZsqCreateOrderResult;
import com.lanf.integration.remote.dto.ZsqDeliveryBillingChannel;
import com.lanf.integration.remote.dto.ZsqCancelResult;
import com.lanf.integration.util.ZsqGeoUtils;
import com.lanf.integration.util.ZsqLiabilityFeeParser;
import com.lanf.util.CoordinateNormalizer;
import com.lanf.integration.web.dto.CreateTakeawayDispatchRequest;
import com.lanf.integration.web.dto.CreateTakeawayOrderRequest;
import com.lanf.integration.web.dto.ZsqDispatchOptionsRequest;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.integration.web.dto.ZsqTakeawayDispatchResult;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
public class ZsqDeliveryService {

    private static final Pattern SUPPLIER_NAME_PATTERN =
            Pattern.compile("(?:三方配送来源|配送来源|配送渠道)[:：]\\s*([^\\r\\n]+)");

    private final ZsqRemoteClient remoteClient;
    private final ZsqOrderService orderService;
    private final ZsqAuthService authService;
    private final ZsqProperties properties;

    public ZsqDeliveryService(ZsqRemoteClient remoteClient, ZsqOrderService orderService,
                              ZsqAuthService authService, ZsqProperties properties) {
        this.remoteClient = remoteClient;
        this.orderService = orderService;
        this.authService = authService;
        this.properties = properties;
    }

    /**
     * 创建外卖订单并立即发起配送（保存并发单）。
     */
    public ZsqTakeawayDispatchResult createTakeawayAndDispatch(String authorization,
                                                               CreateTakeawayDispatchRequest request) {
        CreateTakeawayOrderRequest orderReq = request.getOrder();
        ZsqCreateOrderResult created = orderService.createTakeawayOrder(authorization, orderReq);
        ZsqDispatchOptionsRequest options = request.getDispatch() != null
                ? request.getDispatch() : new ZsqDispatchOptionsRequest();
        try {
            return dispatchOpenOrder(authorization, created.getId(), options, created);
        } catch (ZsqApiException e) {
            throw new ZsqPartialDispatchException(created, e);
        }
    }

    /**
     * 对已有真省钱 open 订单询价并发配送（余额不足充值后重试，无需再 create）。
     */
    public ZsqTakeawayDispatchResult dispatchOpenOrder(String authorization, long openOrderId,
                                                       ZsqDispatchOptionsRequest options) {
        ZsqCreateOrderResult stub = new ZsqCreateOrderResult();
        stub.setId(openOrderId);
        return dispatchOpenOrder(authorization, openOrderId, options, stub);
    }

    public ZsqTakeawayDispatchResult dispatchOpenOrderWithConfig(long openOrderId,
                                                                 ZsqDispatchOptionsRequest options) {
        return authService.executeWithConfigAuth(auth -> dispatchOpenOrder(auth, openOrderId, options));
    }

    private ZsqTakeawayDispatchResult dispatchOpenOrder(String authorization, long openOrderId,
                                                        ZsqDispatchOptionsRequest options,
                                                        ZsqCreateOrderResult orderMeta) {
        Map<String, Object> detail = remoteClient.getOpenOrderDetail(authorization, openOrderId);
        ZsqDispatchOptionsRequest opts = options != null ? options : new ZsqDispatchOptionsRequest();
        Map<String, Object> billingParam = buildBillingParam(detail, openOrderId, opts);

        List<ZsqDeliveryBillingChannel> quoted = remoteClient.quoteDelivery(authorization, billingParam);
        List<Integer> selectedCodes = selectDeliveryCodes(quoted, opts);

        Map<String, Object> dispatchBody = buildDispatchBody(openOrderId, billingParam, opts, quoted, selectedCodes);
        Map<String, Object> dispatchResult = remoteClient.dispatchDelivery(authorization, dispatchBody);

        ZsqTakeawayDispatchResult result = new ZsqTakeawayDispatchResult();
        result.setOrder(orderMeta);
        result.setDispatch(dispatchResult);
        result.setQuotedChannels(quoted);
        result.setSelectedDeliveryCodes(selectedCodes);
        return result;
    }

    public ZsqTakeawayDispatchResult createTakeawayAndDispatchWithConfig(CreateTakeawayDispatchRequest request) {
        CreateTakeawayOrderRequest orderReq = request.getOrder();
        ZsqDispatchOptionsRequest options = request.getDispatch() != null
                ? request.getDispatch() : new ZsqDispatchOptionsRequest();
        ZsqCreateOrderResult created = authService.executeWithConfigAuth(
                auth -> orderService.createTakeawayOrder(auth, orderReq));
        try {
            return authService.executeWithConfigAuth(
                    auth -> dispatchOpenOrder(auth, created.getId(), options, created));
        } catch (ZsqApiException e) {
            throw new ZsqPartialDispatchException(created, e);
        }
    }

    /**
     * 骑手实时定位与 ETA，供前端展示距商家/距用户还有多久。
     */
    public ZsqRiderTrackingResponse getRiderTracking(String authorization, long openOrderId) {
        Map<String, Object> detail = remoteClient.getOpenOrderDetail(authorization, openOrderId);
        List<Map<String, Object>> timeline;
        try {
            timeline = remoteClient.getDeliveryStatusTimeline(authorization, openOrderId);
        } catch (Exception e) {
            timeline = new ArrayList<>();
        }
        List<Map<String, Object>> orderLogs;
        try {
            orderLogs = remoteClient.getOpenOrderLog(authorization, openOrderId);
        } catch (Exception e) {
            orderLogs = new ArrayList<>();
        }
        orderLogs = filterOrderLogsForOpenOrder(orderLogs, openOrderId);
        return buildTrackingResponse(detail, timeline, orderLogs);
    }

    public ZsqRiderTrackingResponse getRiderTrackingWithConfig(long openOrderId) {
        return authService.executeWithConfigAuth(auth -> getRiderTracking(auth, openOrderId));
    }

    private Map<String, Object> buildBillingParam(Map<String, Object> detail, long openOrderId,
                                                  ZsqDispatchOptionsRequest options) {
        Map<String, Object> shop = asMap(detail.get("fromAddress"));
        Map<String, Object> to = asMap(detail.get("toAddress"));

        Object deliveryShopId = detail.get("deliveryShopId");
        if (deliveryShopId == null && shop != null) {
            deliveryShopId = shop.get("id");
        }

        Map<String, Object> receiver = new HashMap<>();
        receiver.put("goodType", str(detail.get("goodType"), shop != null ? shop.get("industryType") : 1));
        receiver.put("orderNo", null);
        receiver.put("toAddress", firstNonBlank(
                getStr(to, "toAddress"), str(detail.get("receiverAddress"))));
        receiver.put("toAddressDetail", firstNonBlank(
                getStr(to, "toAddressDetail"), str(detail.get("receiverAddressDetail"))));
        receiver.put("toLatitude", str(firstNonNull(
                getStr(to, "toLatitude"), detail.get("receiverLatitude"), detail.get("toLatitude"))));
        receiver.put("toLongitude", str(firstNonNull(
                getStr(to, "toLongitude"), detail.get("receiverLongitude"), detail.get("toLongitude"))));
        receiver.put("toMobile", str(firstNonNull(
                getStr(to, "toMobile"), detail.get("receiverPhone"))));
        receiver.put("toReceiverName", firstNonBlank(
                getStr(to, "toReceiverName"), str(detail.get("receiverName"))));
        receiver.put("weight", intVal(detail.get("weight"), 3));

        Map<String, Object> param = new HashMap<>();
        param.put("appointType", 0);
        param.put("callOrderType", options.getCallOrderType() != null ? options.getCallOrderType() : "1");
        param.put("callOrderSortType", "1");
        param.put("coordinateType", 1);
        param.put("couponId", null);
        param.put("deliveryShopId", str(deliveryShopId));
        param.put("deliveryType", 1);
        param.put("isUseInsurance", 0);
        param.put("cityName", firstNonBlank(
                str(detail.get("receiverCity")), str(detail.get("cityName")), "江门市"));
        param.put("customerRemarks", str(detail.get("orderRemark")));
        param.put("receiverList", java.util.Collections.singletonList(receiver));
        param.put("tradeChannel", "4");
        param.put("storeId", detail.get("storeId"));
        param.put("openOrderId", openOrderId);
        param.put("expressType", null);
        param.put("premiumInfoList", new ArrayList<>());
        return param;
    }

    private List<Integer> selectDeliveryCodes(List<ZsqDeliveryBillingChannel> quoted,
                                              ZsqDispatchOptionsRequest options) {
        if (quoted == null || quoted.isEmpty()) {
            throw new ZsqApiException("配送询价无可用渠道");
        }
        if (options.getDeliveryCode() != null) {
            boolean found = quoted.stream()
                    .anyMatch(c -> options.getDeliveryCode().equals(c.getDeliveryCode()) && c.isAvailable());
            if (!found) {
                throw new ZsqApiException("指定配送渠道不可用: deliveryCode=" + options.getDeliveryCode());
            }
            return java.util.Collections.singletonList(options.getDeliveryCode());
        }

        int count = options.getChannelCount() != null ? options.getChannelCount()
                : properties.getAutoDispatchChannelCount();
        if (count <= 0) {
            count = 1;
        }

        List<ZsqDeliveryBillingChannel> available = quoted.stream()
                .filter(ZsqDeliveryBillingChannel::isAvailable)
                .sorted(Comparator.comparingDouble(c -> parseMoney(c.getEstimateMoney())))
                .collect(Collectors.toList());
        if (available.isEmpty()) {
            throw new ZsqApiException("配送询价无可用渠道");
        }

        List<Integer> codes = new ArrayList<>();
        for (int i = 0; i < Math.min(count, available.size()); i++) {
            codes.add(available.get(i).getDeliveryCode());
        }
        return codes;
    }

    private Map<String, Object> buildDispatchBody(long openOrderId, Map<String, Object> billingParam,
                                                  ZsqDispatchOptionsRequest options,
                                                  List<ZsqDeliveryBillingChannel> quoted,
                                                  List<Integer> selectedCodes) {
        double low = Double.MAX_VALUE;
        double high = 0;
        for (ZsqDeliveryBillingChannel ch : quoted) {
            if (ch.getDeliveryCode() != null && selectedCodes.contains(ch.getDeliveryCode()) && ch.isAvailable()) {
                double money = parseMoney(ch.getEstimateMoney());
                low = Math.min(low, money);
                high = Math.max(high, money);
            }
        }
        if (low == Double.MAX_VALUE) {
            low = 0;
        }

        Map<String, Object> body = new HashMap<>();
        body.put("autoPay", 1);
        body.put("callOrderType", options.getCallOrderType() != null ? options.getCallOrderType() : "1");
        body.put("deliveryChannelList", selectedCodes);
        body.put("lowPrice", low);
        body.put("higPrice", high);
        body.put("openOrderId", openOrderId);
        body.put("param", billingParam);
        body.put("splitProduct", null);
        return body;
    }

    private ZsqRiderTrackingResponse buildTrackingResponse(Map<String, Object> detail,
                                                           List<Map<String, Object>> timeline,
                                                           List<Map<String, Object>> orderLogs) {
        ZsqRiderTrackingResponse resp = new ZsqRiderTrackingResponse();
        resp.setOpenOrderId(longVal(detail.get("id")));
        resp.setOrderId(str(detail.get("orderId")));
        resp.setDeliveryTimeline(timeline);
        resp.setOrderLogs(orderLogs != null ? orderLogs : new ArrayList<>());

        List<Map<String, Object>> currentBatchLogs = currentDispatchBatchLogs(orderLogs);
        Map<String, Object> latestOrderLog = latestOrderLog(currentBatchLogs);
        Map<String, Object> latestRiderLocationLog = latestRiderLocationLog(currentBatchLogs);
        Integer sendStatus = latestOrderLog != null
                ? orderLogSendStatus(latestOrderLog)
                : intObj(detail.get("deliverySendStatus"));
        String sendStatusDesc = latestOrderLog != null
                ? orderLogStatusDesc(latestOrderLog)
                : str(detail.get("deliverySendStatusDesc"));
        resp.setDeliverySendStatus(sendStatus);
        resp.setDeliverySendStatusDesc(sendStatusDesc);
        String phase = resolvePhase(sendStatus, sendStatusDesc, detail);
        resp.setPhase(phase);
        resp.setEffectiveState(buildEffectiveState(
                detail, currentBatchLogs, latestOrderLog, sendStatus, sendStatusDesc, phase));
        resp.setCoordinateType(resolveTrackingCoordinateType(detail));
        resp.setTrajectoryState(buildTrajectoryState(currentBatchLogs));

        ZsqRiderTrackingResponse.RiderPoint rider = new ZsqRiderTrackingResponse.RiderPoint();
        rider.setName(firstNonBlank(
                str(detail.get("deliveryCourierName")), str(detail.get("courierName"))));
        rider.setPhone(firstNonBlank(
                str(detail.get("deliveryCourierMobile")), str(detail.get("courierMobile"))));
        rider.setLat(firstNonNull(
                ZsqGeoUtils.parseCoord(detail.get("deliveryCourierLat")),
                ZsqGeoUtils.parseCoord(detail.get("courierLat")),
                ZsqGeoUtils.parseCoord(detail.get("transporterLat"))));
        rider.setLng(firstNonNull(
                ZsqGeoUtils.parseCoord(detail.get("deliveryCourierLng")),
                ZsqGeoUtils.parseCoord(detail.get("courierLng")),
                ZsqGeoUtils.parseCoord(detail.get("transporterLng"))));
        enrichRiderFromOrderLog(rider, latestOrderLog);
        if (latestRiderLocationLog != latestOrderLog) {
            enrichRiderFromOrderLog(rider, latestRiderLocationLog);
        }
        resp.setRider(rider);

        Map<String, Object> shopAddr = asMap(detail.get("fromAddress"));
        ZsqRiderTrackingResponse.LocationPoint shop = new ZsqRiderTrackingResponse.LocationPoint();
        shop.setLat(firstNonNull(
                ZsqGeoUtils.parseCoord(detail.get("senderLatitude")),
                ZsqGeoUtils.parseCoord(detail.get("senderLat")),
                shopAddr != null ? ZsqGeoUtils.parseCoord(shopAddr.get("shopLat")) : null));
        shop.setLng(firstNonNull(
                ZsqGeoUtils.parseCoord(detail.get("senderLongitude")),
                ZsqGeoUtils.parseCoord(detail.get("senderLng")),
                shopAddr != null ? ZsqGeoUtils.parseCoord(shopAddr.get("shopLng")) : null));
        shop.setAddress(shopAddr != null ? getStr(shopAddr, "shopAddress") : null);
        shop.setAddressDetail(shopAddr != null ? getStr(shopAddr, "shopName") : null);
        resp.setShop(shop);

        Map<String, Object> toAddr = asMap(detail.get("toAddress"));
        ZsqRiderTrackingResponse.LocationPoint user = new ZsqRiderTrackingResponse.LocationPoint();
        user.setLat(firstNonNull(
                ZsqGeoUtils.parseCoord(detail.get("receiverLatitude")),
                ZsqGeoUtils.parseCoord(detail.get("toLatitude")),
                toAddr != null ? ZsqGeoUtils.parseCoord(toAddr.get("toLatitude")) : null));
        user.setLng(firstNonNull(
                ZsqGeoUtils.parseCoord(detail.get("receiverLongitude")),
                ZsqGeoUtils.parseCoord(detail.get("toLongitude")),
                toAddr != null ? ZsqGeoUtils.parseCoord(toAddr.get("toLongitude")) : null));
        user.setAddress(firstNonBlank(
                toAddr != null ? getStr(toAddr, "toAddress") : null,
                str(detail.get("receiverAddress"))));
        user.setAddressDetail(firstNonBlank(
                toAddr != null ? getStr(toAddr, "toAddressDetail") : null,
                str(detail.get("receiverAddressDetail"))));
        resp.setUser(user);

        ZsqRiderTrackingResponse.PlatformEta platformEta = new ZsqRiderTrackingResponse.PlatformEta();
        platformEta.setDistanceText(str(detail.get("riderDistance")));
        platformEta.setDurationText(str(detail.get("riderDurationText")));
        platformEta.setDescription(str(detail.get("deliveryStatusDesc")));
        if (isBlank(platformEta.getDistanceText()) && isBlank(platformEta.getDurationText())) {
            platformEta = null;
        }
        resp.setPlatformEta(platformEta);

        resp.setComputedEta(computeEta(rider, shop, user));
        resp.setActualFee(resolveActualFee(detail));
        resp.setDeliverySupplierName(resolveDeliverySupplierName(detail, latestOrderLog));
        return resp;
    }

    private ZsqRiderTrackingResponse.EffectiveState buildEffectiveState(
            Map<String, Object> detail,
            List<Map<String, Object>> currentBatchLogs,
            Map<String, Object> latestOrderLog,
            Integer sendStatus,
            String sendStatusDesc,
            String phase) {
        ZsqRiderTrackingResponse.EffectiveState state =
                new ZsqRiderTrackingResponse.EffectiveState();
        state.setSendStatus(sendStatus);
        state.setStatusDesc(sendStatusDesc);
        state.setPhase(phase);

        boolean logIsAuthoritative = latestOrderLog != null
                && orderLogSendStatus(latestOrderLog) != null;
        state.setSource(logIsAuthoritative ? "ORDER_LOG" : "ORDER_DETAIL");
        if (logIsAuthoritative) {
            state.setEffectiveLogId(firstNonNull(
                    longVal(latestOrderLog.get("sortNum")), longVal(latestOrderLog.get("id"))));
            state.setUpdatedAt(firstNonBlank(
                    str(latestOrderLog.get("createTime")),
                    str(latestOrderLog.get("pcCreateTime"))));
        } else {
            state.setUpdatedAt(firstNonBlank(
                    str(detail.get("currStatusTime")),
                    str(detail.get("updateTime")),
                    str(detail.get("createTime"))));
        }

        Map<String, Object> dispatchStart = latestDispatchStartLog(currentBatchLogs);
        state.setParentOrderNo(firstNonBlank(
                str(detail.get("deliveryParentOrderCode")),
                str(detail.get("deliveryParentOrderNo")),
                dispatchStart != null ? str(dispatchStart.get("deliveryParentOrderNo")) : null,
                dispatchStart != null
                        ? lineValue(str(dispatchStart.get("content")), "配送单号") : null));
        state.setThirdPartyOrderNo(firstNonBlank(
                str(detail.get("thirdPartyOrderCode")),
                str(detail.get("deliveryOrderCode")),
                latestOrderLog != null
                        ? lineValue(str(latestOrderLog.get("content")), "三方配送单号") : null));
        return state;
    }

    /**
     * Converts a tracking response to the system GCJ-02 contract using canonical local endpoints.
     * ZSQ coordinateType=1 and undeclared legacy tracking responses are treated as BD-09.
     */
    public void normalizeTrackingToGcj02(ZsqRiderTrackingResponse tracking,
                                         Double localShopLat, Double localShopLng,
                                         Double localUserLat, Double localUserLng) {
        if (tracking == null) {
            return;
        }
        String sourceType = resolveTrackingSourceType(tracking);
        normalizeRiderPoint(tracking.getRider(), sourceType);

        ZsqRiderTrackingResponse.LocationPoint shop = ensureLocation(tracking.getShop());
        if (localShopLat != null && localShopLng != null) {
            shop.setLat(localShopLat);
            shop.setLng(localShopLng);
            normalizeLocationPoint(shop, CoordinateNormalizer.GCJ02);
        } else {
            normalizeLocationPoint(shop, sourceType);
        }
        tracking.setShop(shop);

        ZsqRiderTrackingResponse.LocationPoint user = ensureLocation(tracking.getUser());
        if (localUserLat != null && localUserLng != null) {
            user.setLat(localUserLat);
            user.setLng(localUserLng);
            normalizeLocationPoint(user, CoordinateNormalizer.GCJ02);
        } else {
            normalizeLocationPoint(user, sourceType);
        }
        tracking.setUser(user);
        normalizeTimeline(tracking.getDeliveryTimeline(), sourceType);
        tracking.setCoordinateType(CoordinateNormalizer.GCJ02);
        tracking.setComputedEta(computeEta(tracking.getRider(), shop, user));
    }

    private String resolveTrackingSourceType(ZsqRiderTrackingResponse tracking) {
        String rawType = tracking.getCoordinateType();
        if (rawType != null && !rawType.trim().isEmpty()) {
            String declared = CoordinateNormalizer.normalizeType(rawType);
            if (CoordinateNormalizer.BD09.equals(declared)
                    || CoordinateNormalizer.GCJ02.equals(declared)
                    || CoordinateNormalizer.WGS84.equals(declared)) {
                return declared;
            }
        }
        // 真省钱 coordinateType=1 的轨迹边界为 BD-09；旧响应缺少声明时也按该契约处理。
        return CoordinateNormalizer.BD09;
    }

    private void normalizeRiderPoint(ZsqRiderTrackingResponse.RiderPoint point, String sourceType) {
        if (point == null) {
            return;
        }
        CoordinateNormalizer.Point normalized = normalizePoint(point.getLat(), point.getLng(), sourceType);
        point.setLat(normalized != null ? normalized.getLat() : null);
        point.setLng(normalized != null ? normalized.getLng() : null);
    }

    private void normalizeLocationPoint(ZsqRiderTrackingResponse.LocationPoint point, String sourceType) {
        CoordinateNormalizer.Point normalized = normalizePoint(point.getLat(), point.getLng(), sourceType);
        point.setLat(normalized != null ? normalized.getLat() : null);
        point.setLng(normalized != null ? normalized.getLng() : null);
    }

    private CoordinateNormalizer.Point normalizePoint(Double lat, Double lng, String sourceType) {
        if (lat == null || lng == null) {
            return null;
        }
        try {
            return CoordinateNormalizer.toGcj02(lat, lng, sourceType);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private void normalizeTimeline(List<Map<String, Object>> timeline, String sourceType) {
        if (timeline == null) {
            return;
        }
        for (Map<String, Object> node : timeline) {
            normalizeTimelineValue(node, sourceType);
        }
    }

    @SuppressWarnings("unchecked")
    private void normalizeTimelineValue(Object value, String sourceType) {
        if (value instanceof Map) {
            Map<String, Object> map = (Map<String, Object>) value;
            String nodeSourceType = resolveCoordinateType(map.get("coordinateType"), sourceType);
            normalizeMapPoint(map, "lat", "lng", nodeSourceType);
            normalizeMapPoint(map, "latitude", "longitude", nodeSourceType);
            normalizeMapPoint(map, "deliveryCourierLat", "deliveryCourierLng", nodeSourceType);
            normalizeMapPoint(map, "courierLat", "courierLng", nodeSourceType);
            normalizeMapPoint(map, "transporterLat", "transporterLng", nodeSourceType);
            for (Object nested : new ArrayList<>(map.values())) {
                if (nested instanceof Map || nested instanceof List) {
                    normalizeTimelineValue(nested, nodeSourceType);
                }
            }
        } else if (value instanceof List) {
            for (Object nested : (List<?>) value) {
                normalizeTimelineValue(nested, sourceType);
            }
        }
    }

    private void normalizeMapPoint(Map<String, Object> map, String latKey, String lngKey,
                                   String sourceType) {
        if (!map.containsKey(latKey) && !map.containsKey(lngKey)) {
            return;
        }
        CoordinateNormalizer.Point normalized = normalizePoint(
                ZsqGeoUtils.parseCoord(map.get(latKey)),
                ZsqGeoUtils.parseCoord(map.get(lngKey)), sourceType);
        map.put(latKey, normalized != null ? normalized.getLat() : null);
        map.put(lngKey, normalized != null ? normalized.getLng() : null);
        map.put("coordinateType", CoordinateNormalizer.GCJ02);
    }

    private String resolveTrackingCoordinateType(Map<String, Object> detail) {
        String direct = resolveCoordinateType(detail.get("coordinateType"), null);
        if (direct != null) {
            return direct;
        }
        Map<String, Object> fromAddress = asMap(detail.get("fromAddress"));
        String from = resolveCoordinateType(fromAddress != null ? fromAddress.get("coordinateType") : null, null);
        if (from != null) {
            return from;
        }
        Map<String, Object> toAddress = asMap(detail.get("toAddress"));
        String to = resolveCoordinateType(toAddress != null ? toAddress.get("coordinateType") : null, null);
        return to != null ? to : "zsq_raw";
    }

    private String resolveCoordinateType(Object raw, String fallback) {
        if (raw == null) {
            return fallback;
        }
        String value = String.valueOf(raw).trim();
        if ("1".equals(value)) {
            return CoordinateNormalizer.BD09;
        }
        String normalized = CoordinateNormalizer.normalizeType(value);
        if (CoordinateNormalizer.BD09.equals(normalized)
                || CoordinateNormalizer.GCJ02.equals(normalized)
                || CoordinateNormalizer.WGS84.equals(normalized)) {
            return normalized;
        }
        return fallback;
    }

    private static ZsqRiderTrackingResponse.LocationPoint ensureLocation(
            ZsqRiderTrackingResponse.LocationPoint point) {
        return point != null ? point : new ZsqRiderTrackingResponse.LocationPoint();
    }

    private ZsqRiderTrackingResponse.ComputedEta computeEta(ZsqRiderTrackingResponse.RiderPoint rider,
                                                            ZsqRiderTrackingResponse.LocationPoint shop,
                                                            ZsqRiderTrackingResponse.LocationPoint user) {
        if (rider == null || rider.getLat() == null || rider.getLng() == null) {
            return null;
        }
        double speed = properties.getRiderSpeedKmh();
        ZsqRiderTrackingResponse.ComputedEta eta = new ZsqRiderTrackingResponse.ComputedEta();
        eta.setSpeedKmh(speed);

        if (shop != null && shop.getLat() != null && shop.getLng() != null) {
            double km = ZsqGeoUtils.haversineKm(rider.getLat(), rider.getLng(), shop.getLat(), shop.getLng());
            eta.setRiderToShopKm(round2(km));
            eta.setToShopMinutes(ZsqGeoUtils.etaMinutes(km, speed));
        }
        if (user != null && user.getLat() != null && user.getLng() != null) {
            double km = ZsqGeoUtils.haversineKm(rider.getLat(), rider.getLng(), user.getLat(), user.getLng());
            eta.setRiderToUserKm(round2(km));
            eta.setToUserMinutes(ZsqGeoUtils.etaMinutes(km, speed));
        }
        if (eta.getRiderToShopKm() == null && eta.getRiderToUserKm() == null) {
            return null;
        }
        return eta;
    }

    /** 真省钱配送状态：20待接、30取货中、80到店、40配送中、50完成、60取消。 */
    private String resolvePhase(Integer sendStatus, String sendStatusDesc, Map<String, Object> detail) {
        if (sendStatus != null) {
            if (sendStatus == 60) {
                return "CANCELLED";
            }
            if (sendStatus == 50) {
                return "DELIVERED";
            }
            if (sendStatus == 30 || sendStatus == 80) {
                return "TO_SHOP";
            }
            if (sendStatus == 40) {
                return "TO_USER";
            }
            if (sendStatus <= 0 || sendStatus == 10 || sendStatus == 20) {
                return "WAITING_RIDER";
            }
        }
        String normalizedDesc = firstNonBlank(sendStatusDesc,
                str(detail.get("deliverySendStatusDesc")),
                str(detail.get("deliveryStatusDesc")));
        if (!isBlank(normalizedDesc)) {
            if (normalizedDesc.contains("取消")) {
                return "CANCELLED";
            }
            if (normalizedDesc.contains("完成") || normalizedDesc.contains("送达")) {
                return "DELIVERED";
            }
        }
        Object orderStatus = detail.get("status");
        if (orderStatus instanceof Number && ((Number) orderStatus).intValue() >= 90) {
            return "CANCELLED";
        }
        return "UNKNOWN";
    }

    private Map<String, Object> latestOrderLog(List<Map<String, Object>> orderLogs) {
        Map<String, Object> latest = null;
        Long latestSortNum = null;
        if (orderLogs == null) {
            return null;
        }
        for (Map<String, Object> candidate : orderLogs) {
            if (candidate == null || orderLogSendStatus(candidate) == null) {
                continue;
            }
            Long candidateSortNum = firstNonNull(
                    longVal(candidate.get("sortNum")), longVal(candidate.get("id")));
            if (latest == null || (candidateSortNum != null
                    && (latestSortNum == null || candidateSortNum > latestSortNum))) {
                latest = candidate;
                latestSortNum = candidateSortNum;
            }
        }
        return latest;
    }

    private Map<String, Object> latestRiderLocationLog(List<Map<String, Object>> orderLogs) {
        Map<String, Object> latest = null;
        Long latestSortNum = null;
        if (orderLogs == null) {
            return null;
        }
        for (Map<String, Object> candidate : orderLogs) {
            if (!hasOrderLogCoordinate(candidate)) {
                continue;
            }
            Long candidateSortNum = firstNonNull(
                    longVal(candidate.get("sortNum")), longVal(candidate.get("id")));
            if (latest == null || (candidateSortNum != null
                    && (latestSortNum == null || candidateSortNum > latestSortNum))) {
                latest = candidate;
                latestSortNum = candidateSortNum;
            }
        }
        return latest;
    }

    /**
     * Only logs from the latest "配送下单" event belong to the current dispatch batch.
     * Earlier cancellations remain in raw orderLogs for history, but must not affect the current state.
     */
    private List<Map<String, Object>> currentDispatchBatchLogs(List<Map<String, Object>> orderLogs) {
        if (orderLogs == null || orderLogs.isEmpty()) {
            return new ArrayList<>();
        }
        Map<String, Object> latestDispatchStart = null;
        for (Map<String, Object> orderLog : orderLogs) {
            if (isDispatchStartLog(orderLog)
                    && (latestDispatchStart == null || compareLogOrder(orderLog, latestDispatchStart) > 0)) {
                latestDispatchStart = orderLog;
            }
        }
        if (latestDispatchStart == null) {
            return new ArrayList<>(orderLogs);
        }
        List<Map<String, Object>> current = new ArrayList<>();
        for (Map<String, Object> orderLog : orderLogs) {
            if (orderLog != null && compareLogOrder(orderLog, latestDispatchStart) >= 0) {
                current.add(orderLog);
            }
        }
        return current;
    }

    private Map<String, Object> latestDispatchStartLog(List<Map<String, Object>> orderLogs) {
        Map<String, Object> latest = null;
        if (orderLogs == null) {
            return null;
        }
        for (Map<String, Object> orderLog : orderLogs) {
            if (isDispatchStartLog(orderLog)
                    && (latest == null || compareLogOrder(orderLog, latest) > 0)) {
                latest = orderLog;
            }
        }
        return latest;
    }

    private boolean isDispatchStartLog(Map<String, Object> orderLog) {
        if (orderLog == null) {
            return false;
        }
        String title = str(orderLog.get("title"));
        if ("配送下单".equals(title)) {
            return true;
        }
        String content = str(orderLog.get("content"));
        return !isBlank(lineValue(content, "配送单号"))
                && !isBlank(lineValue(content, "来源"));
    }

    private int compareLogOrder(Map<String, Object> left, Map<String, Object> right) {
        Long leftId = firstNonNull(longVal(left.get("sortNum")), longVal(left.get("id")));
        Long rightId = firstNonNull(longVal(right.get("sortNum")), longVal(right.get("id")));
        if (leftId != null && rightId != null) {
            return Long.compare(leftId, rightId);
        }
        String leftTime = firstNonBlank(str(left.get("pcCreateTime")), str(left.get("createTime")));
        String rightTime = firstNonBlank(str(right.get("pcCreateTime")), str(right.get("createTime")));
        if (leftTime == null) {
            return rightTime == null ? 0 : -1;
        }
        return rightTime == null ? 1 : leftTime.compareTo(rightTime);
    }

    private boolean hasOrderLogCoordinate(Map<String, Object> orderLog) {
        if (orderLog == null) {
            return false;
        }
        String coordinate = lineValue(str(orderLog.get("content")), "经纬度");
        if (isBlank(coordinate)) {
            return false;
        }
        String[] pair = coordinate.split(",", -1);
        return pair.length == 2
                && ZsqGeoUtils.parseCoord(pair[0]) != null
                && ZsqGeoUtils.parseCoord(pair[1]) != null;
    }

    private List<Map<String, Object>> filterOrderLogsForOpenOrder(List<Map<String, Object>> orderLogs,
                                                                 long expectedOpenOrderId) {
        if (orderLogs == null || orderLogs.isEmpty()) {
            return new ArrayList<>();
        }
        List<Map<String, Object>> matched = new ArrayList<>();
        for (Map<String, Object> orderLog : orderLogs) {
            if (belongsToOpenOrder(orderLog, expectedOpenOrderId)) {
                matched.add(orderLog);
            }
        }
        return matched;
    }

    private boolean belongsToOpenOrder(Map<String, Object> orderLog, long expectedOpenOrderId) {
        if (orderLog == null) {
            return false;
        }
        Long directOpenOrderId = longVal(orderLog.get("openOrderId"));
        if (directOpenOrderId != null) {
            return directOpenOrderId == expectedOpenOrderId;
        }
        Object rawList = orderLog.get("list");
        if (!(rawList instanceof List)) {
            return false;
        }
        for (Object value : (List<?>) rawList) {
            Map<String, Object> node = asMap(value);
            Long nestedOpenOrderId = node != null ? longVal(node.get("openOrderId")) : null;
            if (nestedOpenOrderId != null && nestedOpenOrderId == expectedOpenOrderId) {
                return true;
            }
        }
        return false;
    }

    private Integer orderLogSendStatus(Map<String, Object> orderLog) {
        Integer structuredStatus = intObj(orderLog.get("sendStatus"));
        if (structuredStatus != null) {
            return structuredStatus;
        }
        String title = str(orderLog.get("title"));
        String content = str(orderLog.get("content"));
        if ((!isBlank(title) && title.contains("取消配送"))
                || !isBlank(lineValue(content, "取消原因"))) {
            return 60;
        }
        String status = orderLogStatusDesc(orderLog);
        if (isBlank(status)) {
            return null;
        }
        if (status.contains("取消") || status.contains("异常单")) {
            return 60;
        }
        if (status.contains("完成") || status.contains("送达")) {
            return 50;
        }
        if (status.contains("配送中")) {
            return 40;
        }
        if (status.contains("骑士到店") || status.contains("骑手到店") || status.contains("已到店")) {
            return 80;
        }
        if (status.contains("取货") || status.contains("已接单")) {
            return 30;
        }
        if (status.contains("待接单") || status.contains("新订单")) {
            return 20;
        }
        return null;
    }

    private ZsqRiderTrackingResponse.TrajectoryState buildTrajectoryState(
            List<Map<String, Object>> orderLogs) {
        if (orderLogs == null || orderLogs.isEmpty()) {
            return null;
        }
        ZsqRiderTrackingResponse.TrajectoryState state =
                new ZsqRiderTrackingResponse.TrajectoryState();
        Long callbackLogId = null;
        Long orderStatusLogId = null;
        Long deliveryStatusLogId = null;
        Long cancelReasonLogId = null;
        Long latestStatusLogId = null;
        boolean found = false;

        for (Map<String, Object> orderLog : orderLogs) {
            if (orderLog == null) {
                continue;
            }
            Long logId = firstNonNull(longVal(orderLog.get("sortNum")), longVal(orderLog.get("id")));
            String content = str(orderLog.get("content"));
            String callbackStatus = lineValue(content, "回传状态");
            if (!isBlank(callbackStatus) && isNewerLog(logId, callbackLogId)) {
                state.setCallbackStatus(callbackStatus);
                callbackLogId = logId;
                found = true;
            }

            String deliveryStatus = lineValue(content, "配送状态");
            if (!isBlank(deliveryStatus) && isNewerLog(logId, deliveryStatusLogId)) {
                state.setDeliveryStatus(deliveryStatus);
                deliveryStatusLogId = logId;
                found = true;
            }

            String orderTransition = lineValue(content, "订单状态");
            if (!isBlank(orderTransition) && isNewerLog(logId, orderStatusLogId)) {
                String[] transition = splitStatusTransition(orderTransition);
                state.setPreviousOrderStatus(transition[0]);
                state.setOrderStatus(transition[1]);
                orderStatusLogId = logId;
                found = true;
            }

            String cancelReason = lineValue(content, "取消原因");
            if (!isBlank(cancelReason) && isNewerLog(logId, cancelReasonLogId)) {
                state.setCancelReason(cancelReason);
                cancelReasonLogId = logId;
                found = true;
            }

            if ((orderLogSendStatus(orderLog) != null || !isBlank(callbackStatus)
                    || !isBlank(deliveryStatus) || !isBlank(orderTransition)
                    || !isBlank(cancelReason)) && isNewerLog(logId, latestStatusLogId)) {
                latestStatusLogId = logId;
                state.setLatestStatusLogId(logId);
                state.setStatusUpdatedAt(firstNonBlank(
                        str(orderLog.get("createTime")), str(orderLog.get("pcCreateTime"))));
            }
        }
        return found ? state : null;
    }

    private boolean isNewerLog(Long candidateId, Long currentId) {
        return currentId == null || (candidateId != null && candidateId > currentId);
    }

    private String[] splitStatusTransition(String transition) {
        int arrow = transition.lastIndexOf("->");
        int arrowLength = 2;
        if (arrow < 0) {
            arrow = transition.lastIndexOf('→');
            arrowLength = 1;
        }
        if (arrow < 0) {
            String status = transition.trim();
            return new String[]{null, status};
        }
        return new String[]{
                transition.substring(0, arrow).trim(),
                transition.substring(arrow + arrowLength).trim()
        };
    }

    private String orderLogStatusDesc(Map<String, Object> orderLog) {
        String structured = firstNonBlank(
                str(orderLog.get("orderStatusDesc")), str(orderLog.get("statusDesc")));
        if (!isBlank(structured)) {
            return structured;
        }
        String content = str(orderLog.get("content"));
        String status = firstNonBlank(
                lineValue(content, "回传状态"), lineValue(content, "配送状态"));
        if (!isBlank(status)) {
            return status;
        }
        String transition = lineValue(content, "订单状态");
        if (!isBlank(transition)) {
            int arrow = transition.lastIndexOf("->");
            return arrow >= 0 ? transition.substring(arrow + 2).trim() : transition;
        }
        return null;
    }

    private void enrichRiderFromOrderLog(ZsqRiderTrackingResponse.RiderPoint rider,
                                         Map<String, Object> latestOrderLog) {
        if (rider == null || latestOrderLog == null) {
            return;
        }
        Object rawList = latestOrderLog.get("list");
        Map<String, Object> latestNode = null;
        Long latestNodeId = null;
        if (rawList instanceof List) {
            for (Object value : (List<?>) rawList) {
                Map<String, Object> node = asMap(value);
                if (node == null) {
                    continue;
                }
                Long nodeId = longVal(node.get("id"));
                if (latestNode == null || (nodeId != null && (latestNodeId == null || nodeId > latestNodeId))) {
                    latestNode = node;
                    latestNodeId = nodeId;
                }
            }
        }
        if (latestNode != null) {
            rider.setName(firstNonBlank(str(latestNode.get("deliveryCourierName")), rider.getName()));
            rider.setPhone(firstNonBlank(str(latestNode.get("deliveryCourierMobile")), rider.getPhone()));
        }
        String content = str(latestOrderLog.get("content"));
        rider.setName(firstNonBlank(lineValue(content, "骑手姓名"), rider.getName()));
        rider.setPhone(firstNonBlank(lineValue(content, "骑手电话"), rider.getPhone()));
        String coordinate = lineValue(content, "经纬度");
        if (!isBlank(coordinate)) {
            String[] pair = coordinate.split(",", -1);
            if (pair.length == 2) {
                Double lng = ZsqGeoUtils.parseCoord(pair[0]);
                Double lat = ZsqGeoUtils.parseCoord(pair[1]);
                if (lat != null && lng != null) {
                    rider.setLat(lat);
                    rider.setLng(lng);
                    rider.setLocationLogId(firstNonNull(
                            longVal(latestOrderLog.get("sortNum")), longVal(latestOrderLog.get("id"))));
                    rider.setLocationUpdatedAt(firstNonBlank(
                            str(latestOrderLog.get("createTime")), str(latestOrderLog.get("pcCreateTime"))));
                }
            }
        }
    }

    private String lineValue(String content, String key) {
        if (isBlank(content) || isBlank(key)) {
            return null;
        }
        for (String rawLine : content.split("\\r?\\n")) {
            String line = rawLine.trim();
            String asciiPrefix = key + ":";
            String chinesePrefix = key + "：";
            if (line.startsWith(asciiPrefix)) {
                return line.substring(asciiPrefix.length()).trim();
            }
            if (line.startsWith(chinesePrefix)) {
                return line.substring(chinesePrefix.length()).trim();
            }
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> asMap(Object value) {
        if (value instanceof Map) {
            return (Map<String, Object>) value;
        }
        return null;
    }

    private String getStr(Map<String, Object> map, String key) {
        return map == null ? null : str(map.get(key));
    }

    private String str(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private String str(Object value, Object fallback) {
        String s = str(value);
        return isBlank(s) ? str(fallback) : s;
    }

    @SafeVarargs
    private final <T> T firstNonNull(T... values) {
        for (T v : values) {
            if (v != null) {
                return v;
            }
        }
        return null;
    }

    private String firstNonBlank(String... values) {
        for (String v : values) {
            if (!isBlank(v)) {
                return v;
            }
        }
        return null;
    }

    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    private int intVal(Object value, int defaultVal) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        if (value != null) {
            try {
                return Integer.parseInt(String.valueOf(value).trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return defaultVal;
    }

    private Integer intObj(Object value) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        if (value != null) {
            try {
                return Integer.parseInt(String.valueOf(value).trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }

    private Long longVal(Object value) {
        if (value instanceof Number) {
            return ((Number) value).longValue();
        }
        if (value != null) {
            try {
                return Long.parseLong(String.valueOf(value).trim());
            } catch (NumberFormatException ignored) {
            }
        }
        return null;
    }

    private double parseMoney(String money) {
        if (money == null || money.trim().isEmpty()) {
            return 999999;
        }
        try {
            return Double.parseDouble(money.trim());
        } catch (NumberFormatException e) {
            return 999999;
        }
    }

    /**
     * 取消真省钱外卖/配送单，并解析责任扣费。
     */
    public ZsqCancelResult cancelTakeawayOrder(String authorization, long openOrderId,
                                               String parentOrderNo, boolean dispatched) {
        Map<String, Object> promptWrapper = null;
        String cancelPrompt = null;
        BigDecimal liability = null;

        if (dispatched) {
            try {
                promptWrapper = remoteClient.getDeliveryCancelPrompt(authorization, openOrderId);
                cancelPrompt = extractCancelPrompt(promptWrapper);
                liability = ZsqLiabilityFeeParser.parseFromMaps(promptWrapper);
                liability = ZsqLiabilityFeeParser.merge(liability,
                        ZsqLiabilityFeeParser.parseFromPromptText(cancelPrompt));
            } catch (Exception ignored) {
                // 无配送或平台不支持提示时继续尝试取消
            }
        }

        // 真省钱 open 订单取消的权威接口。成功响应允许 data=null，不能据此再次尝试其它取消接口。
        Map<String, Object> cancelResp = remoteClient.cancelOpenOrder(authorization, openOrderId);

        liability = ZsqLiabilityFeeParser.merge(liability, ZsqLiabilityFeeParser.parseFromMaps(cancelResp));
        liability = ZsqLiabilityFeeParser.merge(liability,
                ZsqLiabilityFeeParser.parseFromPromptText(cancelPrompt));

        ZsqCancelResult result = new ZsqCancelResult();
        result.setSuccess(true);
        result.setMessage("取消成功");
        result.setCancelPrompt(cancelPrompt);
        result.setLiabilityFeeYuan(liability);
        result.setRawPrompt(promptWrapper);
        result.setRawCancel(cancelResp);
        return result;
    }

    public ZsqCancelResult cancelTakeawayOrderWithConfig(long openOrderId, String parentOrderNo, boolean dispatched) {
        return authService.executeWithConfigAuth(
                auth -> cancelTakeawayOrder(auth, openOrderId, parentOrderNo, dispatched));
    }

    private static String extractCancelPrompt(Map<String, Object> map) {
        if (map == null) {
            return null;
        }
        Object p = map.get("cancelPrompt");
        return p != null ? String.valueOf(p) : null;
    }

    private double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    private BigDecimal resolveActualFee(Map<String, Object> detail) {
        if (detail == null) {
            return null;
        }
        Object[] candidates = new Object[]{
                detail.get("shopActualCost"),
                detail.get("discountLastMoney"),
                detail.get("yhpsDiscountLastMoney")
        };
        for (Object val : candidates) {
            BigDecimal bd = toBigDecimalMoney(val);
            if (bd != null && bd.compareTo(BigDecimal.ZERO) >= 0) {
                return bd;
            }
        }
        return null;
    }

    private static BigDecimal toBigDecimalMoney(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number) {
            return BigDecimal.valueOf(((Number) value).doubleValue()).setScale(2, RoundingMode.HALF_UP);
        }
        String s = String.valueOf(value).trim();
        if (s.isEmpty()) {
            return null;
        }
        s = s.replace("元", "").replace("￥", "").replace(",", "").trim();
        try {
            return new BigDecimal(s).setScale(2, RoundingMode.HALF_UP);
        } catch (Exception ignored) {
            return null;
        }
    }

    private String resolveDeliverySupplierName(Map<String, Object> detail, Map<String, Object> latestOrderLog) {
        if (detail != null) {
            String supplier = firstNonBlank(
                    str(detail.get("deliverySupplierName")),
                    str(detail.get("callingSupplierName")));
            if (!isBlank(supplier)) {
                return supplier;
            }
        }
        if (latestOrderLog != null) {
            String content = str(latestOrderLog.get("content"));
            if (!isBlank(content)) {
                Matcher m = SUPPLIER_NAME_PATTERN.matcher(content);
                if (m.find()) {
                    return m.group(1).trim();
                }
            }
        }
        return null;
    }
}
