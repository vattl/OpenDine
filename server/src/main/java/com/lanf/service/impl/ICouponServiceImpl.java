package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.dto.CouponDTO;
import com.lanf.dto.CouponRuleValidateRequest;
import com.lanf.dto.CouponRuleValidateResult;
import com.lanf.dto.R;
import com.lanf.dto.UserCouponDTO;
import com.lanf.converter.UserCouponConverter;
import com.lanf.entity.Coupon;
import com.lanf.entity.CouponRedeemCode;
import com.lanf.entity.Dish;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shop;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.ComboMapper;
import com.lanf.mapper.CouponMapper;
import com.lanf.mapper.CouponRedeemCodeMapper;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.ICouponService;
import com.lanf.service.IDishService;
import com.lanf.service.IShopService;
import com.lanf.util.CouponShopFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.text.SimpleDateFormat;

/**
 * 优惠券服务实现类（具体业务逻辑）
 */
@Service // 标识为Spring管理的Service Bean
@RequiredArgsConstructor // 构造器注入依赖（替代@Autowired）
public class ICouponServiceImpl implements ICouponService {

    // 注入Mapper层依赖（构造器注入，由@RequiredArgsConstructor自动生成构造方法）
    private final CouponMapper couponMapper;
    private final CouponRedeemCodeMapper couponRedeemCodeMapper;
    private final UserCouponMapper userCouponMapper;
    private final OrderMapper orderMapper;
    private final ComboMapper comboMapper;
    private final UserCouponConverter userCouponConverter;
    private final IDishService dishService;
    private final IShopService shopService;
    private final ObjectMapper objectMapper;
    @org.springframework.beans.factory.annotation.Autowired(required = false)
    private com.lanf.notify.service.UnifiedNotificationService unifiedNotificationService;
    public void setUnifiedNotificationService(com.lanf.notify.service.UnifiedNotificationService unifiedNotificationService) {
        this.unifiedNotificationService = unifiedNotificationService;
    }
    /**
     * 实现：获取可领取优惠券列表
     */
    @Override
    public R<List<CouponDTO>> getAvailableCoupons(String openid) {
        // 1. 查询所有可用优惠券（原逻辑不变）
        List<Coupon> coupons = couponMapper.selectAvailableCoupons();

        // 2. 实体 → DTO 转换（用 LambdaQueryWrapper 重构领取状态判断）
        List<CouponDTO> dtoList = coupons.stream()
                .map(coupon -> {
                    CouponDTO dto = new CouponDTO();
                    // 基础字段映射（原逻辑不变）
                    dto.setId(coupon.getId());
                    dto.setCoupon_name(coupon.getCoupon_name());
                    dto.setCoupon_type(coupon.getCoupon_type());
                    dto.setDiscount_value(coupon.getDiscount_value());
                    dto.setMin_amount(coupon.getMin_amount());
                    dto.setStart_time(coupon.getStart_time());
                    dto.setEnd_time(coupon.getEnd_time());
                    dto.setStock(coupon.getStock());
                    dto.setDescription(coupon.getDescription());
                    dto.setApply_dining_type(coupon.getApply_dining_type());

                    // 核心重构：用 LambdaQueryWrapper 判断用户是否已领取
                    LambdaQueryWrapper<UserCoupon> queryWrapper = new LambdaQueryWrapper<UserCoupon>()
                            .eq(UserCoupon::getUser_openid, openid) // 匹配用户openid
                            .eq(UserCoupon::getCoupon_id, coupon.getId()); // 匹配当前优惠券ID

                    // 调用 BaseMapper 的 selectCount 统计记录数
                    Integer receiveCount = userCouponMapper.selectCount(queryWrapper);
                    dto.setHas_received(receiveCount > 0); // 标记是否已领取

                    return dto;
                })
                .collect(Collectors.toList());
        return R.success(dtoList);
    }

    /**
     * 获取用户可用优惠券数量：与 {@link #getUserCoupon} 在 status=0 下的语义一致（用户券未过期 + 模板存在且在有效期内）。
     */
    @Override
    public int getAvailableCouponCount(String openid) {
        if (!StringUtils.hasText(openid)) {
            return 0;
        }
        Date now = new Date();
        List<UserCouponDTO> list = userCouponMapper.getUserCoupon(openid.trim(), now, 0);
        if (list == null || list.isEmpty()) {
            return 0;
        }
        return list.size();
    }

