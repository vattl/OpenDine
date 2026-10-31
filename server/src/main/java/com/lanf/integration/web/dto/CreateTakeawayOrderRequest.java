package com.lanf.integration.web.dto;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.Pattern;

/**
 * 你方服务器对外接口入参（创建外卖订单）。
 */
public class CreateTakeawayOrderRequest {

    /** 发单店铺 ID；配置后优先于店名匹配 */
    private Long fromAddressId;

    /** 本系统门店中文名，用于与真省钱发单店铺 shopName 匹配（无 fromAddressId 时） */
    private String fromAddressShopName;

    /** 本系统门店纬度，与 fromAddressShopName 一并用于 50 米内定位校验 */
    private Double fromAddressLatitude;

    /** 本系统门店经度，与 fromAddressShopName 一并用于 50 米内定位校验 */
    private Double fromAddressLongitude;

    /** fromAddress 坐标来源；默认 gcj02，可传 wgs84 / bd09，由服务端统一转换。 */
    private String fromAddressCoordinateType = "gcj02";

    @NotBlank(message = "收货人不能为空")
    private String receiverName;

    @NotBlank(message = "收货手机号不能为空")
    @Pattern(regexp = "^1\\d{10}$", message = "手机号格式不正确")
    private String receiverPhone;

    private String extension;

    @NotBlank(message = "地址关键词不能为空")
    private String receiverAddress;

    @NotBlank(message = "门牌号不能为空")
    private String receiverDetail;

    @NotBlank(message = "城市不能为空")
    private String cityName = "江门市";

    /** 小程序选点纬度；有值且 tips 解析失败时直接用于发单 */
    private Double receiverLatitude;

    /** 小程序选点经度；有值且 tips 解析失败时直接用于发单 */
    private Double receiverLongitude;

    /** 收货坐标来源；默认 gcj02，可传 wgs84 / bd09，由服务端统一转换。 */
    private String receiverCoordinateType = "gcj02";

    /** 区县，用于推断城市与缩短 keywords */
    private String district;

    private String productName = "到店查看";
    private String productAmount = "50";
    private Integer productCount = 1;
    private Integer weight = 3;
    private String remark = "";
    /** 预约时间 yyyy-MM-dd HH:mm:ss，空=立即送达 */
    private String expectTime = "";

    public Long getFromAddressId() {
        return fromAddressId;
    }

    public void setFromAddressId(Long fromAddressId) {
        this.fromAddressId = fromAddressId;
    }

    public String getFromAddressShopName() {
        return fromAddressShopName;
    }

    public void setFromAddressShopName(String fromAddressShopName) {
        this.fromAddressShopName = fromAddressShopName;
    }

    public Double getFromAddressLatitude() {
        return fromAddressLatitude;
    }

    public void setFromAddressLatitude(Double fromAddressLatitude) {
        this.fromAddressLatitude = fromAddressLatitude;
    }

    public Double getFromAddressLongitude() {
        return fromAddressLongitude;
    }

    public void setFromAddressLongitude(Double fromAddressLongitude) {
        this.fromAddressLongitude = fromAddressLongitude;
    }

    public String getFromAddressCoordinateType() {
        return fromAddressCoordinateType;
    }

    public void setFromAddressCoordinateType(String fromAddressCoordinateType) {
        this.fromAddressCoordinateType = fromAddressCoordinateType;
    }

    public String getReceiverName() {
        return receiverName;
    }

    public void setReceiverName(String receiverName) {
        this.receiverName = receiverName;
    }

    public String getReceiverPhone() {
        return receiverPhone;
    }

    public void setReceiverPhone(String receiverPhone) {
        this.receiverPhone = receiverPhone;
    }

    public String getExtension() {
        return extension;
    }

    public void setExtension(String extension) {
        this.extension = extension;
    }

    public String getReceiverAddress() {
        return receiverAddress;
    }

    public void setReceiverAddress(String receiverAddress) {
        this.receiverAddress = receiverAddress;
    }

    public String getReceiverDetail() {
        return receiverDetail;
    }

    public void setReceiverDetail(String receiverDetail) {
        this.receiverDetail = receiverDetail;
    }

    public String getCityName() {
        return cityName;
    }

    public void setCityName(String cityName) {
        this.cityName = cityName;
    }

    public Double getReceiverLatitude() {
        return receiverLatitude;
    }

    public void setReceiverLatitude(Double receiverLatitude) {
        this.receiverLatitude = receiverLatitude;
    }

    public Double getReceiverLongitude() {
        return receiverLongitude;
    }

    public void setReceiverLongitude(Double receiverLongitude) {
        this.receiverLongitude = receiverLongitude;
    }

    public String getReceiverCoordinateType() {
        return receiverCoordinateType;
    }

    public void setReceiverCoordinateType(String receiverCoordinateType) {
        this.receiverCoordinateType = receiverCoordinateType;
    }

    public String getDistrict() {
        return district;
    }

    public void setDistrict(String district) {
        this.district = district;
    }

    public String getProductName() {
        return productName;
    }

    public void setProductName(String productName) {
        this.productName = productName;
    }

    public String getProductAmount() {
        return productAmount;
    }

    public void setProductAmount(String productAmount) {
        this.productAmount = productAmount;
    }

    public Integer getProductCount() {
        return productCount;
    }

    public void setProductCount(Integer productCount) {
        this.productCount = productCount;
    }

    public Integer getWeight() {
        return weight;
    }

    public void setWeight(Integer weight) {
        this.weight = weight;
    }

    public String getRemark() {
        return remark;
    }

    public void setRemark(String remark) {
        this.remark = remark;
    }

    public String getExpectTime() {
        return expectTime;
    }

    public void setExpectTime(String expectTime) {
        this.expectTime = expectTime;
    }
}
