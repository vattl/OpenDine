package com.lanf.integration.service;

import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.remote.dto.*;
import com.lanf.integration.util.ZsqShopNameMatcher;
import com.lanf.integration.util.ZsqAddressTextHelper;
import com.lanf.integration.web.dto.CreateTakeawayOrderRequest;
import com.lanf.util.CoordinateNormalizer;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.List;

@Service
public class ZsqOrderService {

    private final ZsqRemoteClient remoteClient;
    private final ZsqAuthService authService;

    public ZsqOrderService(ZsqRemoteClient remoteClient, ZsqAuthService authService) {
        this.remoteClient = remoteClient;
        this.authService = authService;
    }

    public List<ZsqShopAddress> listShops(String authorization) {
        return remoteClient.listShopAddresses(authorization);
    }

    public List<ZsqAddressTip> addressTips(String authorization, String city, String keywords) {
        return remoteClient.addressInputTips(authorization, city, keywords);
    }

    /**
     * 创建外卖订单：选店 → 地址解析 → 下单。
     */
    public ZsqCreateOrderResult createTakeawayOrder(String authorization, CreateTakeawayOrderRequest req) {
        List<ZsqShopAddress> shops = remoteClient.listShopAddresses(authorization);
        ZsqShopAddress shop = pickShop(shops, req);

        ZsqAddressTip tip = resolveAddressTip(authorization, req);
        ZsqCreateOrderPayload payload = buildPayload(shop, tip, req);
        ZsqCreateOrderResult result = remoteClient.createTakeawayOrder(authorization, payload);
        try {
            remoteClient.markAddressUsed(authorization, payload);
        } catch (Exception ignored) {
            // 非关键步骤
        }
        return result;
    }

    /**
     * 使用 application.yml 中配置的账号自动登录并下单。
     */
    public ZsqCreateOrderResult createTakeawayOrderWithConfig(CreateTakeawayOrderRequest req) {
        return authService.executeWithConfigAuth(auth -> createTakeawayOrder(auth, req));
    }

    private ZsqShopAddress pickShop(List<ZsqShopAddress> shops, CreateTakeawayOrderRequest req) {
        if (shops == null || shops.isEmpty()) {
            throw new ZsqApiException("无可用发单店铺");
        }
        Long preferredId = req.getFromAddressId();
        if (preferredId != null) {
            return shops.stream()
                    .filter(s -> preferredId.equals(s.getId()))
                    .findFirst()
                    .orElseThrow(() -> new ZsqApiException("未找到店铺 id=" + preferredId));
        }
        if (StringUtils.hasText(req.getFromAddressShopName())) {
            CoordinateNormalizer.Point shopPoint = normalizeOptionalPoint(
                    req.getFromAddressLatitude(), req.getFromAddressLongitude(),
                    req.getFromAddressCoordinateType(), "发单门店");
            ZsqShopAddress matched = ZsqShopNameMatcher.pickByShopName(
                    shops,
                    req.getFromAddressShopName().trim(),
                    shopPoint != null ? shopPoint.getLat() : null,
                    shopPoint != null ? shopPoint.getLng() : null);
            if (matched != null) {
                return matched;
            }
            throw new ZsqApiException("未找到与店名「" + req.getFromAddressShopName().trim()
                    + "」匹配的真省钱发单店铺，请核对 t_shop.name 与真省钱发单店铺名");
        }
        return shops.stream()
                .filter(s -> s.getIsDefault() != null && s.getIsDefault() == 1)
                .findFirst()
                .orElse(shops.get(0));
    }

