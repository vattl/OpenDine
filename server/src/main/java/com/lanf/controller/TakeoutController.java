package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.dto.OrderDTO;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.entity.ShopTakeoutConfig;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.entity.UserAddress;
import com.lanf.util.OrderPackagingFeeCalculator;
import com.lanf.util.TakeoutDeliveryFeeCalculator;
import com.lanf.util.TakeoutDistanceResolver;
import com.lanf.util.CoordinateNormalizer;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopTakeoutConfigService;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.integration.web.dto.ZsqRiderTrackingResponse;
import com.lanf.integration.exception.ZsqRemoteOrderMissingException;
import com.lanf.service.ITakeoutDeliveryService;
import com.lanf.service.ITakeoutZsqIntegrationService;
import com.lanf.service.IUserAddressService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopChainSupport;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.*;

/**
 * 小程序外卖：门店配置、地址、计价预览、创建订单（写 t_order + t_takeout_delivery）。
 */
@RestController
@RequestMapping("/order/takeout")
public class TakeoutController {

    @Autowired
    private OrderController orderController;
    @Autowired
    private IOrderService orderService;
    @Autowired
    private IUserAddressService userAddressService;
    @Autowired
    private IShopTakeoutConfigService shopTakeoutConfigService;
    @Autowired
    private ITakeoutDeliveryService takeoutDeliveryService;
    @Autowired
    private IShopService shopService;
    @Autowired
    private TakeoutDistanceResolver takeoutDistanceResolver;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private ITakeoutZsqIntegrationService takeoutZsqIntegrationService;
    private Integer resolveChainShop(HttpServletRequest request, Integer bodyShopId, String bodyShopCode) {
        return ShopChainSupport.resolveShopChain(request, bodyShopId, bodyShopCode,
                shopService::requireActiveShopIdByCode);
    }

    private static Integer shopIdOrDefault(Integer shopId) {
        return shopId != null ? shopId : 1;
    }

    private static double sumGoodsRaw(List<OrderDetail> goods) {
        if (goods == null) {
            return 0d;
        }
        double s = 0d;
        for (OrderDetail od : goods) {
            if (od != null && od.getTotal_price() != null) {
                s += od.getTotal_price();
            }
        }
        return Math.round(s * 100) / 100.0;
    }

    private static String buildFullAddress(UserAddress a) {
        StringBuilder sb = new StringBuilder();
        if (StringUtils.hasText(a.getProvince())) {
            sb.append(a.getProvince().trim());
        }
        if (StringUtils.hasText(a.getCity())) {
            sb.append(a.getCity().trim());
        }
        if (StringUtils.hasText(a.getDistrict())) {
            sb.append(a.getDistrict().trim());
        }
        if (StringUtils.hasText(a.getDetail_address())) {
            sb.append(a.getDetail_address().trim());
        }
        return sb.toString();
    }

    /**
     * 当前门店外卖配置（未配置行时返回 enabled=0 的默认对象）。
     */
    @GetMapping("/config")
    public R config(@RequestParam(required = false) Integer shop_id,
                    HttpServletRequest request) {
        Integer sid = shop_id != null && shop_id > 0 ? shop_id : shopIdOrDefault(resolveChainShop(request, null, null));
        ShopTakeoutConfig c = shopTakeoutConfigService.resolveForShop(sid);
        return R.ok().put("config", c);
    }

    /**
     * 预览配送费与应付商品小计校验（不含优惠券重算）。
     * 请求体：shop_id 可选；goods_subtotal 或 goods_list；address_id + openid（或 lng/lat）用于按距离计费。
     */
    @PostMapping("/preview")
    public R preview(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        try {
            Integer bodyShop = ShopChainSupport.parseBodyShopId(body != null ? body.get("shop_id") : null);
            String bodyCode = ShopChainSupport.parseBodyShopCode(body != null ? body.get("shop_code") : null);
            Integer sid = shopIdOrDefault(resolveChainShop(request, bodyShop, bodyCode));
            ShopTakeoutConfig cfg = shopTakeoutConfigService.resolveForShop(sid);
            double goods = resolveGoodsSubtotal(body);
            UserAddress addr = resolvePreviewAddress(body);
            Shop shop = shopService.getById(sid);
            return buildPreviewResponse(sid, cfg, shop, addr, goods);
        } catch (Exception e) {
            return R.error("预览失败：" + e.getMessage());
        }
    }

    private double resolveGoodsSubtotal(Map<String, Object> body) {
        if (body != null && body.get("goods_list") instanceof List) {
            List<?> raw = (List<?>) body.get("goods_list");
            List<OrderDetail> gl = objectMapper.convertValue(raw,
                    objectMapper.getTypeFactory().constructCollectionType(List.class, OrderDetail.class));
            return sumGoodsRaw(gl);
        }
        if (body != null && body.get("goods_subtotal") != null) {
            return Double.parseDouble(body.get("goods_subtotal").toString());
        }
        return 0d;
    }

