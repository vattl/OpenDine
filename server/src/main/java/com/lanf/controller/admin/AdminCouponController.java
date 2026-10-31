package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONObject;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Coupon;
import com.lanf.entity.CouponRedeemCode;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.CouponMapper;
import com.lanf.mapper.CouponRedeemCodeMapper;
import com.lanf.mapper.OrderMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.mapper.UserMapper;
import com.lanf.properties.WeixinProperties;
import com.lanf.service.ICouponService;
import com.lanf.util.AdminOrderShopScope;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.CouponShopFilter;
import com.lanf.util.HttpClientUtil;
import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletRequest;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.security.SecureRandom;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.stream.Collectors;

/**
 * 运营后台 - 优惠券管理（增删改查）
 */
@RestController
@RequestMapping("/admin/coupon")
public class AdminCouponController {

    private static final Logger log = LoggerFactory.getLogger(AdminCouponController.class);
    private static final ObjectMapper OM = new ObjectMapper();
    private static final String REDEEM_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final int REDEEM_CODE_LEN = 10;
    private static final SecureRandom REDEEM_RNG = new SecureRandom();

    @Autowired
    private CouponMapper couponMapper;
    @Autowired
    private CouponRedeemCodeMapper couponRedeemCodeMapper;
    @Autowired
    private UserMapper userMapper;
    @Autowired
    private OrderMapper orderMapper;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private ICouponService couponService;
    @Autowired
    private WeixinProperties weixinProperties;
    @Autowired
    private HttpClientUtil httpClientUtil;
    @Autowired
    private HttpServletRequest httpServletRequest;

    /**
     * 列表（可按状态筛选）
     * status: 0-未启用 1-可用 2-已下架；不传查全部
     */
    @GetMapping("/list")
    public R list(@RequestParam(required = false) Integer status) {
        try {
            // 线上数据库字段可能存在差异，避免按不存在的 update_time/create_time 排序导致 500
            QueryWrapper<Coupon> qw = new QueryWrapper<Coupon>().orderByDesc("id");
            if (status != null) {
                qw.eq("status", status);
            }
            List<Coupon> all = couponMapper.selectList(qw);
            Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
            List<Coupon> list = sid == null ? all : all.stream()
                    .filter(c -> CouponShopFilter.appliesToShop(c, sid))
                    .collect(Collectors.toList());
            Map<String, Object> result = new HashMap<>();
            result.put("list", list);
            result.put("total", list != null ? list.size() : 0);
            return R.ok(result);
        } catch (Exception e) {
            return R.error("查询失败：" + (e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName()));
        }
    }

