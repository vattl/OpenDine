package com.lanf.integration.service;

import com.lanf.integration.config.ZsqProperties;
import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ZsqDeliveryCoordinateNormalizationTest {

    @Test
    void readsBd09CoordinateTypeDeclaredByZsqAddress() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> fromAddress = new HashMap<>();
        fromAddress.put("coordinateType", 1);
        fromAddress.put("shopLat", "22.771600");
        fromAddress.put("shopLng", "112.970500");
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54159992L);
        detail.put("fromAddress", fromAddress);
        when(remoteClient.getOpenOrderDetail("token", 54159992L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54159992L)).thenReturn(new ArrayList<>());
        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54159992L);

        assertEquals("bd09", tracking.getCoordinateType());
    }

    @Test
    void usesNewestOperationLogEntryAsCanonicalDeliveryStatus() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54160088L);
        detail.put("deliverySendStatus", 20);
        detail.put("deliverySendStatusDesc", "待接单");
        detail.put("deliveryCourierName", "旧渠道骑手");
        when(remoteClient.getOpenOrderDetail("token", 54160088L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54160088L)).thenReturn(new ArrayList<>());

        Map<String, Object> completed = new HashMap<>();
        completed.put("id", 841183281213701L);
        completed.put("openOrderId", 54160088L);
        completed.put("type", 2);
        completed.put("subType", 201);
        completed.put("title", "真省钱回传配送信息");
        completed.put("content", "骑手姓名: 张骑手\r\n骑手电话: 13800138001\r\n"
                + "三方配送来源: 京东特惠\r\n回传状态: 已完成\r\n"
                + "经纬度: 112.98070903808514,22.77187797310817");
        Map<String, Object> cancelled = new HashMap<>();
        cancelled.put("id", 841183280644357L);
        cancelled.put("openOrderId", 54160088L);
        cancelled.put("type", 5);
        cancelled.put("content", "配送状态: 已取消\r\n订单状态: 配送中 -> 已取消");
        when(remoteClient.getOpenOrderLog("token", 54160088L))
                .thenReturn(java.util.Arrays.asList(cancelled, completed));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54160088L);

        assertEquals(50, tracking.getDeliverySendStatus());
        assertEquals("已完成", tracking.getDeliverySendStatusDesc());
        assertEquals("DELIVERED", tracking.getPhase());
        assertEquals("张骑手", tracking.getRider().getName());
        assertEquals("13800138001", tracking.getRider().getPhone());
        assertEquals(22.77187797310817, tracking.getRider().getLat(), 0.0000001);
        assertEquals(112.98070903808514, tracking.getRider().getLng(), 0.0000001);
    }

    @Test
    void mapsOrderLogSendStatus60ToCancelledInsteadOfDelivered() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54160088L);
        detail.put("deliverySendStatus", 40);
        when(remoteClient.getOpenOrderDetail("token", 54160088L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54160088L)).thenReturn(new ArrayList<>());

        Map<String, Object> cancelled = new HashMap<>();
        cancelled.put("id", 841183281213702L);
        cancelled.put("openOrderId", 54160088L);
        cancelled.put("type", 2);
        cancelled.put("subType", 201);
        cancelled.put("content", "骑手姓名: 张骑手\r\n回传状态: 已取消");
        when(remoteClient.getOpenOrderLog("token", 54160088L))
                .thenReturn(java.util.Collections.singletonList(cancelled));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54160088L);

        assertEquals(60, tracking.getDeliverySendStatus());
        assertEquals("CANCELLED", tracking.getPhase());
    }

    @Test
    void ignoresOrderLogsBelongingToAnotherOpenOrder() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54160088L);
        detail.put("deliverySendStatus", 20);
        detail.put("deliverySendStatusDesc", "待接单");
        when(remoteClient.getOpenOrderDetail("token", 54160088L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54160088L)).thenReturn(new ArrayList<>());

        Map<String, Object> wrongOrderLog = new HashMap<>();
        wrongOrderLog.put("id", 841183281213701L);
        wrongOrderLog.put("openOrderId", 54047523L);
        wrongOrderLog.put("content", "回传状态: 已完成");
        when(remoteClient.getOpenOrderLog("token", 54160088L))
                .thenReturn(java.util.Collections.singletonList(wrongOrderLog));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54160088L);

        assertEquals(20, tracking.getDeliverySendStatus());
        assertEquals("WAITING_RIDER", tracking.getPhase());
    }

    @Test
    void usesLatestCoordinateLogWhenNewerStatusLogHasNoLocation() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54048302L);
        detail.put("deliverySendStatus", 20);
        when(remoteClient.getOpenOrderDetail("token", 54048302L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54048302L)).thenReturn(new ArrayList<>());

        Map<String, Object> latestStatus = new HashMap<>();
        latestStatus.put("id", 841190897983557L);
        latestStatus.put("openOrderId", 54048302L);
        latestStatus.put("type", 5);
        latestStatus.put("content", "配送状态: 配送中\r\n订单状态: 取货中 -> 配送中");
        Map<String, Object> latestLocation = new HashMap<>();
        latestLocation.put("id", 841190888849861L);
        latestLocation.put("openOrderId", 54048302L);
        latestLocation.put("type", 2);
        latestLocation.put("subType", 202);
        latestLocation.put("content", "骑手姓名: 张骑手\r\n骑手电话: 13800138001\r\n"
                + "回传状态: 配送中\r\n经纬度: 112.97473779554853,22.763579847937205");
        when(remoteClient.getOpenOrderLog("token", 54048302L))
                .thenReturn(java.util.Arrays.asList(latestStatus, latestLocation));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54048302L);

        assertEquals(40, tracking.getDeliverySendStatus());
        assertEquals("TO_USER", tracking.getPhase());
        assertEquals("张骑手", tracking.getRider().getName());
        assertEquals(22.763579847937205, tracking.getRider().getLat(), 0.0000001);
        assertEquals(112.97473779554853, tracking.getRider().getLng(), 0.0000001);
    }

    @Test
    void preservesCoreTrajectoryStatesAndTreatsMerchantCancellationAsCancelled() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54232322L);
        detail.put("orderId", "841794065912197");
        detail.put("deliverySendStatus", 30);
        when(remoteClient.getOpenOrderDetail("token", 54232322L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54232322L)).thenReturn(new ArrayList<>());

        Map<String, Object> cancelled = new HashMap<>();
        cancelled.put("id", 841795756380357L);
        cancelled.put("openOrderId", 54232322L);
        cancelled.put("type", 3);
        cancelled.put("title", "取消配送单");
        cancelled.put("content", "订单状态: 取货中 -> 异常单\r\n取消原因: 商家取消\r\n操作人: 店员 13800138000");
        cancelled.put("createTime", "2026-08-25 18:15:44");

        Map<String, Object> callback = new HashMap<>();
        callback.put("id", 841795640996101L);
        callback.put("openOrderId", 54232322L);
        callback.put("type", 2);
        callback.put("subType", 201);
        callback.put("content", "骑手姓名: 李骑手\r\n骑手电话: 13800138002\r\n"
                + "回传状态: 取货中\r\n经纬度: 112.97509773999961,22.757134184148953");
        callback.put("createTime", "2026-08-25 18:15:16");

        Map<String, Object> delivery = new HashMap<>();
        delivery.put("id", 841795640197381L);
        delivery.put("openOrderId", 54232322L);
        delivery.put("type", 5);
        delivery.put("content", "骑手姓名: 李骑手\r\n骑手电话: 13800138002\r\n"
                + "配送状态: 取货中\r\n订单状态: 待接单 -> 取货中");
        delivery.put("createTime", "2026-08-25 18:15:16");

        when(remoteClient.getOpenOrderLog("token", 54232322L))
                .thenReturn(java.util.Arrays.asList(cancelled, callback, delivery));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54232322L);

        assertEquals(60, tracking.getDeliverySendStatus());
        assertEquals("异常单", tracking.getDeliverySendStatusDesc());
        assertEquals("CANCELLED", tracking.getPhase());
        assertNotNull(tracking.getTrajectoryState());
        assertEquals("取货中", tracking.getTrajectoryState().getCallbackStatus());
        assertEquals("取货中", tracking.getTrajectoryState().getDeliveryStatus());
        assertEquals("取货中", tracking.getTrajectoryState().getPreviousOrderStatus());
        assertEquals("异常单", tracking.getTrajectoryState().getOrderStatus());
        assertEquals("商家取消", tracking.getTrajectoryState().getCancelReason());
        assertEquals(841795756380357L, tracking.getTrajectoryState().getLatestStatusLogId());
        assertEquals("2026-08-25 18:15:44", tracking.getTrajectoryState().getStatusUpdatedAt());
        assertEquals(841795640996101L, tracking.getRider().getLocationLogId());
        assertEquals("2026-08-25 18:15:16", tracking.getRider().getLocationUpdatedAt());
        assertEquals(22.757134184148953, tracking.getRider().getLat(), 0.0000001);
        assertEquals(112.97509773999961, tracking.getRider().getLng(), 0.0000001);
    }

    @Test
    void treatsCancellationTitleAsCancelledWithoutAStatusLine() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54232322L);
        detail.put("deliverySendStatus", 30);
        when(remoteClient.getOpenOrderDetail("token", 54232322L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 54232322L)).thenReturn(new ArrayList<>());

        Map<String, Object> cancelled = new HashMap<>();
        cancelled.put("id", 841795756380358L);
        cancelled.put("openOrderId", 54232322L);
        cancelled.put("title", "取消配送单");
        cancelled.put("content", "取消原因: 商家取消");
        when(remoteClient.getOpenOrderLog("token", 54232322L))
                .thenReturn(java.util.Collections.singletonList(cancelled));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54232322L);

        assertEquals(60, tracking.getDeliverySendStatus());
        assertEquals("CANCELLED", tracking.getPhase());
        assertEquals("商家取消", tracking.getTrajectoryState().getCancelReason());
    }

    @Test
    void ignoresPreviousDispatchCancellationWhenLatestBatchIsPickingUp() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 54384514L);
        detail.put("deliverySendStatus", 30);
        detail.put("deliverySendStatusDesc", "取货中");
        detail.put("deliveryParentOrderCode", "JH842230763496325");
        detail.put("thirdPartyOrderCode", "3749203565953626113");
        detail.put("currStatusTime", "2026-08-26 23:53:09");
        when(remoteClient.getOpenOrderDetail("token", 54384514L)).thenReturn(detail);

        Map<String, Object> currentLocation = new HashMap<>();
        currentLocation.put("id", 842232935031685L);
        currentLocation.put("openOrderId", 54384514L);
        currentLocation.put("subType", 202);
        currentLocation.put("content", "三方配送单号: 3749203565953626113\r\n"
                + "三方配送来源: 顺丰优质\r\n回传状态: 取货中\r\n"
                + "经纬度: 112.97364192515289,22.757524054967273");
        currentLocation.put("createTime", "2026-08-26 23:54:37");

        Map<String, Object> currentDispatch = new HashMap<>();
        currentDispatch.put("id", 842230766510981L);
        currentDispatch.put("openOrderId", 54384514L);
        currentDispatch.put("title", "配送下单");
        currentDispatch.put("deliveryParentOrderNo", "JH842230763496325");
        currentDispatch.put("content", "订单状态: 新订单 -> 待接单\r\n"
                + "配送单号: JH842230763496325\r\n来源: 真省钱聚合跑腿");
        currentDispatch.put("createTime", "2026-08-26 23:45:48");

        Map<String, Object> previousCancellation = new HashMap<>();
        previousCancellation.put("id", 842230763066245L);
        previousCancellation.put("openOrderId", 54384514L);
        previousCancellation.put("title", "取消配送单");
        previousCancellation.put("content", "订单状态: 待接单 -> 异常单\r\n取消原因: 超时未接单");
        previousCancellation.put("createTime", "2026-08-26 23:45:47");
        when(remoteClient.getOpenOrderLog("token", 54384514L))
                .thenReturn(java.util.Arrays.asList(
                        currentLocation, currentDispatch, previousCancellation));

        Map<String, Object> cancelledChannel = new HashMap<>();
        cancelledChannel.put("sendStatus", 60);
        cancelledChannel.put("sortNum", 257865130L);
        cancelledChannel.put("orderStatusDesc", "已取消");
        Map<String, Object> activeChannel = new HashMap<>();
        activeChannel.put("sendStatus", 30);
        activeChannel.put("sortNum", 257865129L);
        activeChannel.put("orderStatusDesc", "取货中");
        when(remoteClient.getDeliveryStatusTimeline("token", 54384514L))
                .thenReturn(java.util.Arrays.asList(cancelledChannel, activeChannel));

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 54384514L);

        assertEquals(30, tracking.getDeliverySendStatus());
        assertEquals("TO_SHOP", tracking.getPhase());
        assertEquals("取货中", tracking.getTrajectoryState().getCallbackStatus());
        assertNull(tracking.getTrajectoryState().getCancelReason());
        assertEquals(842232935031685L, tracking.getTrajectoryState().getLatestStatusLogId());
        assertNotNull(tracking.getEffectiveState());
        assertEquals(30, tracking.getEffectiveState().getSendStatus());
        assertEquals("取货中", tracking.getEffectiveState().getStatusDesc());
        assertEquals("TO_SHOP", tracking.getEffectiveState().getPhase());
        assertEquals("ORDER_LOG", tracking.getEffectiveState().getSource());
        assertEquals(842232935031685L, tracking.getEffectiveState().getEffectiveLogId());
        assertEquals("JH842230763496325", tracking.getEffectiveState().getParentOrderNo());
        assertEquals("3749203565953626113", tracking.getEffectiveState().getThirdPartyOrderNo());
        assertEquals("2026-08-26 23:54:37", tracking.getEffectiveState().getUpdatedAt());
    }

    @Test
    void convertsBd09RiderUsingShopAnchorAndUsesCanonicalLocalEndpoints() {
        ZsqProperties properties = new ZsqProperties();
        ZsqDeliveryService service = new ZsqDeliveryService(null, null, null, properties);
        ZsqRiderTrackingResponse tracking = tracking(
                39.916000, 116.404500,
                39.915166, 116.403842,
                39.920000, 116.410000);

        service.normalizeTrackingToGcj02(tracking,
                39.908823, 116.397470,
                39.910000, 116.400000);

        assertEquals("gcj02", tracking.getCoordinateType());
        assertEquals(39.908823, tracking.getShop().getLat(), 0.0000001);
        assertEquals(116.397470, tracking.getShop().getLng(), 0.0000001);
        assertEquals(39.910000, tracking.getUser().getLat(), 0.0000001);
        assertEquals(116.400000, tracking.getUser().getLng(), 0.0000001);
        assertEquals(39.9096, tracking.getRider().getLat(), 0.001);
        assertEquals(116.3981, tracking.getRider().getLng(), 0.001);
        assertNotNull(tracking.getComputedEta());
    }

    @Test
    void defaultsUndeclaredZsqPointsToBd09WithoutLocalAnchors() {
        ZsqProperties properties = new ZsqProperties();
        ZsqDeliveryService service = new ZsqDeliveryService(null, null, null, properties);
        ZsqRiderTrackingResponse tracking = tracking(
                22.771732, 112.970749,
                22.771600, 112.970500,
                22.771678, 112.970730);
        service.normalizeTrackingToGcj02(tracking, null, null, null, null);

        assertEquals("gcj02", tracking.getCoordinateType());
        assertEquals(22.7660, tracking.getRider().getLat(), 0.001);
        assertEquals(112.9642, tracking.getRider().getLng(), 0.001);
        assertEquals(22.7659, tracking.getShop().getLat(), 0.001);
        assertEquals(112.9640, tracking.getShop().getLng(), 0.001);
        assertEquals(22.7660, tracking.getUser().getLat(), 0.001);
        assertEquals(112.9642, tracking.getUser().getLng(), 0.001);
    }

    @Test
    void convertsCoordinatesNestedInDeliveryTimeline() {
        ZsqProperties properties = new ZsqProperties();
        ZsqDeliveryService service = new ZsqDeliveryService(null, null, null, properties);
        ZsqRiderTrackingResponse tracking = tracking(
                22.771732, 112.970749,
                22.771600, 112.970500,
                22.771678, 112.970730);
        tracking.setCoordinateType("bd09");
        Map<String, Object> location = new HashMap<>();
        location.put("lat", "22.771732");
        location.put("lng", "112.970749");
        Map<String, Object> node = new HashMap<>();
        node.put("location", location);
        List<Map<String, Object>> timeline = new ArrayList<>();
        timeline.add(node);
        tracking.setDeliveryTimeline(timeline);

        service.normalizeTrackingToGcj02(tracking, null, null, null, null);

        Map<?, ?> normalized = (Map<?, ?>) tracking.getDeliveryTimeline().get(0).get("location");
        assertEquals(22.7660, ((Number) normalized.get("lat")).doubleValue(), 0.001);
        assertEquals(112.9642, ((Number) normalized.get("lng")).doubleValue(), 0.001);
        assertEquals("gcj02", normalized.get("coordinateType"));
    }

    @Test
    void keepsGcj02RiderWhenRemoteShopAlreadyMatchesLocalAnchor() {
        ZsqProperties properties = new ZsqProperties();
        ZsqDeliveryService service = new ZsqDeliveryService(null, null, null, properties);
        ZsqRiderTrackingResponse tracking = tracking(
                22.579000, 113.082000,
                22.578738, 113.081901,
                22.590000, 113.090000);
        tracking.setCoordinateType("gcj02");

        service.normalizeTrackingToGcj02(tracking,
                22.578738, 113.081901,
                22.580000, 113.083000);

        assertEquals(22.579000, tracking.getRider().getLat(), 0.0000001);
        assertEquals(113.082000, tracking.getRider().getLng(), 0.0000001);
    }

    @Test
    void toleratesTrackingWithoutRiderLocation() {
        ZsqProperties properties = new ZsqProperties();
        ZsqDeliveryService service = new ZsqDeliveryService(null, null, null, properties);
        ZsqRiderTrackingResponse tracking = new ZsqRiderTrackingResponse();

        service.normalizeTrackingToGcj02(tracking,
                22.578738, 113.081901,
                22.580000, 113.083000);

        assertEquals("gcj02", tracking.getCoordinateType());
        assertNull(tracking.getComputedEta());
    }

    @Test
    void clearsIncompleteRemoteCoordinatePairs() {
        ZsqProperties properties = new ZsqProperties();
        ZsqDeliveryService service = new ZsqDeliveryService(null, null, null, properties);
        ZsqRiderTrackingResponse tracking = new ZsqRiderTrackingResponse();
        tracking.setCoordinateType("bd09");
        ZsqRiderTrackingResponse.RiderPoint rider = new ZsqRiderTrackingResponse.RiderPoint();
        rider.setLat(22.771732);
        tracking.setRider(rider);

        service.normalizeTrackingToGcj02(tracking, null, null, null, null);

        assertEquals("gcj02", tracking.getCoordinateType());
        assertNull(tracking.getRider().getLat());
        assertNull(tracking.getRider().getLng());
        assertNull(tracking.getComputedEta());
    }

    private static ZsqRiderTrackingResponse tracking(double riderLat, double riderLng,
                                                       double shopLat, double shopLng,
                                                       double userLat, double userLng) {
        ZsqRiderTrackingResponse response = new ZsqRiderTrackingResponse();
        ZsqRiderTrackingResponse.RiderPoint rider = new ZsqRiderTrackingResponse.RiderPoint();
        rider.setLat(riderLat);
        rider.setLng(riderLng);
        response.setRider(rider);
        ZsqRiderTrackingResponse.LocationPoint shop = new ZsqRiderTrackingResponse.LocationPoint();
        shop.setLat(shopLat);
        shop.setLng(shopLng);
        response.setShop(shop);
        ZsqRiderTrackingResponse.LocationPoint user = new ZsqRiderTrackingResponse.LocationPoint();
        user.setLat(userLat);
        user.setLng(userLng);
        response.setUser(user);
        return response;
    }

    @Test
    void parsesActualFeeAndSupplierFromOrderDetailJson() {
        ZsqRemoteClient remoteClient = mock(ZsqRemoteClient.class);
        Map<String, Object> detail = new HashMap<>();
        detail.put("id", 58284607L);
        detail.put("orderId", "854978713415877");
        detail.put("deliverySendStatus", 50);
        detail.put("deliverySendStatusDesc", "已完成");
        detail.put("deliveryCourierName", "王骑手");
        detail.put("deliveryCourierMobile", "13800138003");
        detail.put("deliverySupplierName", "京东特惠");
        detail.put("shopActualCost", "6.13");
        detail.put("discountLastMoney", "6.13");
        detail.put("yhpsDiscountLastMoney", "6.13");

        when(remoteClient.getOpenOrderDetail("token", 58284607L)).thenReturn(detail);
        when(remoteClient.getDeliveryStatusTimeline("token", 58284607L)).thenReturn(new ArrayList<>());
        when(remoteClient.getOpenOrderLog("token", 58284607L)).thenReturn(new ArrayList<>());

        ZsqDeliveryService service = new ZsqDeliveryService(
                remoteClient, null, null, new ZsqProperties());

        ZsqRiderTrackingResponse tracking = service.getRiderTracking("token", 58284607L);

        assertEquals(new BigDecimal("6.13"), tracking.getActualFee());
        assertEquals("京东特惠", tracking.getDeliverySupplierName());
        assertEquals("王骑手", tracking.getRider().getName());
        assertEquals("13800138003", tracking.getRider().getPhone());
    }
}