    @Override
    public int getAvailableCouponCount(String openid, Integer shopId) {
        if (!StringUtils.hasText(openid) || shopId == null || shopId <= 0) {
            return 0;
        }
        Date now = new Date();
        List<UserCouponDTO> userCouponList = userCouponMapper.getUserCoupon(openid.trim(), now, 0);
        if (userCouponList == null || userCouponList.isEmpty()) {
            return 0;
        }
        int count = 0;
        for (UserCouponDTO dto : userCouponList) {
            if (isUserCouponUsableForShop(dto, now, shopId)) {
                count++;
            }
        }
        return count;
    }

    @Override
    public Coupon selectByCouponById(Long coupon_id) {
        return couponMapper.selectValidCouponById(coupon_id);
    }

    @Override
    public double calcDiscountAmount(double totalRaw, Coupon coupon) {
        if (coupon == null || coupon.getCoupon_type() == null || totalRaw <= 0) {
            return 0d;
        }
        double dv = coupon.getDiscount_value() != null ? coupon.getDiscount_value().doubleValue() : 0d;
        String type = coupon.getCoupon_type().trim().toLowerCase();
        if ("direct_reduction".equals(type) || "full_reduction".equals(type)) {
            return Math.min(dv, totalRaw);
        }
        if ("discount".equals(type) && dv > 0 && dv <= 100) {
            return totalRaw * (100 - dv) / 100;
        }
        return 0d;
    }

    @Override
    public R<CouponRuleValidateResult> validateCouponRule(CouponRuleValidateRequest req) {
        if (req == null) {
            return R.paramError("请求体不能为空");
        }
        if (!StringUtils.hasText(req.getOpenid())) {
            return R.paramError("openid不能为空");
        }
        if (req.getCoupon_id() == null || req.getCoupon_id() <= 0) {
            return R.paramError("coupon_id不能为空");
        }
        CouponRuleValidateResult out = new CouponRuleValidateResult();
        out.setCoupon_id(req.getCoupon_id());
        try {
            UserCouponDTO userCoupon = userCouponMapper.selectValidCouponById(req.getCoupon_id(), req.getOpenid().trim());
            if (userCoupon == null && StringUtils.hasText(req.getOrder_no())) {
                UserCouponDTO bound = userCouponMapper.selectUserCouponJoinById(
                        req.getCoupon_id(), req.getOpenid().trim());
                if (bound != null
                        && Integer.valueOf(1).equals(bound.getStatus())
                        && StringUtils.hasText(bound.getOrder_no())
                        && req.getOrder_no().trim().equals(bound.getOrder_no().trim())) {
                    userCoupon = bound;
                }
            }
            if (userCoupon == null) {
                return invalid(out, "优惠券不存在或不可用");
            }
            out.setCoupon_template_id(userCoupon.getCoupon_id());
            out.setCoupon_type(userCoupon.getCoupon_type());
            boolean usedByCurrentOrder = Integer.valueOf(1).equals(userCoupon.getStatus())
                    && StringUtils.hasText(req.getOrder_no())
                    && StringUtils.hasText(userCoupon.getOrder_no())
                    && req.getOrder_no().trim().equals(userCoupon.getOrder_no().trim());
            if ((userCoupon.getStatus() == null || userCoupon.getStatus() != 0) && !usedByCurrentOrder) {
                return invalid(out, "优惠券状态不可用");
            }
            Date now = new Date();
            if (userCoupon.getStart_time() != null && now.before(userCoupon.getStart_time())) {
                return invalid(out, "优惠券未到生效时间");
            }
            if (userCoupon.getExpire_time() != null && now.after(userCoupon.getExpire_time())) {
                return invalid(out, "优惠券已过期");
            }

            Coupon couponTemplate = selectByCouponById(userCoupon.getCoupon_id());
            if (couponTemplate == null) {
                return invalid(out, "优惠券模板不存在");
            }
            if (req.getShop_id() != null) {
                try {
                    // 同时校验门店存在且营业
                    Shop sh = shopService.getById(req.getShop_id());
                    if (sh == null || sh.getStatus() == null || sh.getStatus() != 1) {
                        return invalid(out, "门店不可用或不存在");
                    }
                    validateCouponShopScope(couponTemplate, req.getShop_id());
                } catch (RuntimeException e) {
                    return invalid(out, e.getMessage());
                }
            }
            try {
                validateCouponShopScope(couponTemplate, req.getShop_id());
            } catch (RuntimeException e) {
                return invalid(out, e.getMessage());
            }
            if (!isDiningTypeAllowed(couponTemplate.getApply_dining_type(), req.getDineInOrTakeOut())) {
                return invalid(out, "该优惠券不适用于当前用餐方式");
            }

            List<OrderDetail> goods = req.getGoods_list() != null ? req.getGoods_list() : new ArrayList<>();
            double totalRaw = sumTotal(goods);
            double eligibleRaw = calcEligibleAmount(goods, couponTemplate.getApply_dish_ids());
            out.setTotal_amount(round2(totalRaw));
            out.setEligible_amount(round2(eligibleRaw));
            if (eligibleRaw <= 0) {
                return invalid(out, "该优惠券不适用于当前所选菜品");
            }
            double minAmount = couponTemplate.getMin_amount() != null ? couponTemplate.getMin_amount().doubleValue() : 0d;
            out.setMin_amount(round2(minAmount));
            if (minAmount > 0 && eligibleRaw < minAmount) {
                return invalid(out, "适用菜品金额未达到优惠券使用门槛（最低需消费" + round2(minAmount) + "元）");
            }
            double discount = calcDiscountAmount(eligibleRaw, couponTemplate);
            out.setDiscount_amount(round2(discount));
            double payable = Math.max(0d, totalRaw - discount);
            out.setPayable_amount(round2(payable));
            out.setValid(true);
            out.setReason("校验通过");
            return R.success(out, "校验通过");
        } catch (RuntimeException e) {
            return invalid(out, e.getMessage());
        } catch (Exception e) {
            return R.systemError("优惠券规则校验失败：" + e.getMessage());
        }
    }

