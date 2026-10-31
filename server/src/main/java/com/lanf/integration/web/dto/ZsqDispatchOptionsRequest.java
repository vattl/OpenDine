package com.lanf.integration.web.dto;

/**
 * 一键下单（保存并发配送）可选参数，可嵌在创建订单请求同体或单独传。
 */
public class ZsqDispatchOptionsRequest {

    /** 1=同时叫单（默认），2=依次叫单 */
    private String callOrderType = "1";

    /** 自动选择的配送渠道数量（按价格从低到高），默认 1 */
    private Integer channelCount = 1;

    /** 指定配送渠道 deliveryCode；若为空则自动选最便宜可用渠道 */
    private Integer deliveryCode;

    public String getCallOrderType() {
        return callOrderType;
    }

    public void setCallOrderType(String callOrderType) {
        this.callOrderType = callOrderType;
    }

    public Integer getChannelCount() {
        return channelCount;
    }

    public void setChannelCount(Integer channelCount) {
        this.channelCount = channelCount;
    }

    public Integer getDeliveryCode() {
        return deliveryCode;
    }

    public void setDeliveryCode(Integer deliveryCode) {
        this.deliveryCode = deliveryCode;
    }
}