    private ZsqCreateOrderPayload buildPayload(
            ZsqShopAddress shop, ZsqAddressTip tip, CreateTakeawayOrderRequest req) {
        ZsqCreateOrderPayload p = new ZsqCreateOrderPayload();
        p.setType(1);
        p.setFromAddressId(shop.getId());
        p.setGoodType(shop.getIndustryType() != null ? shop.getIndustryType() : 1);
        p.setToReceiverName(req.getReceiverName());
        p.setToMobile(formatMobile(req.getReceiverPhone(), req.getExtension()));
        p.setToAddress(tip.getAddress() != null ? tip.getAddress()
                : tip.getProvince() + tip.getCity() + tip.getDistrict() + tip.getName());
        p.setToAddressDetail(req.getReceiverDetail());
        p.setToLatitude(tip.getLocation().getLat());
        p.setToLongitude(tip.getLocation().getLng());
        p.setProductName(req.getProductName() != null ? req.getProductName() : "到店查看");
        p.setProductAmount(req.getProductAmount() != null ? req.getProductAmount() : "50");
        p.setProductCount(req.getProductCount() != null ? req.getProductCount() : 1);
        p.setWeight(req.getWeight() != null ? req.getWeight() : 3);
        p.setOrderRemark(req.getRemark() != null ? req.getRemark() : "");
        p.setExpectTime(req.getExpectTime() != null ? req.getExpectTime() : "");
        p.setOrderType(p.getExpectTime() != null && !p.getExpectTime().trim().isEmpty() ? 2 : 1);
        return p;
    }

    private String formatMobile(String phone, String extension) {
        if (extension != null && !extension.trim().isEmpty()) {
            return phone + "_" + extension;
        }
        return phone;
    }

    private ZsqAddressTip resolveAddressTip(String authorization, CreateTakeawayOrderRequest req) {
        if (hasValidReceiverCoords(req)) {
            return buildTipFromCoords(req);
        }
        List<ZsqAddressTip> tips = resolveAddressTips(
                authorization, req.getCityName(), req.getReceiverAddress(), req.getDistrict());
        if (tips != null && !tips.isEmpty() && tips.get(0).getLocation() != null) {
            return tips.get(0);
        }
        throw new ZsqApiException("地址解析失败: " + req.getReceiverAddress());
    }

    private List<ZsqAddressTip> resolveAddressTips(String authorization, String cityName,
                                                    String receiverAddress, String district) {
        for (String city : ZsqAddressTextHelper.cityAttempts(cityName, district)) {
            for (String kw : ZsqAddressTextHelper.keywordAttempts(receiverAddress)) {
                List<ZsqAddressTip> tips = remoteClient.addressInputTips(authorization, city, kw);
                if (tips != null && !tips.isEmpty() && tips.get(0).getLocation() != null) {
                    return tips;
                }
            }
        }
        return null;
    }

    private static boolean hasValidReceiverCoords(CreateTakeawayOrderRequest req) {
        if (req.getReceiverLatitude() == null || req.getReceiverLongitude() == null) {
            return false;
        }
        double lat = req.getReceiverLatitude();
        double lng = req.getReceiverLongitude();
        return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(lat == 0 && lng == 0);
    }

    private static ZsqAddressTip buildTipFromCoords(CreateTakeawayOrderRequest req) {
        // 真省钱 open-order / delivery boundary uses Baidu BD-09 (coordinateType=1).
        CoordinateNormalizer.Point point = CoordinateNormalizer.toBd09(
                req.getReceiverLatitude(), req.getReceiverLongitude(), req.getReceiverCoordinateType());
        ZsqAddressTip tip = new ZsqAddressTip();
        ZsqAddressTip.ZsqLocation loc = new ZsqAddressTip.ZsqLocation();
        loc.setLat(CoordinateNormalizer.decimal(point.getLat()).toPlainString());
        loc.setLng(CoordinateNormalizer.decimal(point.getLng()).toPlainString());
        tip.setLocation(loc);
        String addr = req.getReceiverAddress();
        tip.setAddress(StringUtils.hasText(addr) ? addr : "收货地址");
        tip.setName(StringUtils.hasText(addr) && addr.length() > 32 ? addr.substring(0, 32) : addr);
        if (StringUtils.hasText(req.getCityName())) {
            tip.setCity(req.getCityName());
        }
        return tip;
    }

    private static CoordinateNormalizer.Point normalizeOptionalPoint(Double lat, Double lng, String coordinateType,
                                                                      String label) {
        if (lat == null && lng == null) {
            return null;
        }
        if (lat == null || lng == null) {
            throw new IllegalArgumentException(label + "经纬度必须同时提供");
        }
        return CoordinateNormalizer.toGcj02(lat, lng, coordinateType);
    }
}