    private R<CouponRuleValidateResult> invalid(CouponRuleValidateResult out, String reason) {
        out.setValid(false);
        out.setDiscount_amount(0d);
        out.setPayable_amount(out.getTotal_amount() != null ? out.getTotal_amount() : 0d);
        out.setReason(reason);
        return R.fail(1, reason, out);
    }

    private void validateCouponShopScope(Coupon couponTemplate, Integer orderShopId) {
        if (couponTemplate == null) {
            return;
        }
        String raw = couponTemplate.getApply_shop_ids();
        // 约定：apply_shop_ids 为空/[] 视为不可用
        if (!StringUtils.hasText(raw) || "[]".equals(raw.trim())) {
            throw new RuntimeException("该优惠券未配置适用门店，暂不可使用");
        }
        if (orderShopId == null) {
            throw new RuntimeException("该优惠券需指定门店后才能校验");
        }
        Set<Integer> allow = parseJsonIntSet(raw, "优惠券适用门店配置异常，请联系管理员");
        if (allow.isEmpty()) {
            throw new RuntimeException("该优惠券未配置适用门店，暂不可使用");
        }
        if (!allow.contains(orderShopId)) {
            throw new RuntimeException("该优惠券不适用于当前门店");
        }
    }

    private boolean isDiningTypeAllowed(String applyDiningType, String dineType) {
        if (!StringUtils.hasText(applyDiningType) || "all".equalsIgnoreCase(applyDiningType.trim())) {
            return true;
        }
        if (!StringUtils.hasText(dineType)) {
            return false;
        }
        String normalized = normalizeDiningType(dineType);
        if ("dine_in".equalsIgnoreCase(applyDiningType.trim())) {
            return "dine_in".equals(normalized);
        }
        if ("take_out".equalsIgnoreCase(applyDiningType.trim())) {
            return "take_out".equals(normalized);
        }
        return true;
    }

    private String normalizeDiningType(String raw) {
        String t = raw.trim();
        if ("堂食".equals(t) || "dine_in".equalsIgnoreCase(t) || "dinein".equalsIgnoreCase(t)) {
            return "dine_in";
        }
        if ("打包".equals(t) || "take_out".equalsIgnoreCase(t) || "takeout".equalsIgnoreCase(t)) {
            return "take_out";
        }
        return t.toLowerCase();
    }

    private Set<Integer> parseJsonIntSet(String raw, String errMsg) {
        Set<Integer> set = new HashSet<>();
        try {
            List<?> arr = objectMapper.readValue(raw.trim(), List.class);
            if (arr != null) {
                for (Object o : arr) {
                    if (o instanceof Number) {
                        set.add(((Number) o).intValue());
                    } else if (o != null && StringUtils.hasText(o.toString())) {
                        set.add(Integer.parseInt(o.toString().trim()));
                    }
                }
            }
            return set;
        } catch (Exception e) {
            throw new RuntimeException(errMsg);
        }
    }

