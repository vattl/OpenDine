package com.lanf.integration.remote.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** 配送询价结果项，对应 POST /delivery/order/billing 的 data 数组元素。 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class ZsqDeliveryBillingChannel {

    private Integer status;
    private String errorMsg;
    private Integer deliveryCode;
    private Integer deliveryType;
    private String deliveryChannelName;
    private String estimateMoney;
    private String distance;
    private Integer isSupportInsurance;

    public Integer getStatus() {
        return status;
    }

    public void setStatus(Integer status) {
        this.status = status;
    }

    public String getErrorMsg() {
        return errorMsg;
    }

    public void setErrorMsg(String errorMsg) {
        this.errorMsg = errorMsg;
    }

    public Integer getDeliveryCode() {
        return deliveryCode;
    }

    public void setDeliveryCode(Integer deliveryCode) {
        this.deliveryCode = deliveryCode;
    }

    public Integer getDeliveryType() {
        return deliveryType;
    }

    public void setDeliveryType(Integer deliveryType) {
        this.deliveryType = deliveryType;
    }

    public String getDeliveryChannelName() {
        return deliveryChannelName;
    }

    public void setDeliveryChannelName(String deliveryChannelName) {
        this.deliveryChannelName = deliveryChannelName;
    }

    public String getEstimateMoney() {
        return estimateMoney;
    }

    public void setEstimateMoney(String estimateMoney) {
        this.estimateMoney = estimateMoney;
    }

    public String getDistance() {
        return distance;
    }

    public void setDistance(String distance) {
        this.distance = distance;
    }

    public Integer getIsSupportInsurance() {
        return isSupportInsurance;
    }

    public void setIsSupportInsurance(Integer isSupportInsurance) {
        this.isSupportInsurance = isSupportInsurance;
    }

    public boolean isAvailable() {
        return status != null && status == 1;
    }
}