    private UserAddress resolvePreviewAddress(Map<String, Object> body) {
        if (body == null) {
            return null;
        }
        Long addressId = parseLong(first(body, "address_id", "addressId"));
        String openid = body.get("openid") != null ? body.get("openid").toString().trim() : null;
        if (addressId != null && StringUtils.hasText(openid)) {
            return userAddressService.getByIdAndOpenid(addressId, openid);
        }
        Object lng = first(body, "lng", "longitude");
        Object lat = first(body, "lat", "latitude");
        if (lng == null || lat == null) {
            return null;
        }
        UserAddress a = new UserAddress();
        String coordinateType = first(body, "coordinate_type", "coordinateType", "coord_type", "coordType") != null
                ? first(body, "coordinate_type", "coordinateType", "coord_type", "coordType").toString() : null;
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                Double.parseDouble(lat.toString()), Double.parseDouble(lng.toString()), coordinateType);
        a.setLng(CoordinateNormalizer.decimal(point.getLng()));
        a.setLat(CoordinateNormalizer.decimal(point.getLat()));
        a.setCoordinate_type(CoordinateNormalizer.GCJ02);
        return a;
    }

    private R buildPreviewResponse(int sid, ShopTakeoutConfig cfg, Shop shop, UserAddress addr, double goods) {
        TakeoutDeliveryFeeCalculator.Quote quote =
                TakeoutDeliveryFeeCalculator.quote(cfg, shop, addr, goods, takeoutDistanceResolver);
        boolean okMin = cfg.getMin_order_amount() == null
                || BigDecimal.valueOf(goods).compareTo(cfg.getMin_order_amount()) >= 0;
        double packagingFee = OrderPackagingFeeCalculator.calcYuan(goods);
        double delivery = quote.deliveryFee.doubleValue();
        double settPreview = OrderPackagingFeeCalculator.roundMoney(goods + packagingFee + delivery);
        R r = R.ok()
                .put("shop_id", sid)
                .put("enabled", cfg.getEnabled())
                .put("goods_subtotal", goods)
                .put("packaging_fee", packagingFee)
                .put("sett_amount_preview", settPreview)
                .put("delivery_fee", delivery)
                .put("meet_min_order", okMin)
                .put("min_order_amount", cfg.getMin_order_amount())
                .put("free_delivery_threshold", cfg.getFree_delivery_threshold())
                .put("free_delivery_max_distance_km", cfg.getFree_delivery_max_distance_km())
                .put("max_delivery_distance_km", cfg.getMax_delivery_distance_km())
                .put("delivery_fee_tiers", TakeoutDeliveryFeeCalculator.parseTiers(cfg))
                .put("lead_time_minutes", cfg.getLead_time_minutes())
                .put("distance_km", quote.distanceKm > 0 ? quote.distanceKm : null)
                .put("distance_method", quote.distanceMethod)
                .put("free_delivery", quote.freeDelivery)
                .put("deliverable", quote.deliverable);
        if (quote.message != null) {
            r.put("pricing_hint", quote.message);
        } else if (addr == null) {
            r.put("pricing_hint", "请传 address_id 与 openid，或 lng/lat，以按配送距离计费");
        }
        return r;
    }

    @GetMapping("/address/list")
    public R addressList(@RequestParam String openid) {
        if (!StringUtils.hasText(openid)) {
            return R.error("openid不能为空");
        }
        return R.ok().put("list", userAddressService.listByOpenid(openid.trim()));
    }

    @PostMapping("/address/save")
    public R addressSave(@RequestBody UserAddress row) {
        if (row == null || !StringUtils.hasText(row.getOpenid())) {
            return R.error("openid不能为空");
        }
        try {
            if (!userAddressService.saveOrUpdateForUser(row)) {
                return R.error("保存失败，请检查联系人、电话与详细地址");
            }
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
        return R.ok().put("id", row.getId()).put("coordinate_type", CoordinateNormalizer.GCJ02)
                .put("lng", row.getLng()).put("lat", row.getLat());
    }

    @PostMapping("/address/delete")
    public R addressDelete(@RequestBody Map<String, Object> body) {
        Long id = parseLong(body != null ? body.get("id") : null);
        String openid = body != null && body.get("openid") != null ? body.get("openid").toString().trim() : null;
        if (id == null || !StringUtils.hasText(openid)) {
            return R.error("id 与 openid 不能为空");
        }
        if (!userAddressService.removeByIdAndOpenid(id, openid)) {
            return R.error("删除失败或无权限");
        }
        return R.ok();
    }

    @PostMapping("/address/setDefault")
    public R addressSetDefault(@RequestBody Map<String, Object> body) {
        Long id = parseLong(body != null ? body.get("id") : null);
        String openid = body != null && body.get("openid") != null ? body.get("openid").toString().trim() : null;
        if (id == null || !StringUtils.hasText(openid)) {
            return R.error("id 与 openid 不能为空");
        }
        if (!userAddressService.setDefault(id, openid)) {
            return R.error("设置失败或无权限");
        }
        return R.ok();
    }

    /**
     * 创建外卖订单：请求体在标准 {@link OrderDTO} 字段基础上增加 address_id（或 addressId），
     * 且 dineInOrTakeOut 应为「外卖」（可不传，后端会强制为外卖）。
     * 商品小计须满足门店起送价；sett_amount 将写入「商品小计 + 打包费 + 配送费」。
     */
    @PostMapping("/create")
    @Transactional(rollbackFor = Exception.class)
    public R createTakeout(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        try {
            if (body == null) {
                return R.error("请求体不能为空");
            }
            Long addressId = parseLong(first(body, "address_id", "addressId"));
            if (addressId == null) {
                return R.error("address_id 不能为空");
            }
            Map<String, Object> orderMap = new LinkedHashMap<>(body);
            orderMap.remove("address_id");
            orderMap.remove("addressId");
            orderMap.remove("code");
            orderMap.remove("wx_code");
            orderMap.remove("wxCode");
            OrderDTO dto = objectMapper.convertValue(orderMap, OrderDTO.class);
            Object authenticatedIdentity = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
            String openid = authenticatedIdentity != null ? authenticatedIdentity.toString().trim() : null;
            if (!StringUtils.hasText(openid)) {
                return R.error(401, "用户登录已过期，请重新登录");
            }
            if (dto == null) {
                return R.error("请求体无效");
            }
            dto.setOpenid(openid);
            if (dto.getGoods_list() == null || dto.getGoods_list().isEmpty()) {
                return R.error("goods_list不能为空");
            }
            UserAddress addr = userAddressService.getByIdAndOpenid(addressId, openid);
            if (addr == null) {
                return R.error("地址不存在或不属于当前用户");
            }
            Integer bodyShop = ShopChainSupport.parseBodyShopId(dto.getShop_id());
            String bodyCode = ShopChainSupport.parseBodyShopCode(dto.getShop_code());
            Integer sid = shopIdOrDefault(resolveChainShop(request, bodyShop, bodyCode));
            dto.setShop_id(sid);
            ShopTakeoutConfig cfg = shopTakeoutConfigService.resolveForShop(sid);
            if (cfg.getEnabled() == null || cfg.getEnabled() != 1) {
                return R.error("该门店未开启外卖");
            }
            double goods = sumGoodsRaw(dto.getGoods_list());
            if (cfg.getMin_order_amount() != null
                    && BigDecimal.valueOf(goods).compareTo(cfg.getMin_order_amount()) < 0) {
                return R.error("未达起送价（满 " + cfg.getMin_order_amount().stripTrailingZeros().toPlainString() + " 元起送）");
            }
            Shop shop = shopService.getById(sid);
            TakeoutDeliveryFeeCalculator.Quote quote =
                    TakeoutDeliveryFeeCalculator.quote(cfg, shop, addr, goods, takeoutDistanceResolver);
            if (!quote.deliverable) {
                return R.error(quote.message != null ? quote.message : "当前地址不可配送");
            }
            BigDecimal deliveryBd = quote.deliveryFee;
            double delivery = deliveryBd.doubleValue();
            double packaging = OrderPackagingFeeCalculator.calcYuan(goods);
            double sett = OrderPackagingFeeCalculator.roundMoney(goods + packaging + delivery);
            dto.setDelivery_fee(delivery);
            dto.setDineInOrTakeOut("外卖");
            if (!StringUtils.hasText(dto.getTable_number())) {
                dto.setTable_number("外卖");
            }
            if (!StringUtils.hasText(dto.getNumber_of_diners())) {
                dto.setNumber_of_diners("1");
            }
            dto.setSett_amount(sett);
            R r = orderController.create(dto, request);
            if (r == null || !Integer.valueOf(0).equals(r.get("code"))) {
                return r;
            }
            Integer oid = (Integer) r.get("id");
            String orderNo = r.get("order_no") != null ? r.get("order_no").toString() : null;
            if (oid == null || !StringUtils.hasText(orderNo)) {
                throw new IllegalStateException("创单成功但缺少 id/order_no");
            }
            TakeoutDelivery td = new TakeoutDelivery();
            td.setOrder_id(oid);
            td.setOrder_no(orderNo.trim());
            td.setShop_id(sid);
            td.setUser_address_id(addressId);
            td.setReceiver_name(addr.getContact_name());
            td.setReceiver_phone(addr.getContact_phone());
            td.setAddress_full(buildFullAddress(addr));
            td.setLng(addr.getLng());
            td.setLat(addr.getLat());
            td.setDelivery_fee(deliveryBd);
            td.setDispatch_status("submitted");
            takeoutDeliveryService.insertForNewOrder(td);
            return r.put("delivery_fee", delivery).put("packaging_fee", packaging)
                    .put("address_full", td.getAddress_full())
                    .put("takeout_delivery_id", td.getId())
                    .put("openid", openid)
                    .put("distance_km", quote.distanceKm > 0 ? quote.distanceKm : null)
                .put("distance_method", quote.distanceMethod)
                    .put("free_delivery", quote.freeDelivery);
        } catch (Exception e) {
            return R.error("创建外卖订单失败：" + e.getMessage());
        }
    }

    /**
     * 当前用户外卖单列表（dineInOrTakeOut=外卖）。
     */
    @PostMapping("/order/list")
    public R myOrders(@RequestBody Map<String, Object> body) {
        String openid = body != null && body.get("openid") != null ? body.get("openid").toString().trim() : null;
        if (!StringUtils.hasText(openid)) {
            return R.error("openid不能为空");
        }
        int page = 1;
        int size = 20;
        if (body.get("page") instanceof Number) {
            page = Math.max(1, ((Number) body.get("page")).intValue());
        }
        if (body.get("pageSize") instanceof Number) {
            size = Math.min(50, Math.max(1, ((Number) body.get("pageSize")).intValue()));
        }
        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("openid", openid)
                .eq("dineInOrTakeOut", "外卖")
                .orderByDesc("order_time");
        Page<Order> pg = new Page<>(page, size);
        IPage<Order> res = orderService.page(pg, q);
        takeoutDeliveryService.enrichOrders(res.getRecords());
        return R.ok().put("list", res.getRecords()).put("total", res.getTotal()).put("page", page).put("pageSize", size);
    }

    @GetMapping("/order/detail")
    public R orderDetail(@RequestParam String openid, @RequestParam String order_no) {
        if (!StringUtils.hasText(openid) || !StringUtils.hasText(order_no)) {
            return R.error("openid 与 order_no 不能为空");
        }
        Order o = orderService.getOne(new QueryWrapper<Order>()
                .eq("order_no", order_no.trim())
                .eq("openid", openid.trim())
                .last("LIMIT 1"));
        if (o == null) {
            return R.error("订单不存在");
        }
        if (!"外卖".equals(o.getDineInOrTakeOut())) {
            return R.error("非外卖订单");
        }
        TakeoutDelivery d = takeoutDeliveryService.getByOrderId(o.getId());
        takeoutDeliveryService.enrichOrder(o);
        return R.ok().put("order", o).put("delivery", d);
    }

    /**
     * 骑手实时定位与 ETA（真省钱）；须为本用户外卖单且已发配送。
     */
    @GetMapping("/order/tracking")
    public R orderTracking(@RequestParam String openid, @RequestParam String order_no) {
        if (!StringUtils.hasText(openid) || !StringUtils.hasText(order_no)) {
            return R.error("openid 与 order_no 不能为空");
        }
        try {
            ZsqRiderTrackingResponse tracking = takeoutZsqIntegrationService.getTrackingForUser(
                    openid.trim(), order_no.trim());
            Order o = orderService.getOne(new QueryWrapper<Order>()
                    .eq("order_no", order_no.trim())
                    .eq("openid", openid.trim())
                    .last("LIMIT 1"));
            TakeoutDelivery d = o != null ? takeoutDeliveryService.getByOrderId(o.getId()) : null;
            if (o != null) {
                takeoutDeliveryService.enrichOrder(o);
            }
            return R.ok().put("tracking", tracking).put("order", o).put("delivery", d);
        } catch (ZsqRemoteOrderMissingException e) {
            return R.error(4091, e.getMessage())
                    .put("canRedispatch", false)
                    .put("requiresMerchantRedispatch", true);
        } catch (IllegalArgumentException | IllegalStateException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            return R.error("获取配送追踪失败：" + e.getMessage());
        }
    }

    private static Object first(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            if (body.containsKey(k)) {
                return body.get(k);
            }
        }
        return null;
    }

    private static Long parseLong(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        try {
            return Long.parseLong(v.toString().trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String parseString(Object v) {
        if (v == null) {
            return null;
        }
        String s = v.toString().trim();
        return s.isEmpty() ? null : s;
    }
}
