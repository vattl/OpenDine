package com.lanf.integration.remote.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** 对应真省钱 POST /open/order/create */
@JsonIgnoreProperties(ignoreUnknown = true)
public class ZsqCreateOrderPayload {

    private int type = 1;
    private String expectTime = "";
    private Long fromAddressId;
    private int goodType = 1;
    private String orderRemark = "";
    private int orderType = 1;
    private String productAmount;
    private int productCount = 1;
    private String productName = "到店查看";
    private String toAddress;
    private String toAddressDetail;
    private String toLatitude;
    private String toLongitude;
    private String toMobile;
    private String toReceiverName;
    private int weight = 3;

    public int getType() {
        return type;
    }

    public void setType(int type) {
        this.type = type;
    }

    public String getExpectTime() {
        return expectTime;
    }

    public void setExpectTime(String expectTime) {
        this.expectTime = expectTime;
    }

    public Long getFromAddressId() {
        return fromAddressId;
    }

    public void setFromAddressId(Long fromAddressId) {
        this.fromAddressId = fromAddressId;
    }

    public int getGoodType() {
        return goodType;
    }

    public void setGoodType(int goodType) {
        this.goodType = goodType;
    }

    public String getOrderRemark() {
        return orderRemark;
    }

    public void setOrderRemark(String orderRemark) {
        this.orderRemark = orderRemark;
    }

    public int getOrderType() {
        return orderType;
    }

    public void setOrderType(int orderType) {
        this.orderType = orderType;
    }

    public String getProductAmount() {
        return productAmount;
    }

    public void setProductAmount(String productAmount) {
        this.productAmount = productAmount;
    }

    public int getProductCount() {
        return productCount;
    }

    public void setProductCount(int productCount) {
        this.productCount = productCount;
    }

    public String getProductName() {
        return productName;
    }

    public void setProductName(String productName) {
        this.productName = productName;
    }

    public String getToAddress() {
        return toAddress;
    }

    public void setToAddress(String toAddress) {
        this.toAddress = toAddress;
    }

    public String getToAddressDetail() {
        return toAddressDetail;
    }

    public void setToAddressDetail(String toAddressDetail) {
        this.toAddressDetail = toAddressDetail;
    }

    public String getToLatitude() {
        return toLatitude;
    }

    public void setToLatitude(String toLatitude) {
        this.toLatitude = toLatitude;
    }

    public String getToLongitude() {
        return toLongitude;
    }

    public void setToLongitude(String toLongitude) {
        this.toLongitude = toLongitude;
    }

    public String getToMobile() {
        return toMobile;
    }

    public void setToMobile(String toMobile) {
        this.toMobile = toMobile;
    }

    public String getToReceiverName() {
        return toReceiverName;
    }

    public void setToReceiverName(String toReceiverName) {
        this.toReceiverName = toReceiverName;
    }

    public int getWeight() {
        return weight;
    }

    public void setWeight(int weight) {
        this.weight = weight;
    }
}