    /** 详情 */
    @GetMapping("/get")
    public R get(@RequestParam Long id) {
        if (id == null || id <= 0) {
            return R.error("id 不能为空");
        }
        Coupon c = couponMapper.selectById(id);
        if (c == null) {
            return R.error("优惠券不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(c, sid)) {
            return R.error(4003, "优惠券不属于当前门店");
        }
        return R.ok().put("coupon", c);
    }

    /** 新增 */
    @PostMapping("/add")
    @AuditLog(module = "coupon", action = "admin_coupon_add", target = "#p0.id")
    public R add(@RequestBody Coupon coupon) {
        if (coupon == null) {
            return R.error("参数不能为空");
        }
        if (!StringUtils.hasText(coupon.getCoupon_name())) {
            return R.error("coupon_name 不能为空");
        }
        if (!StringUtils.hasText(coupon.getCoupon_type())) {
            return R.error("coupon_type 不能为空");
        }
        if (!StringUtils.hasText(coupon.getApply_dining_type())) {
            coupon.setApply_dining_type("all");
        }
        Date now = new Date();
        if (coupon.getCreate_time() == null) coupon.setCreate_time(now);
        if (coupon.getUpdate_time() == null) coupon.setUpdate_time(now);
        if (coupon.getStatus() == null) coupon.setStatus(1);
        if (coupon.getStock() == null) coupon.setStock(-1);
        if (coupon.getGranted_count() == null) {
            coupon.setGranted_count(0);
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (sid != null && !StringUtils.hasText(coupon.getApply_shop_ids())) {
            try {
                coupon.setApply_shop_ids(OM.writeValueAsString(Collections.singletonList(sid)));
            } catch (Exception ignored) {
                coupon.setApply_shop_ids("[" + sid + "]");
            }
        }
        couponMapper.insert(coupon);
        return R.ok().put("id", coupon.getId());
    }

    private String generateUniqueRedeemCode() {
        for (int i = 0; i < 20; i++) {
            String code = randomRedeemCode();
            Integer exists = couponRedeemCodeMapper.selectCount(new QueryWrapper<CouponRedeemCode>().eq("redeem_code", code));
            if (exists == null || exists <= 0) {
                return code;
            }
        }
        throw new RuntimeException("生成兑换码失败，请重试");
    }

    private String randomRedeemCode() {
        StringBuilder sb = new StringBuilder(REDEEM_CODE_LEN);
        for (int i = 0; i < REDEEM_CODE_LEN; i++) {
            int idx = REDEEM_RNG.nextInt(REDEEM_CODE_CHARS.length());
            sb.append(REDEEM_CODE_CHARS.charAt(idx));
        }
        return sb.toString();
    }

    /**
     * 独立创建兑换码（支持批量）。
     * 请求示例：{ "couponId": 1, "count": 20 }
     */
    @PostMapping("/redeem-code/create")
    @AuditLog(module = "coupon", action = "admin_coupon_redeem_create", target = "#p0['couponId']")
    public R createRedeemCodes(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Object couponIdRaw = body.get("couponId");
        if (!(couponIdRaw instanceof Number)) {
            return R.error("couponId 必填且必须为数字");
        }
        long couponId = ((Number) couponIdRaw).longValue();
        int count = 1;
        Object countRaw = body.get("count");
        if (countRaw instanceof Number) {
            count = ((Number) countRaw).intValue();
        }
        if (count <= 0) {
            return R.error("count 必须大于 0");
        }
        if (count > 500) {
            return R.error("count 不能超过 500");
        }
        Coupon coupon = couponMapper.selectById(couponId);
        if (coupon == null) {
            return R.error("优惠券不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(coupon, sid)) {
            return R.error(4003, "优惠券不属于当前门店");
        }
        List<Map<String, Object>> codes = new java.util.ArrayList<>();
        Date now = new Date();
        for (int i = 0; i < count; i++) {
            String code = generateUniqueRedeemCode();
            CouponRedeemCode redeem = new CouponRedeemCode();
            redeem.setCoupon_id(couponId);
            redeem.setRedeem_code(code);
            redeem.setStatus(0);
            redeem.setCreate_time(now);
            couponRedeemCodeMapper.insert(redeem);
            Map<String, Object> item = new HashMap<>();
            item.put("id", redeem.getId());
            item.put("redeem_code", code);
            codes.add(item);
        }
        return R.ok().put("couponId", couponId).put("count", count).put("codes", codes);
    }

    /**
     * 一键发券（只发给已绑定手机号用户）
     * 支持按注册时间范围、消费历史金额、会员类型筛选。
     */
    @PostMapping("/batch-send")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "coupon", action = "admin_coupon_batch_send", target = "#p0['couponId']")
    public R batchSendCoupon(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Object couponIdRaw = body.get("couponId");
        if (!(couponIdRaw instanceof Number)) {
            return R.error("couponId 必填且必须为数字");
        }
        long couponId = ((Number) couponIdRaw).longValue();
        if (couponId <= 0) {
            return R.error("couponId 必须大于 0");
        }

        Coupon coupon = couponMapper.selectById(couponId);
        if (coupon == null) {
            return R.error("优惠券不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(coupon, sid)) {
            return R.error(4003, "优惠券不属于当前门店");
        }

        String registerStartRaw = asText(body.get("registerStart"));
        String registerEndRaw = asText(body.get("registerEnd"));
        Date registerStart = parseDateTime(registerStartRaw);
        Date registerEnd = parseDateTime(registerEndRaw);
        if (asText(body.get("registerStart")) != null && registerStart == null) {
            return R.error("registerStart 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (asText(body.get("registerEnd")) != null && registerEnd == null) {
            return R.error("registerEnd 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (registerEnd != null && registerEndRaw != null && !registerEndRaw.contains(":")) {
            registerEnd = new Date(registerEnd.getTime() + 24L * 60L * 60L * 1000L - 1000L);
        }
        if (registerStart != null && registerEnd != null && registerStart.after(registerEnd)) {
            return R.error("registerStart 不能晚于 registerEnd");
        }

        Double minConsumeAmount = asDouble(body.get("minConsumeAmount"));
        Double maxConsumeAmount = asDouble(body.get("maxConsumeAmount"));
        if (body.containsKey("minConsumeAmount") && minConsumeAmount == null) {
            return R.error("minConsumeAmount 必须为数字");
        }
        if (body.containsKey("maxConsumeAmount") && maxConsumeAmount == null) {
            return R.error("maxConsumeAmount 必须为数字");
        }
        if (minConsumeAmount != null && minConsumeAmount < 0) {
            return R.error("minConsumeAmount 不能小于 0");
        }
        if (maxConsumeAmount != null && maxConsumeAmount < 0) {
            return R.error("maxConsumeAmount 不能小于 0");
        }
        if (minConsumeAmount != null && maxConsumeAmount != null && minConsumeAmount > maxConsumeAmount) {
            return R.error("minConsumeAmount 不能大于 maxConsumeAmount");
        }
        boolean previewOnly = toBoolean(body.get("previewOnly"));
        String consumeShopScope = asText(body.get("consumeShopScope"));
        if (!StringUtils.hasText(consumeShopScope)) {
            consumeShopScope = "accessible";
        }

        Set<Integer> userTypes;
        try {
            userTypes = parseUserTypes(body);
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }

        QueryWrapper<User> userQw = new QueryWrapper<User>()
                .isNotNull("phone")
                .ne("phone", "")
                .apply("TRIM(phone) <> ''");
        if (registerStart != null) {
            userQw.ge("time", registerStart);
        }
        if (registerEnd != null) {
            userQw.le("time", registerEnd);
        }
        if (!userTypes.isEmpty()) {
            userQw.in("user_type", userTypes);
        }
        List<User> candidateUsers = userMapper.selectList(userQw);
        int candidateCount = candidateUsers != null ? candidateUsers.size() : 0;
        log.info("batch-send candidate users: couponId={}, shopId={}, consumeShopScope={}, registerStart={}, registerEnd={}, userTypes={}, minConsumeAmount={}, maxConsumeAmount={}, candidateCount={}",
                couponId, sid, consumeShopScope, registerStart, registerEnd, userTypes, minConsumeAmount, maxConsumeAmount, candidateCount);
        
        if (candidateUsers == null || candidateUsers.isEmpty()) {
            return R.ok()
                    .put("couponId", couponId)
                    .put("candidateUserCount", candidateCount)
                    .put("openidReadyCount", 0)
                    .put("consumeMatchedCount", 0)
                    .put("targetUserCount", 0)
                    .put("grantedCount", 0);
        }

        Map<String, Double> userConsumeMap = new HashMap<>();
        if (minConsumeAmount != null || maxConsumeAmount != null) {
            List<String> candidateOpenids = new ArrayList<>();
            for (User user : candidateUsers) {
                if (user != null && StringUtils.hasText(user.getOpenid())) {
                    candidateOpenids.add(user.getOpenid().trim());
                }
            }
            if (!candidateOpenids.isEmpty()) {
                final int batchSize = 500;
                for (int i = 0; i < candidateOpenids.size(); i += batchSize) {
                    int end = Math.min(i + batchSize, candidateOpenids.size());
                    List<String> batch = candidateOpenids.subList(i, end);
                    QueryWrapper<Order> oq = new QueryWrapper<Order>()
                            .select(
                                    "openid AS openid",
                                    "SUM(IFNULL(sett_amount,0)-IFNULL(discount_amount,0)+IFNULL(service_fee,0)-IFNULL(refund_amount,0)-IFNULL(pay_amount_gift,0)) AS total_pay")
                            .eq("transac_status", "success")
                            .isNotNull("openid")
                            .ne("openid", "")
                            .in("openid", batch)
                            .groupBy("openid");
                    AdminOrderShopScope.apply(oq, httpServletRequest, consumeShopScope);
                    List<Map<String, Object>> rows = orderMapper.selectMaps(oq);
                    if (rows != null) {
                        for (Map<String, Object> row : rows) {
                            String openid = asText(row.get("openid"));
                            Double totalPay = asDouble(row.get("total_pay"));
                            if (StringUtils.hasText(openid) && totalPay != null) {
                                userConsumeMap.put(openid.trim(), totalPay);
                            }
                        }
                    }
                }
            }
        }

        List<User> targetUsers = new ArrayList<>();
        int openidReadyCount = 0;
        for (User user : candidateUsers) {
            if (user == null || !StringUtils.hasText(user.getOpenid())) {
                continue;
            }
            openidReadyCount++;
            String openid = user.getOpenid().trim();
            double totalPay = userConsumeMap.getOrDefault(openid, 0d);
            if (minConsumeAmount != null && totalPay < minConsumeAmount) {
                continue;
            }
            if (maxConsumeAmount != null && totalPay > maxConsumeAmount) {
                continue;
            }
            targetUsers.add(user);
        }
        if (targetUsers.isEmpty()) {
            return R.ok()
                    .put("couponId", couponId)
                    .put("previewOnly", previewOnly)
                    .put("candidateUserCount", candidateCount)
                    .put("openidReadyCount", openidReadyCount)
                    .put("consumeMatchedCount", 0)
                    .put("targetUserCount", 0)
                    .put("grantedCount", 0);
        }

        if (previewOnly) {
            log.info("batch-send preview: couponId={}, shopId={}, previewOnly=true, candidateUserCount={}, openidReadyCount={}, consumeMatchedCount={}, targetUserCount={}",
                    couponId, sid, candidateCount, openidReadyCount, targetUsers.size(), targetUsers.size());
            return R.ok()
                    .put("couponId", couponId)
                    .put("previewOnly", true)
                    .put("candidateUserCount", candidateCount)
                    .put("openidReadyCount", openidReadyCount)
                    .put("consumeMatchedCount", targetUsers.size())
                    .put("targetUserCount", targetUsers.size())
                    .put("grantedCount", 0);
        }

        int granted = 0;
        for (User user : targetUsers) {
            String openid = user.getOpenid() != null ? user.getOpenid().trim() : null;
            com.lanf.dto.R<Void> receiveRet = couponService.receiveCoupon(openid, couponId);
            if (receiveRet == null || receiveRet.getCode() == null || receiveRet.getCode() != 0) {
                String msg = (receiveRet != null && StringUtils.hasText(receiveRet.getMsg()))
                        ? receiveRet.getMsg()
                        : "批量发券失败";
                log.warn("batch-send failed: couponId={}, shopId={}, openid={}, reason={}", couponId, sid, openid, msg);
                return R.error(msg);
            }
            granted++;
        }
        log.info("batch-send granted: couponId={}, shopId={}, previewOnly=false, candidateUserCount={}, openidReadyCount={}, consumeMatchedCount={}, targetUserCount={}, grantedCount={}",
                couponId, sid, candidateCount, openidReadyCount, targetUsers.size(), targetUsers.size(), granted);
        return R.ok()
                .put("couponId", couponId)
                .put("previewOnly", false)
                .put("candidateUserCount", candidateCount)
                .put("openidReadyCount", openidReadyCount)
                .put("consumeMatchedCount", targetUsers.size())
                .put("targetUserCount", targetUsers.size())
                .put("grantedCount", granted);
    }

    /**
     * 删除兑换码（支持批量）。
     * 请求示例：{ "ids": [1,2,3] }
     */
    @PostMapping("/redeem-code/delete")
    @AuditLog(module = "coupon", action = "admin_coupon_redeem_delete")
    public R deleteRedeemCodes(@RequestBody Map<String, Object> body) {
        if (body == null || !(body.get("ids") instanceof List)) {
            return R.error("ids 必填，且必须为数组");
        }
        @SuppressWarnings("unchecked")
        List<Object> rawIds = (List<Object>) body.get("ids");
        if (rawIds.isEmpty()) {
            return R.error("ids 不能为空");
        }
        List<Long> ids = new java.util.ArrayList<>();
        for (Object o : rawIds) {
            if (o instanceof Number) {
                ids.add(((Number) o).longValue());
            } else if (o != null && StringUtils.hasText(o.toString())) {
                try {
                    ids.add(Long.parseLong(o.toString().trim()));
                } catch (NumberFormatException e) {
                    return R.error("ids 中存在非法数字");
                }
            }
        }
        if (ids.isEmpty()) {
            return R.error("ids 不能为空");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        for (Long id : ids) {
            CouponRedeemCode code = couponRedeemCodeMapper.selectById(id);
            if (code == null || code.getCoupon_id() == null) {
                return R.error("兑换码不存在，id=" + id);
            }
            Coupon coupon = couponMapper.selectById(code.getCoupon_id());
            if (coupon == null) {
                return R.error("兑换码关联优惠券不存在，id=" + id);
            }
            if (!CouponShopFilter.appliesToShop(coupon, sid)) {
                return R.error(4003, "兑换码不属于当前门店，id=" + id);
            }
        }
        int deleted = couponRedeemCodeMapper.delete(new QueryWrapper<CouponRedeemCode>().in("id", ids));
        return R.ok().put("deleted", deleted);
    }

    /**
     * 用户持券明细分页（按当前门店可见券模板过滤；无门店上下文则不过滤）。
     */
    @GetMapping("/user-coupon/list")
    public R userCouponList(@RequestParam(required = false) Long couponId,
                            @RequestParam(required = false) String openid,
                            @RequestParam(required = false) Integer status,
                            @RequestParam(required = false) String orderNo,
                            @RequestParam(required = false) String getTimeStart,
                            @RequestParam(required = false) String getTimeEnd,
                            @RequestParam(required = false, defaultValue = "1") Integer page,
                            @RequestParam(required = false, defaultValue = "20") Integer pageSize) {
        if (page == null || page < 1) {
            page = 1;
        }
        if (pageSize == null || pageSize < 1) {
            pageSize = 20;
        }
        if (pageSize > 200) {
            pageSize = 200;
        }
        if (status != null && status != 0 && status != 1 && status != 2) {
            return R.error("status 仅支持 0/1/2");
        }
        Date gtStart = parseDateTime(getTimeStart);
        Date gtEnd = parseDateTime(getTimeEnd);
        if (getTimeStart != null && gtStart == null) {
            return R.error("getTimeStart 格式错误");
        }
        if (getTimeEnd != null && gtEnd == null) {
            return R.error("getTimeEnd 格式错误");
        }
        if (gtStart != null && gtEnd != null && gtStart.after(gtEnd)) {
            return R.error("getTimeStart 不能晚于 getTimeEnd");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        List<Long> couponIdsFilter = null;
        if (sid != null) {
            List<Coupon> allCoupons = couponMapper.selectList(new QueryWrapper<Coupon>().orderByDesc("id"));
            couponIdsFilter = new ArrayList<>();
            if (allCoupons != null) {
                for (Coupon c : allCoupons) {
                    if (c != null && c.getId() != null && CouponShopFilter.appliesToShop(c, sid)) {
                        couponIdsFilter.add(c.getId());
                    }
                }
            }
            if (couponIdsFilter.isEmpty()) {
                Map<String, Object> empty = new HashMap<>();
                empty.put("list", Collections.emptyList());
                empty.put("total", 0);
                empty.put("page", page);
                empty.put("pageSize", pageSize);
                return R.ok(empty);
            }
        }
        if (couponId != null && couponId > 0) {
            Coupon coupon = couponMapper.selectById(couponId);
            if (coupon == null) {
                return R.error("优惠券不存在");
            }
            if (sid != null && !CouponShopFilter.appliesToShop(coupon, sid)) {
                return R.error(4003, "优惠券不属于当前门店");
            }
        }
        String orderNoLike = StringUtils.hasText(orderNo) ? orderNo.trim() : null;
        String openidTrim = StringUtils.hasText(openid) ? openid.trim() : null;
        int offset = (page - 1) * pageSize;
        long total = userCouponMapper.adminCountUserCoupons(couponIdsFilter, couponId, openidTrim, status, orderNoLike, gtStart, gtEnd);
        List<com.lanf.dto.UserCouponDTO> rows = userCouponMapper.adminUserCouponPage(
                couponIdsFilter, couponId, openidTrim, status, orderNoLike, gtStart, gtEnd, offset, pageSize);
        Map<String, Object> data = new HashMap<>();
        data.put("list", rows != null ? rows : Collections.emptyList());
        data.put("total", total);
        data.put("page", page);
        data.put("pageSize", pageSize);
        return R.ok(data);
    }

    /**
     * 定向发券：couponId + openid 或 phone（须已绑定 openid）。
     */
    @PostMapping("/user-coupon/grant")
    @AuditLog(module = "coupon", action = "admin_coupon_user_grant", target = "#p0['couponId']")
    public R userCouponGrant(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Object couponIdRaw = body.get("couponId");
        if (!(couponIdRaw instanceof Number)) {
            return R.error("couponId 必填且为数字");
        }
        long couponId = ((Number) couponIdRaw).longValue();
        Coupon coupon = couponMapper.selectById(couponId);
        if (coupon == null) {
            return R.error("优惠券不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(coupon, sid)) {
            return R.error(4003, "优惠券不属于当前门店");
        }
        String targetOpenid = asText(body.get("openid"));
        if (!StringUtils.hasText(targetOpenid)) {
            String phone = asText(body.get("phone"));
            if (!StringUtils.hasText(phone)) {
                return R.error("openid 与 phone 至少填一项");
            }
            User u = userMapper.selectOne(new QueryWrapper<User>().eq("phone", phone.trim()).last("LIMIT 1"));
            if (u == null || !StringUtils.hasText(u.getOpenid())) {
                return R.error("手机号未绑定用户");
            }
            targetOpenid = u.getOpenid().trim();
        } else {
            targetOpenid = targetOpenid.trim();
        }
        com.lanf.dto.R<Void> ret = couponService.receiveCoupon(targetOpenid, couponId);
        if (ret == null || ret.getCode() == null || ret.getCode() != 0) {
            return R.error(ret != null && StringUtils.hasText(ret.getMsg()) ? ret.getMsg() : "发券失败");
        }
        return R.ok().put("openid", targetOpenid).put("couponId", couponId);
    }

    @PostMapping(value = "/user-coupon/batch-grant-excel", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "coupon", action = "admin_coupon_user_batch_grant", target = "#p0")
    public R userCouponBatchGrantExcel(@RequestParam("couponId") Long couponId,
                                       @RequestParam("file") MultipartFile file) throws Exception {
        if (couponId == null || couponId <= 0) return R.error("couponId 必填且为正数");
        if (file == null || file.isEmpty()) return R.error("Excel 文件不能为空");
        Coupon coupon = couponMapper.selectById(couponId);
        if (coupon == null) return R.error("优惠券不存在");
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(coupon, shopId)) {
            return R.error(4003, "优惠券不属于当前门店");
        }
        ExcelOpenidParseResult parsed = parseOpenidsFromExcel(file);
        if (parsed.openids.isEmpty()) return R.error("Excel 中未读取到有效 openid");
        if (coupon.getStock() != null && coupon.getStock() != -1
                && coupon.getStock() < parsed.openids.size()) {
            return R.error("优惠券库存不足，当前库存 " + coupon.getStock()
                    + "，本次需发放 " + parsed.openids.size());
        }
        int granted = 0;
        for (String openid : parsed.openids) {
            com.lanf.dto.R<Void> result = couponService.receiveCoupon(openid, couponId);
            if (result == null || result.getCode() == null || result.getCode() != 0) {
                String message = result != null && StringUtils.hasText(result.getMsg())
                        ? result.getMsg() : "发券失败";
                throw new IllegalStateException("批量发券失败，openid=" + openid + "，原因：" + message);
            }
            granted++;
        }
        return R.ok().put("couponId", couponId).put("fileName", file.getOriginalFilename())
                .put("readCount", parsed.readCount).put("duplicateCount", parsed.duplicateCount)
                .put("targetOpenidCount", parsed.openids.size()).put("grantedCount", granted);
    }

    /**
     * 作废用户券（仅未使用 status=0）。
     */
    @PostMapping("/user-coupon/void")
    @AuditLog(module = "coupon", action = "admin_coupon_user_void", target = "#p0['id']")
    public R userCouponVoid(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Object idRaw = body.get("userCouponId");
        if (!(idRaw instanceof Number)) {
            return R.error("userCouponId 必填且为数字");
        }
        long userCouponId = ((Number) idRaw).longValue();
        UserCoupon uc = userCouponMapper.selectById(userCouponId);
        if (uc == null) {
            return R.error("用户券不存在");
        }
        Coupon coupon = uc.getCoupon_id() != null ? couponMapper.selectById(uc.getCoupon_id()) : null;
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (coupon == null) {
            return R.error("关联优惠券不存在");
        }
        if (!CouponShopFilter.appliesToShop(coupon, sid)) {
            return R.error(4003, "不属于当前门店数据范围");
        }
        if (uc.getStatus() == null || uc.getStatus() != 0) {
            return R.error("仅未使用的用户券可作废");
        }
        uc.setStatus(2);
        userCouponMapper.updateById(uc);
        return R.ok();
    }

    /**
     * 解除用户券与订单号的占用（仅未使用且已绑定 order_no）。
     */
    @PostMapping("/user-coupon/unbind")
    @AuditLog(module = "coupon", action = "admin_coupon_user_unbind")
    public R userCouponUnbind(@RequestBody Map<String, Object> body) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Object idRaw = body.get("userCouponId");
        if (!(idRaw instanceof Number)) {
            return R.error("userCouponId 必填且为数字");
        }
        long userCouponId = ((Number) idRaw).longValue();
        UserCoupon uc = userCouponMapper.selectById(userCouponId);
        if (uc == null) {
            return R.error("用户券不存在");
        }
        Coupon coupon = uc.getCoupon_id() != null ? couponMapper.selectById(uc.getCoupon_id()) : null;
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (coupon == null) {
            return R.error("关联优惠券不存在");
        }
        if (!CouponShopFilter.appliesToShop(coupon, sid)) {
            return R.error(4003, "不属于当前门店数据范围");
        }
        if (uc.getStatus() == null || uc.getStatus() != 0) {
            return R.error("仅未使用的用户券可解绑");
        }
        if (!StringUtils.hasText(uc.getOrder_no())) {
            return R.error("该券未占用订单");
        }
        uc.setOrder_no(null);
        userCouponMapper.updateById(uc);
        return R.ok();
    }

    /**
     * 兑换码核销展示（后台查询核销情况）。
     */
    @GetMapping("/redeem-code/list")
    public R listRedeemCodes(@RequestParam(required = false) Long couponId,
                             @RequestParam(required = false) Integer status,
                             @RequestParam(required = false) String startTime,
                             @RequestParam(required = false) String endTime,
                             @RequestParam(required = false, defaultValue = "1") Integer page,
                             @RequestParam(required = false, defaultValue = "20") Integer pageSize) {
        if (page == null || page < 1) page = 1;
        if (pageSize == null || pageSize < 1) pageSize = 20;
        if (pageSize > 200) pageSize = 200;
        if (status != null && status != 0 && status != 1) {
            return R.error("status 仅支持 0（未核销）或 1（已核销）");
        }
        Date usedTimeStart = parseDateTime(startTime);
        Date usedTimeEnd = parseDateTime(endTime);
        if (startTime != null && usedTimeStart == null) {
            return R.error("startTime 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (endTime != null && usedTimeEnd == null) {
            return R.error("endTime 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (usedTimeStart != null && usedTimeEnd != null && usedTimeStart.after(usedTimeEnd)) {
            return R.error("startTime 不能晚于 endTime");
        }

        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        final Set<Long> allowedCouponIds;
        if (sid != null) {
            List<Coupon> allCoupons = couponMapper.selectList(new QueryWrapper<Coupon>().orderByDesc("id"));
            allowedCouponIds = allCoupons.stream()
                    .filter(c -> c != null && c.getId() != null && CouponShopFilter.appliesToShop(c, sid))
                    .map(Coupon::getId)
                    .collect(Collectors.toCollection(HashSet::new));
        } else {
            allowedCouponIds = null;
        }

        if (couponId != null && couponId > 0) {
            Coupon coupon = couponMapper.selectById(couponId);
            if (coupon == null) {
                return R.error("优惠券不存在");
            }
            if (sid != null && !CouponShopFilter.appliesToShop(coupon, sid)) {
                return R.error(4003, "优惠券不属于当前门店");
            }
        }

        QueryWrapper<CouponRedeemCode> qw = new QueryWrapper<CouponRedeemCode>().orderByDesc("id");
        if (couponId != null && couponId > 0) {
            qw.eq("coupon_id", couponId);
        }
        if (status != null) {
            qw.eq("status", status);
        }
        if (usedTimeStart != null) {
            qw.ge("used_time", usedTimeStart);
        }
        if (usedTimeEnd != null) {
            qw.le("used_time", usedTimeEnd);
        }
        List<CouponRedeemCode> all = couponRedeemCodeMapper.selectList(qw);
        List<CouponRedeemCode> filtered = all;
        if (allowedCouponIds != null) {
            filtered = all.stream()
                    .filter(rc -> rc != null && rc.getCoupon_id() != null && allowedCouponIds.contains(rc.getCoupon_id()))
                    .collect(Collectors.toList());
        }

        int total = filtered.size();
        int fromIndex = (page - 1) * pageSize;
        int toIndex = Math.min(fromIndex + pageSize, total);
        List<CouponRedeemCode> pageList = fromIndex >= total ? new ArrayList<>() : filtered.subList(fromIndex, toIndex);

        List<Map<String, Object>> rows = new ArrayList<>();
        for (CouponRedeemCode rc : pageList) {
            Map<String, Object> row = new HashMap<>();
            row.put("id", rc.getId());
            row.put("coupon_id", rc.getCoupon_id());
            row.put("redeem_code", rc.getRedeem_code());
            row.put("status", rc.getStatus());
            row.put("used_openid", rc.getUsed_openid());
            row.put("used_time", rc.getUsed_time());
            row.put("create_time", rc.getCreate_time());
            rows.add(row);
        }

        return R.ok()
                .put("list", rows)
                .put("total", total)
                .put("page", page)
                .put("pageSize", pageSize);
    }

    /**
     * 兑换码小程序二维码：返回图片二进制（前端自行展示/下载）。
     */
    @GetMapping("/redeem-code/qrcode")
    public ResponseEntity<byte[]> redeemCodeQrcode(@RequestParam("redeem_code") String redeemCode) {
        if (!StringUtils.hasText(redeemCode)) {
            return ResponseEntity.badRequest().build();
        }
        CouponRedeemCode code = couponRedeemCodeMapper.selectOne(new QueryWrapper<CouponRedeemCode>()
                .eq("redeem_code", redeemCode.trim())
                .last("LIMIT 1"));
        if (code == null || code.getCoupon_id() == null) {
            return ResponseEntity.notFound().build();
        }
        Coupon coupon = couponMapper.selectById(code.getCoupon_id());
        if (coupon == null) {
            return ResponseEntity.notFound().build();
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(coupon, sid)) {
            return ResponseEntity.status(403).build();
        }
        String accessToken = getAccessToken();
        if (!StringUtils.hasText(accessToken)) {
            return ResponseEntity.status(500).build();
        }
        Map<String, Object> body = new HashMap<>();
        body.put("path", "pages/index/index?redeem_code=" + redeemCode.trim());
        String url = "https://api.weixin.qq.com/wxa/getwxacode?access_token=" + accessToken;
        byte[] imageBytes = getWechatQrcodeByHttpClient(url, body);
        if (imageBytes == null || imageBytes.length == 0) {
            return ResponseEntity.status(500).build();
        }
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_TYPE, MediaType.IMAGE_PNG_VALUE)
                .body(imageBytes);
    }

    private Date parseDateTime(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String txt = raw.trim();
        String[] patterns = new String[]{"yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"};
        for (String p : patterns) {
            try {
                return new SimpleDateFormat(p).parse(txt);
            } catch (ParseException ignore) {
            }
        }
        return null;
    }

    private String asText(Object v) {
        if (v == null) {
            return null;
        }
        String s = v.toString();
        return StringUtils.hasText(s) ? s.trim() : null;
    }

    private Double asDouble(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Number) {
            return ((Number) v).doubleValue();
        }
        if (!StringUtils.hasText(v.toString())) {
            return null;
        }
        try {
            return Double.parseDouble(v.toString().trim());
        } catch (Exception e) {
            return null;
        }
    }

    private boolean toBoolean(Object raw) {
        if (raw instanceof Boolean) {
            return (Boolean) raw;
        }
        if (raw == null) {
            return false;
        }
        String s = raw.toString().trim();
        return "true".equalsIgnoreCase(s) || "1".equals(s) || "yes".equalsIgnoreCase(s);
    }

    private Set<Integer> parseUserTypes(Map<String, Object> body) {
        Set<Integer> userTypes = new HashSet<>();
        Object one = body.get("userType");
        if (one != null) {
            userTypes.add(parseUserTypeValue(one, "userType"));
        }
        Object many = body.get("userTypes");
        if (many != null && !(many instanceof List)) {
            throw new IllegalArgumentException("userTypes 必须为数组");
        }
        if (many instanceof List) {
            @SuppressWarnings("unchecked")
            List<Object> arr = (List<Object>) many;
            for (Object o : arr) {
                if (o == null) {
                    continue;
                }
                userTypes.add(parseUserTypeValue(o, "userTypes"));
            }
        }
        return userTypes;
    }

    private ExcelOpenidParseResult parseOpenidsFromExcel(MultipartFile file) throws Exception {
        DataFormatter formatter = new DataFormatter();
        try (InputStream input = file.getInputStream(); Workbook workbook = WorkbookFactory.create(input)) {
            if (workbook.getNumberOfSheets() == 0) throw new IllegalArgumentException("Excel 文件没有工作表");
            Sheet sheet = workbook.getSheetAt(0);
            int headerRow = -1;
            int openidColumn = -1;
            for (int i = sheet.getFirstRowNum(); i <= Math.min(sheet.getLastRowNum(), 20); i++) {
                Row row = sheet.getRow(i);
                if (row == null) continue;
                for (int column = 0; column < row.getLastCellNum(); column++) {
                    String header = formatter.formatCellValue(row.getCell(column));
                    if ("openid".equals(normalizeExcelHeader(header))) {
                        headerRow = i;
                        openidColumn = column;
                        break;
                    }
                }
                if (openidColumn >= 0) break;
            }
            if (openidColumn < 0) throw new IllegalArgumentException("Excel 中未找到 openid 表头");
            LinkedHashSet<String> unique = new LinkedHashSet<>();
            int readCount = 0;
            for (int i = headerRow + 1; i <= sheet.getLastRowNum(); i++) {
                Row row = sheet.getRow(i);
                if (row == null) continue;
                String openid = formatter.formatCellValue(row.getCell(openidColumn));
                if (!StringUtils.hasText(openid)) continue;
                readCount++;
                unique.add(openid.trim());
            }
            ExcelOpenidParseResult result = new ExcelOpenidParseResult();
            result.readCount = readCount;
            result.duplicateCount = readCount - unique.size();
            result.openids = new ArrayList<>(unique);
            return result;
        }
    }

    private static String normalizeExcelHeader(String value) {
        return value == null ? "" : value.trim().replace("_", "").replace(" ", "").toLowerCase();
    }

    private static final class ExcelOpenidParseResult {
        private int readCount;
        private int duplicateCount;
        private List<String> openids = Collections.emptyList();
    }

    private int parseUserTypeValue(Object raw, String field) {
        int val;
        if (raw instanceof Number) {
            val = ((Number) raw).intValue();
        } else if (raw != null && StringUtils.hasText(raw.toString())) {
            try {
                val = Integer.parseInt(raw.toString().trim());
            } catch (Exception ignored) {
                throw new IllegalArgumentException(field + " 存在非法值：" + raw);
            }
        } else {
            throw new IllegalArgumentException(field + " 存在非法值：" + raw);
        }
        if (val != 0 && val != 1) {
            throw new IllegalArgumentException(field + " 仅支持 0（普通）或 1（会员）");
        }
        return val;
    }

    private String getAccessToken() {
        String url = "https://api.weixin.qq.com/cgi-bin/token"
                + "?grant_type=client_credential&appid=" + weixinProperties.getAppid()
                + "&secret=" + weixinProperties.getSecret();
        String token = httpClientUtil.sendHttpGet(url);
        if (!StringUtils.hasText(token)) {
            return null;
        }
        JSONObject jsonObject = JSON.parseObject(token);
        Object accessToken = jsonObject.get("access_token");
        return accessToken != null ? accessToken.toString() : null;
    }

    private byte[] getWechatQrcodeByHttpClient(String url, Map<String, Object> body) {
        CloseableHttpClient httpClient = HttpClientBuilder.create().build();
        HttpPost httpPost = new HttpPost(url);
        try {
            StringEntity entity = new StringEntity(JSONObject.toJSONString(body));
            entity.setContentType("image/png");
            httpPost.setEntity(entity);
            HttpResponse response = httpClient.execute(httpPost);
            try (InputStream inputStream = response.getEntity().getContent();
                 ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[1024];
                int len;
                while ((len = inputStream.read(buffer)) != -1) {
                    out.write(buffer, 0, len);
                }
                return out.toByteArray();
            }
        } catch (Exception e) {
            return null;
        }
    }

    /** 编辑 */
    @PostMapping("/update")
    @AuditLog(module = "coupon", action = "admin_coupon_update", target = "#p0.id")
    public R update(@RequestBody Coupon coupon) {
        if (coupon == null || coupon.getId() == null || coupon.getId() <= 0) {
            return R.error("id 不能为空");
        }
        Coupon existing = couponMapper.selectById(coupon.getId());
        if (existing == null) {
            return R.error("优惠券不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(existing, sid)) {
            return R.error(4003, "优惠券不属于当前门店");
        }
        coupon.setUpdate_time(new Date());
        couponMapper.updateById(coupon);
        return R.ok();
    }

    /** 删除（物理删除；如需保留历史建议改为下架 status=2） */
    @GetMapping("/delete")
    public R delete(@RequestParam Long id) {
        if (id == null || id <= 0) {
            return R.error("id 不能为空");
        }
        Coupon existing = couponMapper.selectById(id);
        if (existing == null) {
            return R.error("优惠券不存在");
        }
        Integer sid = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (!CouponShopFilter.appliesToShop(existing, sid)) {
            return R.error(4003, "优惠券不属于当前门店");
        }
        boolean ok = couponMapper.deleteById(id) > 0;
        return ok ? R.ok() : R.error("删除失败");
    }
}