    private double calcEligibleAmount(List<OrderDetail> goods, String applyDishIdsText) {
        if (goods == null || goods.isEmpty()) {
            return 0d;
        }
        boolean hasFilter = StringUtils.hasText(applyDishIdsText) && !"[]".equals(applyDishIdsText.trim());
        Set<Integer> allow = hasFilter ? parseJsonIntSet(applyDishIdsText, "优惠券适用菜品配置异常，请联系管理员") : Collections.emptySet();
        if (hasFilter && allow.isEmpty()) {
            hasFilter = false;
        }

        double eligible = 0d;
        for (OrderDetail od : goods) {
            if (od == null || od.getTotal_price() == null || od.getTotal_price() <= 0) {
                continue;
            }
            // 若为套餐头行，检查套餐是否允许叠加优惠券
            if ("combo_header".equalsIgnoreCase(od.getLine_type()) || (od.getCombo_id() != null && od.getCombo_id() > 0)) {
                if (od.getCombo_id() != null && comboMapper != null) {
                    com.lanf.entity.Combo combo = comboMapper.selectById(od.getCombo_id());
                    if (combo != null && combo.getAllow_coupon() != null && combo.getAllow_coupon() == 0) {
                        continue; // 不允许叠加优惠券，剔除在适用金额之外
                    }
                }
            }
            if (hasFilter) {
                Dish dish = od.getDish_id() != null && od.getDish_id() > 0 ? dishService.getById(od.getDish_id()) : null;
                if (dish == null && StringUtils.hasText(od.getName())) {
                    dish = resolveDishByMenuName(od.getName().trim());
                }
                if (dish == null || dish.getId() == null || !allow.contains(dish.getId())) {
                    continue;
                }
            }
            eligible += od.getTotal_price();
        }
        return eligible;
    }

