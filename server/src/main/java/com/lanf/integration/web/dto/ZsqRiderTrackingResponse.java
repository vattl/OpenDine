package com.lanf.integration.web.dto;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * 骑手实时定位与 ETA，供前端展示「距商家/距用户还有多久」。
 */
public class ZsqRiderTrackingResponse {

    private Long openOrderId;
    private String orderId;
    private Integer deliverySendStatus;
    private String deliverySendStatusDesc;
    /** WAITING_RIDER | TO_SHOP | TO_USER | DELIVERED | CANCELLED | ORDER_MISSING | UNKNOWN */
    private String phase;
    /** gcj02 after business-layer normalization; zsq_raw on the low-level adapter endpoint. */
    private String coordinateType;
    private RiderPoint rider;
    private LocationPoint shop;
    private LocationPoint user;
    /** 真省钱平台返回的文案（如有） */
    private PlatformEta platformEta;
    /** 基于经纬度 + 配置速度估算的 ETA */
    private ComputedEta computedEta;
    private List<Map<String, Object>> deliveryTimeline;
    /** 真省钱 /open/order/log 返回的操作日志；兼容结构化渠道日志。 */
    private List<Map<String, Object>> orderLogs;
    /** 从订单轨迹分别提取的核心状态，避免将不同语义的状态折叠丢失。 */
    private TrajectoryState trajectoryState;
    /** 后端解析出的当前配送批次权威状态；前端应优先使用，禁止从原始时间线自行推断。 */
    private EffectiveState effectiveState;

    /** 真省钱实际跑腿费用（元），来自 shopActualCost/discountLastMoney */
    private BigDecimal actualFee;
    /** 真省钱实际配送运力渠道（如京东特惠、美团等），来自 deliverySupplierName */
    private String deliverySupplierName;

    /** 本系统履约状态（同步自 t_takeout_delivery.dispatch_status） */
    private String dispatchStatus;
    /** 真省钱发配送状态（同步自 t_takeout_delivery.zsq_dispatch_status） */
    private String zsqDispatchStatus;

    public static class RiderPoint {
        private String name;
        private String phone;
        private Double lat;
        private Double lng;
        /** 提供当前骑手坐标的订单轨迹 ID。 */
        private Long locationLogId;
        /** 提供当前骑手坐标的订单轨迹时间。 */
        private String locationUpdatedAt;

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }

        public String getPhone() {
            return phone;
        }

        public void setPhone(String phone) {
            this.phone = phone;
        }

        public Double getLat() {
            return lat;
        }

        public void setLat(Double lat) {
            this.lat = lat;
        }

        public Double getLng() {
            return lng;
        }

        public void setLng(Double lng) {
            this.lng = lng;
        }

        public Long getLocationLogId() {
            return locationLogId;
        }

        public void setLocationLogId(Long locationLogId) {
            this.locationLogId = locationLogId;
        }

        public String getLocationUpdatedAt() {
            return locationUpdatedAt;
        }

        public void setLocationUpdatedAt(String locationUpdatedAt) {
            this.locationUpdatedAt = locationUpdatedAt;
        }
    }

    public static class TrajectoryState {
        private String callbackStatus;
        private String orderStatus;
        private String previousOrderStatus;
        private String deliveryStatus;
        private String cancelReason;
        private Long latestStatusLogId;
        private String statusUpdatedAt;

        public String getCallbackStatus() {
            return callbackStatus;
        }

        public void setCallbackStatus(String callbackStatus) {
            this.callbackStatus = callbackStatus;
        }

        public String getOrderStatus() {
            return orderStatus;
        }

        public void setOrderStatus(String orderStatus) {
            this.orderStatus = orderStatus;
        }

        public String getPreviousOrderStatus() {
            return previousOrderStatus;
        }

        public void setPreviousOrderStatus(String previousOrderStatus) {
            this.previousOrderStatus = previousOrderStatus;
        }

        public String getDeliveryStatus() {
            return deliveryStatus;
        }

        public void setDeliveryStatus(String deliveryStatus) {
            this.deliveryStatus = deliveryStatus;
        }

        public String getCancelReason() {
            return cancelReason;
        }

        public void setCancelReason(String cancelReason) {
            this.cancelReason = cancelReason;
        }

        public Long getLatestStatusLogId() {
            return latestStatusLogId;
        }

        public void setLatestStatusLogId(Long latestStatusLogId) {
            this.latestStatusLogId = latestStatusLogId;
        }

        public String getStatusUpdatedAt() {
            return statusUpdatedAt;
        }

        public void setStatusUpdatedAt(String statusUpdatedAt) {
            this.statusUpdatedAt = statusUpdatedAt;
        }
    }

    public static class EffectiveState {
        private Integer sendStatus;
        private String statusDesc;
        private String phase;
        /** ORDER_LOG | ORDER_DETAIL */
        private String source;
        private Long effectiveLogId;
        private String parentOrderNo;
        private String thirdPartyOrderNo;
        private String updatedAt;

        public Integer getSendStatus() {
            return sendStatus;
        }

        public void setSendStatus(Integer sendStatus) {
            this.sendStatus = sendStatus;
        }

        public String getStatusDesc() {
            return statusDesc;
        }

        public void setStatusDesc(String statusDesc) {
            this.statusDesc = statusDesc;
        }

        public String getPhase() {
            return phase;
        }

        public void setPhase(String phase) {
            this.phase = phase;
        }

        public String getSource() {
            return source;
        }

        public void setSource(String source) {
            this.source = source;
        }

        public Long getEffectiveLogId() {
            return effectiveLogId;
        }

        public void setEffectiveLogId(Long effectiveLogId) {
            this.effectiveLogId = effectiveLogId;
        }

        public String getParentOrderNo() {
            return parentOrderNo;
        }

        public void setParentOrderNo(String parentOrderNo) {
            this.parentOrderNo = parentOrderNo;
        }

        public String getThirdPartyOrderNo() {
            return thirdPartyOrderNo;
        }

        public void setThirdPartyOrderNo(String thirdPartyOrderNo) {
            this.thirdPartyOrderNo = thirdPartyOrderNo;
        }

        public String getUpdatedAt() {
            return updatedAt;
        }

        public void setUpdatedAt(String updatedAt) {
            this.updatedAt = updatedAt;
        }
    }

    public static class LocationPoint {
        private Double lat;
        private Double lng;
        private String address;
        private String addressDetail;

        public Double getLat() {
            return lat;
        }

        public void setLat(Double lat) {
            this.lat = lat;
        }

        public Double getLng() {
            return lng;
        }

        public void setLng(Double lng) {
            this.lng = lng;
        }

        public String getAddress() {
            return address;
        }

        public void setAddress(String address) {
            this.address = address;
        }

        public String getAddressDetail() {
            return addressDetail;
        }

        public void setAddressDetail(String addressDetail) {
            this.addressDetail = addressDetail;
        }
    }

    public static class PlatformEta {
        private String distanceText;
        private String durationText;
        private String description;

        public String getDistanceText() {
            return distanceText;
        }

        public void setDistanceText(String distanceText) {
            this.distanceText = distanceText;
        }

        public String getDurationText() {
            return durationText;
        }

        public void setDurationText(String durationText) {
            this.durationText = durationText;
        }

        public String getDescription() {
            return description;
        }

        public void setDescription(String description) {
            this.description = description;
        }
    }

    public static class ComputedEta {
        private Double riderToShopKm;
        private Double riderToUserKm;
        private Integer toShopMinutes;
        private Integer toUserMinutes;
        private Double speedKmh;

        public Double getRiderToShopKm() {
            return riderToShopKm;
        }

        public void setRiderToShopKm(Double riderToShopKm) {
            this.riderToShopKm = riderToShopKm;
        }

        public Double getRiderToUserKm() {
            return riderToUserKm;
        }

        public void setRiderToUserKm(Double riderToUserKm) {
            this.riderToUserKm = riderToUserKm;
        }

        public Integer getToShopMinutes() {
            return toShopMinutes;
        }

        public void setToShopMinutes(Integer toShopMinutes) {
            this.toShopMinutes = toShopMinutes;
        }

        public Integer getToUserMinutes() {
            return toUserMinutes;
        }

        public void setToUserMinutes(Integer toUserMinutes) {
            this.toUserMinutes = toUserMinutes;
        }

        public Double getSpeedKmh() {
            return speedKmh;
        }

        public void setSpeedKmh(Double speedKmh) {
            this.speedKmh = speedKmh;
        }
    }

    public Long getOpenOrderId() {
        return openOrderId;
    }

    public void setOpenOrderId(Long openOrderId) {
        this.openOrderId = openOrderId;
    }

    public String getOrderId() {
        return orderId;
    }

    public void setOrderId(String orderId) {
        this.orderId = orderId;
    }

    public Integer getDeliverySendStatus() {
        return deliverySendStatus;
    }

    public void setDeliverySendStatus(Integer deliverySendStatus) {
        this.deliverySendStatus = deliverySendStatus;
    }

    public String getDeliverySendStatusDesc() {
        return deliverySendStatusDesc;
    }

    public void setDeliverySendStatusDesc(String deliverySendStatusDesc) {
        this.deliverySendStatusDesc = deliverySendStatusDesc;
    }

    public String getPhase() {
        return phase;
    }

    public void setPhase(String phase) {
        this.phase = phase;
    }

    public String getCoordinateType() {
        return coordinateType;
    }

    public void setCoordinateType(String coordinateType) {
        this.coordinateType = coordinateType;
    }

    public RiderPoint getRider() {
        return rider;
    }

    public void setRider(RiderPoint rider) {
        this.rider = rider;
    }

    public LocationPoint getShop() {
        return shop;
    }

    public void setShop(LocationPoint shop) {
        this.shop = shop;
    }

    public LocationPoint getUser() {
        return user;
    }

    public void setUser(LocationPoint user) {
        this.user = user;
    }

    public PlatformEta getPlatformEta() {
        return platformEta;
    }

    public void setPlatformEta(PlatformEta platformEta) {
        this.platformEta = platformEta;
    }

    public ComputedEta getComputedEta() {
        return computedEta;
    }

    public void setComputedEta(ComputedEta computedEta) {
        this.computedEta = computedEta;
    }

    public List<Map<String, Object>> getDeliveryTimeline() {
        return deliveryTimeline;
    }

    public void setDeliveryTimeline(List<Map<String, Object>> deliveryTimeline) {
        this.deliveryTimeline = deliveryTimeline;
    }

    public List<Map<String, Object>> getOrderLogs() {
        return orderLogs;
    }

    public void setOrderLogs(List<Map<String, Object>> orderLogs) {
        this.orderLogs = orderLogs;
    }

    public TrajectoryState getTrajectoryState() {
        return trajectoryState;
    }

    public void setTrajectoryState(TrajectoryState trajectoryState) {
        this.trajectoryState = trajectoryState;
    }

    public EffectiveState getEffectiveState() {
        return effectiveState;
    }

    public void setEffectiveState(EffectiveState effectiveState) {
        this.effectiveState = effectiveState;
    }

    public String getDispatchStatus() {
        return dispatchStatus;
    }

    public void setDispatchStatus(String dispatchStatus) {
        this.dispatchStatus = dispatchStatus;
    }

    public String getZsqDispatchStatus() {
        return zsqDispatchStatus;
    }

    public void setZsqDispatchStatus(String zsqDispatchStatus) {
        this.zsqDispatchStatus = zsqDispatchStatus;
    }

    public BigDecimal getActualFee() {
        return actualFee;
    }

    public void setActualFee(BigDecimal actualFee) {
        this.actualFee = actualFee;
    }

    public String getDeliverySupplierName() {
        return deliverySupplierName;
    }

    public void setDeliverySupplierName(String deliverySupplierName) {
        this.deliverySupplierName = deliverySupplierName;
    }
}