    private Dish resolveDishByMenuName(String dishName) {
        Dish dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                .eq(Dish::getName, dishName)
                .last("LIMIT 1"));
        if (dish == null) {
            String compact = dishName.replaceAll("\\s+", "");
            if (!compact.equals(dishName)) {
                dish = dishService.getOne(new LambdaQueryWrapper<Dish>()
                        .eq(Dish::getName, compact)
                        .last("LIMIT 1"));
            }
        }
        return dish;
    }

    private double sumTotal(List<OrderDetail> goods) {
        if (goods == null || goods.isEmpty()) {
            return 0d;
        }
        double total = 0d;
        for (OrderDetail od : goods) {
            if (od == null || od.getTotal_price() == null) {
                continue;
            }
            total += od.getTotal_price();
        }
        return total;
    }

    private double round2(double v) {
        return Math.round(v * 100) / 100.0;
    }

    /**
     * 实现：领取优惠券（事务保证原子性）
     */
    @Override
    @Transactional
    public R<Void> receiveCoupon(String openid, Long couponId) {
        // 1. 校验优惠券是否有效（原逻辑不变）
        Coupon coupon = couponMapper.selectValidCouponById(couponId);
        if (coupon == null) {
            return R.fail("优惠券不存在或已失效");
        }

        // 2. 校验库存（-1表示无限库存，原逻辑不变）
        if (coupon.getStock() != -1 && coupon.getStock() <= 0) {
            return R.fail("优惠券已抢完");
        }

        // 允许同一用户同一券模板多条领取记录（兑换码多码、多次领等）；不再按 user+coupon_id 去重。

        // 3. 保存用户优惠券记录（优化字段命名规范：推荐用驼峰命名 setUserOpenid 而非 setUser_openid）
        Date now = new Date();
        UserCoupon userCoupon = new UserCoupon();
        userCoupon.setUser_openid(openid); // 若实体字段是 user_openid，需保持 setUser_openid（按实际实体调整）
        userCoupon.setCoupon_id(couponId); // 同理：若实体字段是 coupon_id，需用 setCoupon_id
        userCoupon.setGet_time(now); // 时间字段推荐驼峰命名 getTime → setGetTime
        userCoupon.setStatus(0); // 0-未使用（与之前状态规范一致）
        userCoupon.setExpire_time(calcUserCouponExpireTime(now, coupon)); // 优先按 validity_time（小时）计算用户券失效时间
        userCouponMapper.insert(userCoupon);
        couponMapper.incrementGrantedCount(couponId);
        if (unifiedNotificationService != null) {
            try {
                unifiedNotificationService.publishCouponGranted(userCoupon, coupon);
            } catch (Exception ignored) {
            }
        }

        // 4. 扣减库存（仅有限库存需要扣减，原逻辑不变）
        if (coupon.getStock() != -1) {
            coupon.setStock(coupon.getStock() - 1);
            couponMapper.updateById(coupon);
        }

        return R.success(null);
    }

    private Date calcUserCouponExpireTime(Date baseTime, Coupon coupon) {
        Date now = baseTime != null ? baseTime : new Date();
        if (coupon != null && coupon.getValidity_time() != null && coupon.getValidity_time() > 0) {
            Calendar cal = Calendar.getInstance();
            cal.setTime(now);
            cal.add(Calendar.HOUR_OF_DAY, coupon.getValidity_time());
            return cal.getTime();
        }
        return coupon != null ? coupon.getEnd_time() : null;
    }

    @Override
    @Transactional
    public R<Map<String, Object>> receiveCouponByRedeemCode(String openid, String redeemCode) {
        if (!StringUtils.hasText(openid)) {
            return R.fail("openid不能为空");
        }
        if (!StringUtils.hasText(redeemCode)) {
            return R.fail("redeem_code不能为空");
        }
        String code = redeemCode.trim();
        CouponRedeemCode redeem = couponRedeemCodeMapper.selectOne(new LambdaQueryWrapper<CouponRedeemCode>()
                .eq(CouponRedeemCode::getRedeem_code, code)
                .eq(CouponRedeemCode::getStatus, 0)
                .last("LIMIT 1"));
        if (redeem == null || redeem.getCoupon_id() == null) {
            return R.fail("兑换码无效");
        }
        // 先原子核销兑换码，确保一次性使用（防转发并发重复兑换）
        int consumed = couponRedeemCodeMapper.update(null, new LambdaUpdateWrapper<CouponRedeemCode>()
                .set(CouponRedeemCode::getStatus, 1)
                .set(CouponRedeemCode::getUsed_openid, openid.trim())
                .set(CouponRedeemCode::getUsed_time, new Date())
                .eq(CouponRedeemCode::getId, redeem.getId())
                .eq(CouponRedeemCode::getRedeem_code, code)
                .eq(CouponRedeemCode::getStatus, 0));
        if (consumed <= 0) {
            return R.fail("兑换码已失效");
        }
        R<Void> receiveResult = receiveCoupon(openid.trim(), redeem.getCoupon_id());
        if (receiveResult == null || receiveResult.getCode() == null || receiveResult.getCode() != 0) {
            // 领取失败抛异常触发事务回滚，保证兑换码不会被错误核销
            throw new RuntimeException(receiveResult != null ? receiveResult.getMsg() : "兑换失败");
        }
        Coupon coupon = couponMapper.selectById(redeem.getCoupon_id());
        Map<String, Object> detail = buildRedeemCouponDetail(coupon);
        return R.success(detail);
    }

    private Map<String, Object> buildRedeemCouponDetail(Coupon coupon) {
        Map<String, Object> m = new HashMap<>();
        m.put("couponName", coupon != null && StringUtils.hasText(coupon.getCoupon_name()) ? coupon.getCoupon_name() : "-");
        m.put("validUntil", formatDate(coupon != null ? coupon.getEnd_time() : null));
        m.put("typeLabel", "优惠券");
        m.put("discountText", formatDiscount(coupon));
        m.put("ruleText", coupon != null && StringUtils.hasText(coupon.getDescription()) ? coupon.getDescription() : "暂无规则说明");
        // 兼容前端可能直接读取原字段
        m.put("coupon_name", m.get("couponName"));
        m.put("valid_until", m.get("validUntil"));
        m.put("type_label", m.get("typeLabel"));
        m.put("discount_text", m.get("discountText"));
        m.put("rule_text", m.get("ruleText"));
        return m;
    }

    private String formatDate(Date d) {
        if (d == null) return "-";
        return new SimpleDateFormat("yyyy-MM-dd").format(d);
    }

    private String formatDiscount(Coupon coupon) {
        if (coupon == null || coupon.getDiscount_value() == null || !StringUtils.hasText(coupon.getCoupon_type())) {
            return "-";
        }
        double dv = coupon.getDiscount_value().doubleValue();
        String type = coupon.getCoupon_type().trim().toLowerCase();
        if ("discount".equals(type)) {
            return dv + "折";
        }
        return "减" + dv + "元";
    }

    /**
     * 实现：获取用户优惠券列表（按状态筛选）
     */
    @Override
    public R<List<UserCouponDTO>> getUserCoupons(String openid, String status) {
        Integer statusCode = resolveCouponStatusCode(status);
        Date now = new Date();
        List<UserCouponDTO> userCouponList = userCouponMapper.getUserCoupon(openid, now, statusCode);
        if (Integer.valueOf(0).equals(statusCode)) {
            userCouponList = retainUsableNotExpired(userCouponList, now);
        }
        return R.success(userCouponList);
    }

    @Override
    public R<List<UserCouponDTO>> getUserCoupons(String openid, String status, Integer shopId) {
        Integer statusCode = resolveCouponStatusCode(status);
        if (shopId == null || shopId <= 0) {
            return R.fail("shop_id 不能为空");
        }
        Date now = new Date();
        List<UserCouponDTO> userCouponList = userCouponMapper.getUserCoupon(openid, now, statusCode);
        if (Integer.valueOf(0).equals(statusCode)) {
            userCouponList = retainUsableNotExpired(userCouponList, now);
        }
        List<UserCouponDTO> filtered = userCouponList.stream()
                .filter(c -> filterUserCouponForShopList(c, statusCode, now, shopId))
                .collect(Collectors.toList());

        return R.success(filtered);
    }

    @Override
    public R<List<UserCouponDTO>> getUserAvailableCoupons(String openid, Integer shopId) {
        return getUserCoupons(openid, "usable", shopId);
    }

    private Integer resolveCouponStatusCode(String status) {
        // 状态映射：usable-未使用(0)、used-已使用(1)、expired-已失效(2)（Java 8兼容）
        if ("usable".equals(status)) {
            return 0;
        } else if ("used".equals(status)) {
            return 1;
        } else if ("expired".equals(status)) {
            return 2;
        }
        throw new IllegalArgumentException("无效状态：" + status);
    }

    /** 「可用」列表：剔除已过期（用户券 expire_time、模板 end_time）；**未到模板生效 start_time 的券仍保留**，下单前以 {@link #validateCouponRule} 为准。 */
    private List<UserCouponDTO> retainUsableNotExpired(List<UserCouponDTO> list, Date now) {
        if (list == null || list.isEmpty()) {
            return list;
        }
        return list.stream().filter(dto -> isUserCouponRecordUsableAt(dto, now)).collect(Collectors.toList());
    }

    /**
     * 列表/计数侧「未过期」判断：不过滤未到模板生效时间；剔除用户券过期、模板已结束。
     * 是否已到可核销时间见 {@link #validateCouponRule}。
     */
    private boolean isUserCouponRecordUsableAt(UserCouponDTO dto, Date now) {
        if (dto == null || dto.getStatus() == null || dto.getStatus() != 0) {
            return false;
        }
        if (dto.getExpire_time() != null && now.after(dto.getExpire_time())) {
            return false;
        }
        if (dto.getEnd_time() != null && now.after(dto.getEnd_time())) {
            return false;
        }
        return true;
    }

    /** 当前门店下列表：usable 时 SQL 已收紧，此处再校验门店范围；used/expired 仅按门店过滤。 */
    private boolean filterUserCouponForShopList(UserCouponDTO c, Integer statusCode, Date now, Integer shopId) {
        if (c == null) {
            return false;
        }
        if (statusCode != null && statusCode == 0 && !isUserCouponRecordUsableAt(c, now)) {
            return false;
        }
        return isCouponApplicableToShop(c.getApply_shop_ids(), shopId);
    }

    /** 可用数量（按门店）：时间维度可用 + apply_shop_ids 含门店。 */
    private boolean isUserCouponUsableForShop(UserCouponDTO dto, Date now, Integer shopId) {
        return dto != null && isUserCouponRecordUsableAt(dto, now) && isCouponApplicableToShop(dto.getApply_shop_ids(), shopId);
    }

    private boolean isCouponApplicableToShop(String applyShopIdsRaw, Integer shopId) {
        return com.lanf.util.CouponShopFilter.strictShopScope(applyShopIdsRaw, shopId);
    }

    /**
     * 实现：使用优惠券（事务保证状态更新原子性）
     */
    @Override
    @Transactional
    public R<Void> useCoupon(String openid, Long couponId, String orderNo) {
        // couponId 优先按 t_user_coupon.id（下单/验券链路与 OrderDTO.coupon_id 一致）；否则按券模板 t_coupon.id 取最早未使用的一条（多领时 FIFO）
        UserCoupon userCoupon = userCouponMapper.selectOne(
                new LambdaQueryWrapper<UserCoupon>()
                        .eq(UserCoupon::getUser_openid, openid)
                        .eq(UserCoupon::getId, couponId)
                        .eq(UserCoupon::getStatus, 0)
                        .last("LIMIT 1"));
        if (userCoupon == null) {
            userCoupon = userCouponMapper.selectOne(
                    new LambdaQueryWrapper<UserCoupon>()
                            .eq(UserCoupon::getUser_openid, openid)
                            .eq(UserCoupon::getCoupon_id, couponId)
                            .eq(UserCoupon::getStatus, 0)
                            .orderByAsc(UserCoupon::getId)
                            .last("LIMIT 1"));
        }

        // 校验优惠券是否可用
        if (userCoupon == null) {
            return R.fail("优惠券不可用");
        }

        // 校验是否过期（过期则标记为失效）

        if (userCoupon.getExpire_time() != null) {
            // 获取过期时间和当前时间的时间戳（毫秒数）
            long expireTimestamp = userCoupon.getExpire_time().getTime();
            long nowTimestamp = System.currentTimeMillis();

            // 时间戳比较：过期时间戳 < 当前时间戳 → 已过期
            if (expireTimestamp < nowTimestamp) {
                userCoupon.setStatus(2); // 状态：已失效
                userCouponMapper.updateById(userCoupon);
                return R.fail("优惠券已过期");
            }
        } else {
            // 空指针防护：避免 expire_time 为 null 导致后续报错
            return R.fail("优惠券信息不完整或过期时间未设置");
        }

        // 更新优惠券状态为已使用，并关联订单号
        userCoupon.setStatus(1); // 状态：已使用
        userCoupon.setUse_time(new Date());
        userCoupon.setOrder_no(orderNo);
        userCouponMapper.updateById(userCoupon);

        return R.success(null);
    }

    @Override
    public R<CouponDTO> getCouponTemplateDetail(String openid, Long templateId, Integer shopId) {
        if (templateId == null || templateId <= 0) {
            return R.paramError("template_id 不能为空");
        }
        Coupon coupon = couponMapper.selectById(templateId);
        if (coupon == null) {
            return R.notFound("优惠券不存在");
        }
        if (coupon.getStatus() == null || coupon.getStatus() != 1) {
            return R.fail("优惠券未启用或已下架");
        }
        Date now = new Date();
        if (coupon.getEnd_time() != null && now.after(coupon.getEnd_time())) {
            return R.fail("活动已结束");
        }
        if (coupon.getStock() != null && coupon.getStock() != -1 && coupon.getStock() <= 0) {
            return R.fail("优惠券已抢完");
        }
        if (shopId != null && shopId > 0 && !CouponShopFilter.strictShopScope(coupon.getApply_shop_ids(), shopId)) {
            return R.fail("该券不适用当前门店");
        }
        boolean hasReceived = false;
        if (StringUtils.hasText(openid)) {
            Integer cnt = userCouponMapper.selectCount(new LambdaQueryWrapper<UserCoupon>()
                    .eq(UserCoupon::getUser_openid, openid.trim())
                    .eq(UserCoupon::getCoupon_id, templateId));
            hasReceived = cnt != null && cnt > 0;
        }
        return R.success(toCouponDto(coupon, hasReceived));
    }

    @Override
    public R<UserCouponDTO> getUserCouponDetail(String openid, Long userCouponRecordId) {
        if (!StringUtils.hasText(openid)) {
            return R.paramError("openid不能为空");
        }
        if (userCouponRecordId == null || userCouponRecordId <= 0) {
            return R.paramError("user_coupon_id 不能为空");
        }
        UserCouponDTO dto = userCouponMapper.selectUserCouponJoinById(userCouponRecordId, openid.trim());
        if (dto == null) {
            return R.notFound("用户优惠券不存在");
        }
        return R.success(dto);
    }

    @Override
    public R<Map<String, Object>> getUserCouponsPage(String openid, String status, Integer shopId, Integer page, Integer pageSize) {
        if (!StringUtils.hasText(openid)) {
            return R.paramError("openid不能为空");
        }
        if (!StringUtils.hasText(status)) {
            return R.paramError("status不能为空");
        }
        final int p = page == null || page < 1 ? 1 : page;
        int ps = pageSize == null || pageSize < 1 ? 20 : pageSize;
        if (ps > 100) {
            ps = 100;
        }
        final Integer statusCode;
        try {
            statusCode = resolveCouponStatusCode(status.trim());
        } catch (IllegalArgumentException e) {
            return R.paramError(e.getMessage());
        }
        Date now = new Date();
        final boolean memMode = Integer.valueOf(0).equals(statusCode) || (shopId != null && shopId > 0);
        if (memMode) {
            List<UserCouponDTO> all = userCouponMapper.getUserCoupon(openid.trim(), now, statusCode);
            if (all == null) {
                all = Collections.emptyList();
            }
            if (Integer.valueOf(0).equals(statusCode)) {
                all = retainUsableNotExpired(all, now);
            }
            if (shopId != null && shopId > 0) {
                all = all.stream()
                        .filter(c -> filterUserCouponForShopList(c, statusCode, now, shopId))
                        .collect(Collectors.toList());
            }
            long total = all.size();
            int from = (p - 1) * ps;
            List<UserCouponDTO> slice = from >= all.size()
                    ? Collections.emptyList()
                    : all.subList(from, Math.min(from + ps, all.size()));
            return R.success(pageMap(slice, total, p, ps));
        }
        long total = userCouponMapper.countUserCouponForPage(openid.trim(), now, statusCode);
        int offset = (p - 1) * ps;
        List<UserCouponDTO> slice = userCouponMapper.getUserCouponPage(openid.trim(), now, statusCode, offset, ps);
        return R.success(pageMap(slice, total, p, ps));
    }

    @Override
    public R<Map<String, Object>> getAvailableCouponsPage(String openid, Integer shopId, Integer page, Integer pageSize) {
        final int p = page == null || page < 1 ? 1 : page;
        int ps = pageSize == null || pageSize < 1 ? 20 : pageSize;
        if (ps > 100) {
            ps = 100;
        }
        List<Coupon> coupons = couponMapper.selectAvailableCoupons();
        if (coupons == null) {
            coupons = Collections.emptyList();
        }
        Date now = new Date();
        List<Coupon> filtered = new ArrayList<>();
        for (Coupon c : coupons) {
            if (c == null || c.getId() == null) {
                continue;
            }
            if (c.getStock() != null && c.getStock() != -1 && c.getStock() <= 0) {
                continue;
            }
            if (c.getEnd_time() != null && now.after(c.getEnd_time())) {
                continue;
            }
            if (shopId != null && shopId > 0 && !CouponShopFilter.strictShopScope(c.getApply_shop_ids(), shopId)) {
                continue;
            }
            filtered.add(c);
        }
        filtered.sort((a, b) -> {
            long ai = a.getId() != null ? a.getId() : 0L;
            long bi = b.getId() != null ? b.getId() : 0L;
            return Long.compare(bi, ai);
        });
        long total = filtered.size();
        int from = (p - 1) * ps;
        List<CouponDTO> rows = new ArrayList<>();
        if (from < filtered.size()) {
            int to = Math.min(from + ps, filtered.size());
            for (Coupon coupon : filtered.subList(from, to)) {
                boolean hasReceived = false;
                if (StringUtils.hasText(openid)) {
                    Integer cnt = userCouponMapper.selectCount(new LambdaQueryWrapper<UserCoupon>()
                            .eq(UserCoupon::getUser_openid, openid.trim())
                            .eq(UserCoupon::getCoupon_id, coupon.getId()));
                    hasReceived = cnt != null && cnt > 0;
                }
                rows.add(toCouponDto(coupon, hasReceived));
            }
        }
        return R.success(pageMap(rows, total, p, ps));
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public R<Void> unbindUserCouponFromOrder(String openid, String orderNo) {
        if (!StringUtils.hasText(openid)) {
            return R.paramError("openid不能为空");
        }
        if (!StringUtils.hasText(orderNo)) {
            return R.paramError("order_no不能为空");
        }
        String ono = orderNo.trim();
        String oid = openid.trim();
        Order order = orderMapper.selectOne(new QueryWrapper<Order>()
                .eq("order_no", ono)
                .eq("openid", oid)
                .last("LIMIT 1"));
        if (order == null) {
            return R.notFound("订单不存在");
        }
        if ("success".equals(order.getTransac_status())) {
            return R.fail("已支付订单不可解绑优惠券");
        }
        List<UserCoupon> bound = userCouponMapper.selectList(new LambdaQueryWrapper<UserCoupon>()
                .eq(UserCoupon::getOrder_no, ono)
                .eq(UserCoupon::getUser_openid, oid)
                .eq(UserCoupon::getStatus, 0));
        if (bound == null || bound.isEmpty()) {
            return R.successMsg("无占用中的优惠券");
        }
        for (UserCoupon uc : bound) {
            uc.setOrder_no(null);
            userCouponMapper.updateById(uc);
        }
        return R.success(null);
    }

    private static Map<String, Object> pageMap(Object list, long total, int page, int pageSize) {
        Map<String, Object> m = new HashMap<>();
        m.put("list", list);
        m.put("total", total);
        m.put("page", page);
        m.put("pageSize", pageSize);
        return m;
    }

    private static CouponDTO toCouponDto(Coupon coupon, boolean hasReceived) {
        CouponDTO dto = new CouponDTO();
        dto.setId(coupon.getId());
        dto.setCoupon_name(coupon.getCoupon_name());
        dto.setCoupon_type(coupon.getCoupon_type());
        dto.setDiscount_value(coupon.getDiscount_value());
        dto.setMin_amount(coupon.getMin_amount());
        dto.setStart_time(coupon.getStart_time());
        dto.setEnd_time(coupon.getEnd_time());
        dto.setStock(coupon.getStock());
        dto.setDescription(coupon.getDescription());
        dto.setApply_dining_type(coupon.getApply_dining_type());
        dto.setHas_received(hasReceived);
        return dto;
    }
}
