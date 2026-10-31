package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.entity.MemberRecharge;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.entity.InviteRecord;
import com.lanf.entity.UserCoupon;
import com.lanf.mapper.InviteRecordMapper;
import com.lanf.mapper.ShopMemberWalletMapper;
import com.lanf.mapper.UserCouponMapper;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import com.lanf.service.IUserService;
import com.lanf.util.AdminOrderShopScope;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderNetRevenue;
import com.lanf.security.AdminShopScopeGuard;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 会员营销（收银系统扩展）
 */
@RestController
@RequestMapping("/admin/member")
public class AdminMemberController {

    /** 与 C 端 {@code POST /order/recharge} 一致：单笔本金下限（元） */
    private static final BigDecimal MEMBER_RECHARGE_MIN_YUAN = new BigDecimal("50.00");

    /** 充值列表排序字段白名单（防注入） */
    private static final Set<String> RECHARGE_SORT_COLUMNS = new HashSet<>(Arrays.asList(
            "id", "created_at", "updated_at", "pay_time",
            "recharge_amount", "gift_amount", "total_amount", "order_no"));

    private static String strBodyField(Map<String, Object> body, String key) {
        if (body == null) {
            return null;
        }
        Object v = body.get(key);
        if (v == null) {
            return null;
        }
        String s = v.toString().trim();
        return s.isEmpty() ? null : s;
    }

    /** 解析正整数门店ID：兼容 JSON 数字与字符串，非法或非正返回 null */
    private static Integer parsePositiveInt(Object raw) {
        if (raw == null) {
            return null;
        }
        try {
            int v = raw instanceof Number ? ((Number) raw).intValue() : Integer.parseInt(raw.toString().trim());
            return v > 0 ? v : null;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** 解析金额：兼容 JSON 数字与字符串，避免 (String) 强转与非法格式导致 500 */
    private static BigDecimal parseMoney(Object raw, String fieldLabel) {
        if (raw == null) {
            return null;
        }
        try {
            if (raw instanceof BigDecimal) {
                return ((BigDecimal) raw).setScale(2, RoundingMode.HALF_UP);
            }
            if (raw instanceof Number) {
                return BigDecimal.valueOf(((Number) raw).doubleValue()).setScale(2, RoundingMode.HALF_UP);
            }
            String s = raw.toString().trim();
            if (s.isEmpty()) {
                return null;
            }
            return new BigDecimal(s).setScale(2, RoundingMode.HALF_UP);
        } catch (NumberFormatException | ArithmeticException e) {
            throw new IllegalArgumentException(fieldLabel + " 格式非法：" + raw);
        }
    }

    @Autowired
    private IOrderService orderService;
    @Autowired
    private IOrderDetailService orderDetailService;
    @Autowired
    private IUserService userService;
    @Autowired
    private IMemberRechargeService memberRechargeService;
    @Autowired
    private com.lanf.service.IShiftService shiftService;
    @Autowired
    private InviteRecordMapper inviteRecordMapper;
    @Autowired
    private UserCouponMapper userCouponMapper;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private AdminShopScopeGuard adminShopScopeGuard;
    @Autowired(required = false)
    private com.lanf.service.IShopMemberWalletService shopMemberWalletService;
    @Autowired(required = false)
    private com.lanf.service.IAdminShopAccessService adminShopAccessService;
    @Autowired
    private AdminOrderController adminOrderController;

    /**
     * 会员列表分页与搜索（支持多门店隔离与全量模式）。
     */
    @PostMapping("/list")
    public R memberList(@RequestBody(required = false) Map<String, Object> body) {
        return adminOrderController.getUserInfo(body);
    }

    @GetMapping("/list")
    public R memberListGet(
            @RequestParam(required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(required = false, defaultValue = "20") Integer pageSize,
            @RequestParam(required = false) String query,
            @RequestParam(required = false) String phone,
            @RequestParam(required = false) Integer shopId,
            @RequestParam(required = false) Boolean allShops) {
        Map<String, Object> body = new HashMap<>();
        body.put("pageNum", pageNum);
        body.put("pageSize", pageSize);
        if (query != null) body.put("query", query);
        if (phone != null) body.put("phone", phone);
        if (shopId != null) body.put("shopId", shopId);
        if (allShops != null) body.put("allShops", allShops);
        return adminOrderController.getUserInfo(body);
    }

    /**
     * 会员充值（对外只传手机号，后端内部用 openid 关联）
     */
    @PostMapping("/recharge")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "member", action = "admin_member_recharge", target = "#p0['userId']")
    public R recharge(@RequestBody Map<String, Object> body) {
        String phone = strBodyField(body, "phone");
        if (phone == null) {
            return R.error("手机号不能为空");
        }
        BigDecimal amount;
        try {
            amount = parseMoney(body != null ? body.get("amount") : null, "充值金额 amount");
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
        if (amount == null) {
            return R.error("充值金额不能为空");
        }
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            return R.error("充值金额必须大于0");
        }
        if (amount.compareTo(MEMBER_RECHARGE_MIN_YUAN) < 0) {
            return R.error("会员充值单笔不得低于50元");
        }
        // 根据手机号查用户，再取 openid 作为内部主键
        User user = userService.getUserByPhone(phone);
        if (user == null || user.getOpenid() == null || user.getOpenid().isEmpty()) {
            return R.error("用户不存在或未绑定openid");
        }

        BigDecimal giftRecorded = BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        if (body != null && body.get("gift_amount") != null) {
            BigDecimal gift;
            try {
                gift = parseMoney(body.get("gift_amount"), "赠送金额 gift_amount");
            } catch (IllegalArgumentException e) {
                return R.error(e.getMessage());
            }
            if (gift != null && gift.compareTo(BigDecimal.ZERO) > 0) {
                giftRecorded = gift;
            }
        }
        Integer requestedShopId = parsePositiveInt(body != null ? body.get("shop_id") : null);
        int[] holder = new int[1];
        R guardR = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
        if (guardR != null) {
            return guardR;
        }
        Integer rechargeShopId = holder[0];
        if (rechargeShopId == null || rechargeShopId <= 0) {
            return R.error(4003, "会员充值必须明确归属门店");
        }
        if (!userService.addBalanceAndGift(user.getId(), amount, giftRecorded)) {
            return R.error("写入用户本金/赠送金失败");
        }
        if (shopMemberWalletService != null) {
            shopMemberWalletService.addBalance(user.getId(), rechargeShopId, amount, giftRecorded);
        }
        Integer operatorId = (Integer) httpServletRequest.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        Long drawerSessionId = null;
        if (operatorId != null) {
            com.lanf.entity.Shift activeShift = shiftService.getOne(new QueryWrapper<com.lanf.entity.Shift>()
                    .eq("admin_id", operatorId)
                    .eq("shop_id", rechargeShopId)
                    .isNull("end_time")
                    .orderByDesc("start_time")
                    .last("LIMIT 1"), false);
            if (activeShift != null) {
                drawerSessionId = activeShift.getDrawer_session_id();
            }
        }
        memberRechargeService.recordAdminSuccess(user.getId(), user.getOpenid(), rechargeShopId,
                operatorId, drawerSessionId, amount, giftRecorded,
                "后台人工充值，手机号 " + phone);
        return R.ok();
    }

    /**
     * 会员充值流水列表（分页、多条件筛选、排序）。
     * <p>
     * 门店：若请求解析出当前 {@code X-Shop-Id} 且未传 {@code allShops=true}，则默认仅 {@code shop_id} 等于该店的记录；
     * 传 {@code shopId} 时优先生效精确按店筛选。{@code allShops=true} 时忽略门店上下文（总部视角）。
     * </p>
     */
    @GetMapping("/recharge/list")
    public R rechargeList(
            @RequestParam(required = false) String phone,
            @RequestParam(required = false) String openid,
            @RequestParam(required = false) Integer userId,
            @RequestParam(required = false) String orderNo,
            @RequestParam(required = false) String transactionId,
            @RequestParam(required = false) String channel,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) Integer shopId,
            @RequestParam(required = false) Boolean allShops,
            @RequestParam(required = false) String payTimeStart,
            @RequestParam(required = false) String payTimeEnd,
            @RequestParam(required = false) String createdStart,
            @RequestParam(required = false) String createdEnd,
            @RequestParam(required = false) BigDecimal minRechargeAmount,
            @RequestParam(required = false) BigDecimal maxRechargeAmount,
            @RequestParam(required = false) BigDecimal minTotalAmount,
            @RequestParam(required = false) BigDecimal maxTotalAmount,
            @RequestParam(required = false, defaultValue = "created_at") String sortField,
            @RequestParam(required = false, defaultValue = "desc") String sortOrder,
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
        QueryWrapper<MemberRecharge> q = new QueryWrapper<>();
        if (StringUtils.hasText(phone)) {
            User u = userService.getUserByPhone(phone.trim());
            if (u == null || !StringUtils.hasText(u.getOpenid())) {
                return R.error("用户不存在或未绑定openid");
            }
            q.eq("openid", u.getOpenid().trim());
        } else if (StringUtils.hasText(openid)) {
            q.eq("openid", openid.trim());
        }
        if (userId != null && userId > 0) {
            q.eq("user_id", userId);
        }
        if (StringUtils.hasText(orderNo)) {
            q.like("order_no", orderNo.trim());
        }
        if (StringUtils.hasText(transactionId)) {
            q.like("transaction_id", transactionId.trim());
        }
        if (StringUtils.hasText(channel)) {
            q.eq("channel", channel.trim().toLowerCase());
        }
        if (StringUtils.hasText(status)) {
            q.eq("status", status.trim().toLowerCase());
        }
        Date payStart = parseDateTimeLoose(payTimeStart);
        Date payEnd = parseDateTimeLoose(payTimeEnd);
        if (payTimeStart != null && payStart == null) {
            return R.error("payTimeStart 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (payTimeEnd != null && payEnd == null) {
            return R.error("payTimeEnd 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (payStart != null) {
            q.ge("pay_time", payStart);
        }
        if (payEnd != null) {
            q.le("pay_time", payEnd);
        }
        Date cStart = parseDateTimeLoose(createdStart);
        Date cEnd = parseDateTimeLoose(createdEnd);
        if (createdStart != null && cStart == null) {
            return R.error("createdStart 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (createdEnd != null && cEnd == null) {
            return R.error("createdEnd 格式错误，支持 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (cStart != null) {
            q.ge("created_at", cStart);
        }
        if (cEnd != null) {
            q.le("created_at", cEnd);
        }
        if (minRechargeAmount != null) {
            q.ge("recharge_amount", minRechargeAmount);
        }
        if (maxRechargeAmount != null) {
            q.le("recharge_amount", maxRechargeAmount);
        }
        if (minTotalAmount != null) {
            q.ge("total_amount", minTotalAmount);
        }
        if (maxTotalAmount != null) {
            q.le("total_amount", maxTotalAmount);
        }
        if (Boolean.TRUE.equals(allShops)) {
            R scopeError = adminShopScopeGuard.requireHeadquarters();
            if (scopeError != null) {
                return scopeError;
            }
        } else {
            int[] targetShop = new int[1];
            R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, targetShop);
            if (scopeError != null) {
                return scopeError;
            }
            if (targetShop[0] > 0) {
                int sid = targetShop[0];
                // 后台人工充值历史流水 shop_id 可能为 NULL（旧数据未落门店），按渠道放开以免整店列表看不到 admin 记录
                q.and(w -> w.eq("shop_id", sid)
                        .or(n -> n.isNull("shop_id").eq("channel", "admin")));
            }
        }
        applyRechargeListOrderBy(q, sortField, sortOrder);
        IPage<MemberRecharge> pg = memberRechargeService.page(new Page<>(page, pageSize), q);
        if (memberRechargeService != null) {
            memberRechargeService.attachMemberPhones(pg.getRecords());
        }
        return R.ok()
                .put("list", pg.getRecords())
                .put("total", pg.getTotal())
                .put("page", pg.getCurrent())
                .put("pageSize", pg.getSize());
    }

    private static void applyRechargeListOrderBy(QueryWrapper<MemberRecharge> q, String sortField, String sortOrder) {
        String col = sortField != null ? sortField.trim() : "created_at";
        if (!RECHARGE_SORT_COLUMNS.contains(col)) {
            col = "created_at";
        }
        boolean asc = "asc".equalsIgnoreCase(sortOrder != null ? sortOrder.trim() : "desc");
        if (asc) {
            q.orderByAsc(col);
        } else {
            q.orderByDesc(col);
        }
    }

    private static Date parseDateTimeLoose(String raw) {
        if (!StringUtils.hasText(raw)) {
            return null;
        }
        String txt = raw.trim();
        String[] patterns = new String[]{"yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"};
        for (String p : patterns) {
            try {
                Date d = new SimpleDateFormat(p).parse(txt);
                if ("yyyy-MM-dd".equals(p) && !txt.contains(":")) {
                    return new Date(d.getTime() + 24L * 60L * 60L * 1000L - 1000L);
                }
                return d;
            } catch (ParseException ignore) {
            }
        }
        return null;
    }

    /**
     * 后台扣减用户余额（按手机号定位用户）
     */
    @PostMapping("/balance/deduct")
    @Transactional(rollbackFor = Exception.class)
    @AuditLog(module = "member", action = "admin_member_balance_deduct", target = "#p0['userId']")
    public R deductBalance(@RequestBody Map<String, Object> body) {
        String reason = strBodyField(body, "reason");
        if (reason == null) {
            reason = strBodyField(body, "remark");
        }
        if (reason == null || reason.trim().isEmpty()) {
            return R.error("扣减原因不能为空");
        }
        Integer requestedShopId = parsePositiveInt(body != null ? body.get("shop_id") : null);
        int[] holder = new int[1];
        R guardR = adminShopScopeGuard.resolveTargetShopId(requestedShopId, holder);
        if (guardR != null) {
            return guardR;
        }
        Integer deductShopId = holder[0];
        if (deductShopId == null || deductShopId <= 0) {
            return R.error(4003, "扣减余额必须明确归属门店");
        }
        String phone = strBodyField(body, "phone");
        if (phone == null) {
            return R.error("手机号不能为空");
        }
        BigDecimal amount;
        try {
            amount = parseMoney(body != null ? body.get("amount") : null, "扣减金额 amount");
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
        if (amount == null) {
            return R.error("扣减金额不能为空");
        }
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            return R.error("扣减金额必须大于0");
        }
        User user = userService.getUserByPhone(phone);
        if (user == null || user.getOpenid() == null || user.getOpenid().isEmpty()) {
            return R.error("用户不存在或未绑定openid");
        }
        if (shopMemberWalletService != null && !shopMemberWalletService.isCrossShopBalanceEnabled(deductShopId)) {
            BigDecimal storeBal = shopMemberWalletService.getAvailableBalanceForShop(user.getId(), deductShopId);
            if (storeBal.compareTo(amount) < 0) {
                return R.error("本店会员储值余额不足（您在其他门店的充值余额不可跨店使用）");
            }
        }
        if (!userService.subtractWalletProportionalIfEnough(user.getId(), amount)) {
            return R.error("余额不足");
        }
        if (shopMemberWalletService != null) {
            shopMemberWalletService.deductBalance(user.getId(), deductShopId, amount);
        }
        Integer operatorId = (Integer) httpServletRequest.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        memberRechargeService.recordAdminSuccess(user.getId(), user.getOpenid(), deductShopId, operatorId, null,
                amount.negate(), BigDecimal.ZERO, "后台人工扣减余额，原因：" + reason.trim());
        return R.ok();
    }

    /**
     * 会员消费记录（入参手机号，内部转 openid 查询订单）
     */
    public R consumption(String phone, Integer limit, String startTime, String endTime, String orderShopScope) {
        return consumption(phone, limit, startTime, endTime, orderShopScope, null, null);
    }

    @GetMapping("/consumption")
    public R consumption(@RequestParam(required = false) String phone,
                         @RequestParam(required = false) Integer limit,
                         @RequestParam(required = false) String startTime,
                         @RequestParam(required = false) String endTime,
                         @RequestParam(required = false, defaultValue = "accessible") String orderShopScope,
                         @RequestParam(required = false) Integer shopId,
                         @RequestParam(required = false) Boolean allShops) {
        if (phone == null || phone.trim().isEmpty()) {
            return R.error("手机号不能为空");
        }
        User user = userService.getUserByPhone(phone.trim());
        if (user == null || user.getOpenid() == null || user.getOpenid().isEmpty()) {
            return R.error("用户不存在或未绑定openid");
        }
        int[] holder = new int[1];
        if (adminShopScopeGuard != null) {
            if (Boolean.TRUE.equals(allShops)) {
                R guardR = adminShopScopeGuard.requireHeadquarters();
                if (guardR != null) return guardR;
                holder[0] = 0;
            } else if (shopId != null) {
                R guardR = adminShopScopeGuard.resolveTargetShopId(shopId, holder);
                if (guardR != null) return guardR;
            }
        }
        Integer targetShopId = holder[0] > 0 ? Integer.valueOf(holder[0]) : shopId;
        String openid = user.getOpenid().trim();
        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .and(w -> w.eq("openid", openid).or().eq("pay_openid", openid));
        AdminOrderShopScope.apply(q, httpServletRequest, Boolean.TRUE.equals(allShops) ? "all" : orderShopScope, targetShopId);
        if (startTime != null && !startTime.isEmpty()) q.ge("pay_time", startTime);
        if (endTime != null && !endTime.isEmpty()) q.le("pay_time", endTime);
        q.orderByDesc("pay_time");
        if (limit != null && limit > 0) {
            q.last("LIMIT " + limit);
        }
        List<Order> list = orderService.list(q);
        List<Map<String, Object>> resultList = new ArrayList<>();
        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        for (Order o : list) {
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("id", o.getId());
            item.put("order_no", o.getOrder_no());
            item.put("orderNo", o.getOrder_no());
            double net = OrderNetRevenue.netRevenueYuan(o);
            item.put("amount", net);
            item.put("actual_amount", net);
            item.put("paid_amount", net);
            item.put("net_amount", net);
            item.put("sett_amount", o.getSett_amount());
            item.put("discount_amount", o.getDiscount_amount());
            item.put("service_fee", o.getService_fee());
            item.put("refund_amount", o.getRefund_amount());
            item.put("pay_time", o.getPay_time() != null ? sdf.format(o.getPay_time()) : (o.getOrder_time() != null ? sdf.format(o.getOrder_time()) : null));
            item.put("order_time", o.getOrder_time() != null ? sdf.format(o.getOrder_time()) : null);
            item.put("table_number", o.getTable_number());
            item.put("tableNumber", o.getTable_number());
            item.put("payment_method", o.getPayment_method());
            item.put("dineInOrTakeOut", o.getDineInOrTakeOut());
            item.put("order_type", o.getDineInOrTakeOut());
            resultList.add(item);
        }
        return R.ok().put("list", resultList).put("data", resultList);
    }

    /**
     * 会员画像（入参手机号，内部转 openid 统计）：基础标签、消费行为、菜品偏好、价值分层、推荐画像
     */
    public R profile(String phone, String orderShopScope) {
        return profile(phone, orderShopScope, null, null);
    }

    @GetMapping("/profile")
    public R profile(@RequestParam(required = false) String phone,
                     @RequestParam(required = false, defaultValue = "accessible") String orderShopScope,
                     @RequestParam(required = false) Integer shopId,
                     @RequestParam(required = false) Boolean allShops) {
        if (phone == null || phone.trim().isEmpty()) {
            return R.error("手机号不能为空");
        }
        User user = userService.getUserByPhone(phone.trim());
        if (user == null || user.getOpenid() == null || user.getOpenid().isEmpty()) {
            return R.error("用户不存在或未绑定openid");
        }
        int[] holder = new int[1];
        if (adminShopScopeGuard != null) {
            if (Boolean.TRUE.equals(allShops)) {
                R guardR = adminShopScopeGuard.requireHeadquarters();
                if (guardR != null) return guardR;
                holder[0] = 0;
            } else if (shopId != null) {
                R guardR = adminShopScopeGuard.resolveTargetShopId(shopId, holder);
                if (guardR != null) return guardR;
            }
        }
        Integer targetShopId = holder[0] > 0 ? Integer.valueOf(holder[0]) : shopId;
        String openid = user.getOpenid().trim();
        QueryWrapper<Order> oq = new QueryWrapper<Order>()
                .eq("transac_status", "success")
                .and(w -> w.eq("openid", openid).or().eq("pay_openid", openid))
                .orderByDesc("pay_time");
        AdminOrderShopScope.apply(oq, httpServletRequest, Boolean.TRUE.equals(allShops) ? "all" : orderShopScope, targetShopId);
        List<Order> orders = orderService.list(oq);
        int count = orders.size();
        double totalAmount = orders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum();
        double avgOrderValue = count > 0 ? totalAmount / count : 0;

        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        String lastVisit = null;
        if (!orders.isEmpty()) {
            Order latest = orders.get(0);
            Date latestTime = latest.getPay_time() != null ? latest.getPay_time() : latest.getOrder_time();
            if (latestTime != null) {
                lastVisit = sdf.format(latestTime);
            }
        }

        // D024：对齐用户列表统计口径的 4 个聚合字段（consume_amount/last_consume_time 复用订单统计；邀请数/可用券数按列表口径查询）
        double consumeAmount = Math.round(totalAmount * 100) / 100.0;
        Integer inviteCount = inviteRecordMapper.selectCount(new QueryWrapper<InviteRecord>()
                .apply("TRIM(inviter_openid) = {0}", openid)
                .isNotNull("invitee_openid")
                .apply("TRIM(invitee_openid) <> ''"));
        Integer couponCount = userCouponMapper.selectCount(new QueryWrapper<UserCoupon>()
                .eq("user_openid", openid)
                .eq("status", 0)
                .and(w -> w.isNull("expire_time").or().gt("expire_time", new Date()))
                .inSql("coupon_id", "SELECT id FROM t_coupon WHERE end_time IS NULL OR end_time >= NOW()"));

        // 一、会员基础标签（登记/小程序可收集；当前仅手机号、年龄可推断）
        Map<String, Object> basicTags = new LinkedHashMap<>();
        basicTags.put("gender", null); // 男/女，未登记为 null
        basicTags.put("ageRange", inferAgeRange(user.getBirthday())); // 18-25/26-35/36-45/45+
        basicTags.put("hasPhone", (user.getPhone() != null && !user.getPhone().isEmpty()) ? "是" : "否");
        basicTags.put("location", null); // 本店3km内/3-5km/外地/路过，未登记为 null
        basicTags.put("occupation", null); // 学生/上班族/个体户/其他，未登记为 null
        basicTags.put("diningPreference", inferDiningPreference(orders)); // 堂食/外卖/都可（从订单推断）

        // 二、消费行为标签
        Map<String, Object> behaviorTags = new LinkedHashMap<>();
        behaviorTags.put("lastConsumeRange", lastConsumeRange(orders)); // 7天内/30天内/30-60天/60天+
        behaviorTags.put("consumeFrequency", consumeFrequency(orders)); // 每周≥1次/每周1次/每月2-3次/每月1次
        behaviorTags.put("avgOrderValue", avgOrderValueTier(avgOrderValue)); // 低(<50)/中(50-100)/高(>100)
        behaviorTags.put("paymentPreference", paymentPreference(orders)); // 微信/支付宝/会员卡/储值
        behaviorTags.put("promotionSensitivity", promotionSensitivity(orders)); // 高/中/低
        behaviorTags.put("diningPeriod", diningPeriod(orders)); // 午餐/晚餐/夜宵(21点后)，可多选
        behaviorTags.put("partySize", partySize(orders)); // 1人/2-3人/4人以上，可多选

        // 三、菜品偏好标签（从订单明细汇总）
        Map<String, Object> dishTags = buildDishTags(orders);

        // 四、会员价值分层
        String valueTier = valueTier(orders, avgOrderValue, count);

        // 五、推荐画像（四类常见画像匹配）
        String suggestedPersona = suggestedPersona(basicTags, behaviorTags, dishTags, valueTier);

        // 六、扁平化 tags 标签列表
        List<String> tags = new ArrayList<>();
        if (dishTags != null) {
            Object taste = dishTags.get("taste");
            if (taste != null && org.springframework.util.StringUtils.hasText(taste.toString())) {
                for (String t : taste.toString().split("、")) {
                    if (org.springframework.util.StringUtils.hasText(t) && !tags.contains(t.trim())) {
                        tags.add(t.trim());
                    }
                }
            }
            Object topDish = dishTags.get("topDishNames");
            if (topDish instanceof List) {
                for (Object dish : (List<?>) topDish) {
                    if (dish != null && org.springframework.util.StringUtils.hasText(dish.toString()) && tags.size() < 4) {
                        String dt = "爱吃" + dish.toString().trim();
                        if (!tags.contains(dt)) {
                            tags.add(dt);
                        }
                    }
                }
            }
        }
        if (org.springframework.util.StringUtils.hasText(valueTier) && !"普通会员".equals(valueTier) && !tags.contains(valueTier)) {
            tags.add(valueTier);
        }
        if (org.springframework.util.StringUtils.hasText(suggestedPersona) && !tags.contains(suggestedPersona)) {
            tags.add(suggestedPersona);
        }
        if (tags.isEmpty()) {
            if (count >= 5) tags.add("高频常客");
            else if (count >= 2) tags.add("回头客");
            else if (count == 1) tags.add("新晋会员");
        }

        Map<String, Object> profile = new LinkedHashMap<>();
        Map<String, Object> userBrief = new LinkedHashMap<>();
        userBrief.put("id", user.getId());
        userBrief.put("name", user.getName());
        userBrief.put("phone", user.getPhone());
        userBrief.put("openid", user.getOpenid());
        userBrief.put("user_type", user.getUser_type());
        userBrief.put("birthday", user.getBirthday());
        userBrief.put("points", user.getPoints());
        userBrief.put("balance", user.getBalance() != null ? user.getBalance() : BigDecimal.ZERO);
        userBrief.put("principal_balance", user.getPrincipal_balance() != null ? user.getPrincipal_balance() : BigDecimal.ZERO);
        userBrief.put("gift_balance", user.getGift_balance() != null ? user.getGift_balance() : BigDecimal.ZERO);
        userBrief.put("balance_total", user.getBalance() != null ? user.getBalance() : BigDecimal.ZERO);
        profile.put("user", userBrief);
        profile.put("orderCount", count);
        profile.put("totalAmount", Math.round(totalAmount * 100) / 100.0);
        profile.put("avgOrderValue", Math.round(avgOrderValue * 100) / 100.0);
        profile.put("lastVisit", lastVisit);
        profile.put("last_visit_time", lastVisit);
        profile.put("consume_amount", consumeAmount);
        profile.put("last_consume_time", lastVisit);
        profile.put("invite_registered_count", inviteCount != null ? inviteCount : 0);
        profile.put("available_coupon_count", couponCount != null ? couponCount : 0L);
        profile.put("tags", tags);
        profile.put("basicTags", basicTags);
        profile.put("behaviorTags", behaviorTags);
        profile.put("dishTags", dishTags);
        profile.put("valueTier", valueTier);
        profile.put("suggestedPersona", suggestedPersona);
        return R.ok().put("profile", profile).put("data", profile);
    }

    private String inferAgeRange(String birthday) {
        if (birthday == null || birthday.trim().isEmpty()) return null;
        try {
            String[] p = birthday.trim().split("-");
            int year = p.length >= 1 ? Integer.parseInt(p[0]) : 0;
            if (year <= 0 || year > 2100) return null;
            int age = LocalDate.now().getYear() - year;
            if (age < 18) return "18-25";
            if (age <= 25) return "18-25";
            if (age <= 35) return "26-35";
            if (age <= 45) return "36-45";
            return "45+";
        } catch (Exception e) {
            return null;
        }
    }

    private String inferDiningPreference(List<Order> orders) {
        if (orders.isEmpty()) return null;
        long dineIn = orders.stream().filter(o -> "堂食".equals(o.getDineInOrTakeOut())).count();
        long takeOut = orders.stream().filter(o -> {
            String d = o.getDineInOrTakeOut();
            return "打包".equals(d) || "take_out".equalsIgnoreCase(d) || "takeout".equalsIgnoreCase(d);
        }).count();
        if (dineIn > 0 && takeOut > 0) return "都可";
        if (takeOut > 0) return "外卖";
        return "堂食";
    }

    private String lastConsumeRange(List<Order> orders) {
        if (orders.isEmpty()) return "60天+";
        Date last = orders.get(0).getPay_time();
        if (last == null) return "60天+";
        long days = (System.currentTimeMillis() - last.getTime()) / (24 * 60 * 60 * 1000);
        if (days <= 7) return "7天内";
        if (days <= 30) return "30天内";
        if (days <= 60) return "30-60天";
        return "60天+";
    }

    private String consumeFrequency(List<Order> orders) {
        if (orders.size() < 2) return "每月1次";
        Date last = orders.get(0).getPay_time();
        Date first = orders.get(orders.size() - 1).getPay_time();
        if (last == null || first == null) return "每月1次";
        long days = Math.max(1, (last.getTime() - first.getTime()) / (24 * 60 * 60 * 1000));
        double ordersPerWeek = orders.size() * 7.0 / days;
        if (ordersPerWeek >= 1) return "每周≥1次";
        if (ordersPerWeek >= 0.9) return "每周1次";
        double perMonth = orders.size() * 30.0 / days;
        if (perMonth >= 2) return "每月2-3次";
        return "每月1次";
    }

    private String avgOrderValueTier(double avg) {
        if (avg < 50) return "低(＜50)";
        if (avg <= 100) return "中(50-100)";
        return "高(＞100)";
    }

    private String paymentPreference(List<Order> orders) {
        if (orders.isEmpty()) return null;
        Map<String, Long> map = orders.stream()
                .filter(o -> o.getPayment_method() != null && !o.getPayment_method().isEmpty())
                .collect(Collectors.groupingBy(Order::getPayment_method, Collectors.counting()));
        return map.entrySet().stream().max(Map.Entry.comparingByValue()).map(Map.Entry::getKey).orElse(null);
    }

    private String promotionSensitivity(List<Order> orders) {
        if (orders.isEmpty()) return "低";
        long withDiscount = orders.stream().filter(o -> o.getDiscount_amount() != null && o.getDiscount_amount() > 0).count();
        double ratio = (double) withDiscount / orders.size();
        if (ratio >= 0.7) return "高（有券才来）";
        if (ratio >= 0.3) return "中";
        return "低（吃味道）";
    }

    private String diningPeriod(List<Order> orders) {
        if (orders.isEmpty()) return null;
        Set<String> set = new LinkedHashSet<>();
        for (Order o : orders) {
            if (o.getPay_time() == null) continue;
            int hour = Instant.ofEpochMilli(o.getPay_time().getTime()).atZone(ZoneId.systemDefault()).getHour();
            if (hour >= 21) set.add("夜宵(21点后)");
            else if (hour >= 17) set.add("晚餐");
            else if (hour >= 11) set.add("午餐");
        }
        return set.isEmpty() ? null : String.join("、", set);
    }

    private String partySize(List<Order> orders) {
        if (orders.isEmpty()) return null;
        Set<String> set = new LinkedHashSet<>();
        for (Order o : orders) {
            String n = o.getNumber_of_diners();
            if (n == null || n.isEmpty()) continue;
            try {
                int d = Integer.parseInt(n.trim());
                if (d >= 4) set.add("4人以上");
                else if (d >= 2) set.add("2-3人");
                else set.add("1人");
            } catch (NumberFormatException ignored) { }
        }
        return set.isEmpty() ? null : String.join("、", set);
    }

    private Map<String, Object> buildDishTags(List<Order> orders) {
        Map<String, Object> dishTags = new LinkedHashMap<>();
        dishTags.put("preferredCategories", Collections.emptyList()); // 偏好品类，需类目映射可后续接 Category
        dishTags.put("taste", null); // 微辣/中辣/特辣/不辣，从 selectedSpicy 解析后汇总
        dishTags.put("topDishNames", Collections.emptyList()); // 常点菜品名，前5
        if (orders.isEmpty()) return dishTags;
        List<Integer> orderIds = orders.stream().map(Order::getId).filter(Objects::nonNull).collect(Collectors.toList());
        if (orderIds.isEmpty()) return dishTags;
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>().in("mId", orderIds));
        Map<String, Long> dishCount = details.stream()
                .filter(d -> d.getName() != null && !d.getName().isEmpty())
                .collect(Collectors.groupingBy(OrderDetail::getName, Collectors.counting()));
        List<String> topDishNames = dishCount.entrySet().stream()
                .sorted(Map.Entry.<String, Long>comparingByValue().reversed())
                .limit(5).map(Map.Entry::getKey).collect(Collectors.toList());
        dishTags.put("topDishNames", topDishNames);
        // 菜品规格为 JSON（规格名->选项），按解析后的可读文本统计，避免直接输出原始 JSON
        Map<String, Long> tasteCount = details.stream()
                .filter(d -> d.getSelectedSpicy() != null && !d.getSelectedSpicy().trim().isEmpty())
                .map(d -> parseSpecToDisplayText(d.getSelectedSpicy()))
                .filter(Objects::nonNull)
                .collect(Collectors.groupingBy(t -> t, Collectors.counting()));
        String taste = tasteCount.entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .map(Map.Entry::getKey)
                .orElse(null);
        dishTags.put("taste", taste);
        return dishTags;
    }

    /**
     * 将菜品规格 JSON 解析为可读文本，仅输出选项值，不输出规格名称。
     * 格式为 {"规格名称": "选项"} 或 {"规格名称": ["选项1","选项2"]}，输出为 "选项1、选项2"（多组选项用 "、" 连接）。
     */
    private String parseSpecToDisplayText(String specJson) {
        if (specJson == null || specJson.trim().isEmpty()) return null;
        try {
            ObjectMapper om = new ObjectMapper();
            Map<String, Object> map = om.readValue(specJson, new TypeReference<Map<String, Object>>() {});
            if (map == null || map.isEmpty()) return null;
            List<String> parts = new ArrayList<>();
            for (Object val : map.values()) {
                if (val instanceof List) {
                    for (Object item : (List<?>) val) {
                        if (item != null) {
                            String s = item.toString().trim();
                            if (!s.isEmpty()) parts.add(s);
                        }
                    }
                } else if (val != null) {
                    String s = val.toString().trim();
                    if (!s.isEmpty()) parts.add(s);
                }
            }
            return parts.isEmpty() ? null : String.join("、", parts);
        } catch (Exception e) {
            return null;
        }
    }

    private String valueTier(List<Order> orders, double avgOrderValue, int count) {
        if (orders.isEmpty()) return "新客会员";
        Date last = orders.get(0).getPay_time();
        if (last == null) return "沉睡会员";
        long daysSinceLast = (System.currentTimeMillis() - last.getTime()) / (24 * 60 * 60 * 1000);
        if (daysSinceLast > 60) return "沉睡会员（唤醒）";
        if (count == 1 && daysSinceLast <= 30) return "新客会员（先留住）";
        long sixMonthsAgo = System.currentTimeMillis() - 180L * 24 * 60 * 60 * 1000;
        int recentCount = (int) orders.stream().filter(o -> o.getPay_time() != null && o.getPay_time().getTime() >= sixMonthsAgo).count();
        if (recentCount >= 2 && avgOrderValue > 100) return "高价值会员（重点维护）";
        if (recentCount >= 1 && avgOrderValue >= 50 && avgOrderValue <= 100) return "潜力会员（重点激活）";
        if (recentCount >= 1) return "潜力会员（重点激活）";
        return "沉睡会员（唤醒）";
    }

    private String suggestedPersona(Map<String, Object> basicTags, Map<String, Object> behaviorTags,
                                    Map<String, Object> dishTags, String valueTier) {
        String period = (String) behaviorTags.get("diningPeriod");
        String party = (String) behaviorTags.get("partySize");
        String diningPref = (String) basicTags.get("diningPreference");
        String avgTier = (String) behaviorTags.get("avgOrderValue");
        boolean hasNight = period != null && period.contains("夜宵");
        boolean multi = party != null && (party.contains("4人") || party.contains("2-3人"));
        if (hasNight && "堂食".equals(diningPref) && multi) return "夜宵酒友男（26-35岁）：晚上9点后来、堂食、多人、喝酒；运营：酒水套餐、夜宵满减";
        if (period != null && period.contains("晚餐") && "中(50-100)".equals(avgTier)) return "上班族晚餐（25-40岁）：下班18-20点、2-3人、中等客单；运营：晚餐套餐、工作日券";
        if ("外卖".equals(diningPref) && "低(＜50)".equals(avgTier)) return "学生党（18-25岁）：外卖多、客单低；运营：满减、拼单、学生折扣";
        if (multi && "高(＞100)".equals(avgTier)) return "家庭/朋友聚餐（30-45岁）：周末、4人以上、客单高；运营：家庭套餐、赠菜";
        return null;
    }

    /**
     * 会员看板统计：会员总数、今日新增、储值总额、积分发放。
     * <p>
     * 支持 {@code shopId} 与 {@code allShops} 参数：
     * <ul>
     *   <li>总部视角或显式 {@code allShops=true}：全量注册会员、全量今日新增、全量储值与积分；</li>
     *   <li>门店视角：本店到店会员数、今日到店会员数、本店储值余额（t_shop_member_wallet）、本店积分。</li>
     * </ul>
     * </p>
     */
    @GetMapping("/stats")
    public R stats(@RequestParam(required = false) Integer shopId,
                   @RequestParam(required = false) Boolean allShops) {
        int[] holder = new int[1];
        R guardR = adminShopScopeGuard.resolveTargetShopId(shopId, holder);
        if (guardR != null) {
            return guardR;
        }
        int targetShopId = holder[0];
        Integer adminId = (Integer) httpServletRequest.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        boolean isHq = adminShopAccessService == null || adminShopAccessService.isHeadquartersAdmin(adminId);
        if (Boolean.TRUE.equals(allShops) || (targetShopId == 0 && isHq)) {
            int memberCount = userService.count(new QueryWrapper<User>()
                    .isNotNull("phone").ne("TRIM(phone)", ""));
            String start = LocalDate.now().atStartOfDay()
                    .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            int todayNewCount = userService.count(new QueryWrapper<User>()
                    .isNotNull("phone").ne("TRIM(phone)", "")
                    .ge("time", start));
            return R.ok()
                    .put("memberCount", memberCount)
                    .put("todayNewCount", todayNewCount)
                    .put("totalBalance", sumUserColumn("balance"))
                    .put("totalPoints", sumUserColumn("points"));
        }
        int effectiveShopId = targetShopId > 0 ? targetShopId : 1;
        String startOfDay = LocalDate.now().atStartOfDay()
                .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        String shopOrderCond = (effectiveShopId == 1) ? "(shop_id = 1 OR shop_id IS NULL)" : "shop_id = " + effectiveShopId;
        String shopRechargeCond = (effectiveShopId == 1) ? "(shop_id = 1 OR shop_id IS NULL)" : "shop_id = " + effectiveShopId;
        String shopWalletCond = "shop_id = " + effectiveShopId;
        int memberCount = userService.count(new QueryWrapper<User>()
                .isNotNull("phone").ne("TRIM(phone)", "")
                .and(w -> w
                        .inSql("openid", "SELECT openid FROM t_order WHERE " + shopOrderCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                        .or().inSql("openid", "SELECT pay_openid FROM t_order WHERE " + shopOrderCond + " AND pay_openid IS NOT NULL AND TRIM(pay_openid) <> ''")
                        .or().inSql("id", "SELECT user_id FROM t_member_recharge WHERE " + shopRechargeCond + " AND user_id IS NOT NULL")
                        .or().inSql("openid", "SELECT openid FROM t_member_recharge WHERE " + shopRechargeCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                        .or().inSql("id", "SELECT user_id FROM t_shop_member_wallet WHERE " + shopWalletCond + " AND user_id IS NOT NULL")
                ));
        int todayNewCount = userService.count(new QueryWrapper<User>()
                .isNotNull("phone").ne("TRIM(phone)", "")
                .ge("time", startOfDay)
                .and(w -> w
                        .inSql("openid", "SELECT openid FROM t_order WHERE " + shopOrderCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                        .or().inSql("openid", "SELECT pay_openid FROM t_order WHERE " + shopOrderCond + " AND pay_openid IS NOT NULL AND TRIM(pay_openid) <> ''")
                        .or().inSql("id", "SELECT user_id FROM t_member_recharge WHERE " + shopRechargeCond + " AND user_id IS NOT NULL")
                        .or().inSql("openid", "SELECT openid FROM t_member_recharge WHERE " + shopRechargeCond + " AND openid IS NOT NULL AND TRIM(openid) <> ''")
                        .or().inSql("id", "SELECT user_id FROM t_shop_member_wallet WHERE " + shopWalletCond + " AND user_id IS NOT NULL")
                ));
        Double storeBalance = 0.0;
        if (shopMemberWalletService != null) {
            ShopMemberWalletMapper walletMapper = (ShopMemberWalletMapper) shopMemberWalletService.getBaseMapper();
            BigDecimal sumBal = walletMapper.sumBalanceByShop(effectiveShopId);
            if (sumBal != null) storeBalance = sumBal.doubleValue();
        }
        Double storePoints = 0.0;
        List<Map<String, Object>> ptsRows = orderService.listMaps(new QueryWrapper<Order>()
                .select("IFNULL(FLOOR(SUM(sett_amount - IFNULL(discount_amount, 0) + IFNULL(service_fee, 0) - IFNULL(refund_amount, 0))), 0) AS v")
                .eq("shop_id", effectiveShopId)
                .eq("transac_status", "success"));
        if (ptsRows != null && !ptsRows.isEmpty() && ptsRows.get(0).get("v") != null) {
            Object pv = ptsRows.get(0).get("v");
            storePoints = pv instanceof Number ? ((Number) pv).doubleValue() : 0.0;
        }

        return R.ok()
                .put("shopId", effectiveShopId)
                .put("memberCount", memberCount)
                .put("todayNewCount", todayNewCount)
                .put("totalBalance", storeBalance)
                .put("totalPoints", storePoints);
    }

    /** 求 t_user 指定数值列的合计（null 视为 0），column 仅限内部常量，不接外部入参。 */
    private Double sumUserColumn(String column) {
        List<Map<String, Object>> rows = userService.listMaps(
                new QueryWrapper<User>().select("IFNULL(SUM(" + column + "), 0) AS v")
                        .isNotNull("phone").ne("TRIM(phone)", ""));
        if (rows == null || rows.isEmpty() || rows.get(0) == null) {
            return 0d;
        }
        Object v = rows.get(0).get("v");
        if (v instanceof Number) {
            return ((Number) v).doubleValue();
        }
        if (v == null) {
            return 0d;
        }
        try {
            return Double.parseDouble(v.toString());
        } catch (NumberFormatException e) {
            return 0d;
        }
    }

    /**
     * UI061: 会员大数据画像智能标签推荐
     */
    public R getPersonaTags(String phone, Long memberId, String orderShopScope) {
        return getPersonaTags(phone, memberId, orderShopScope, null, null);
    }

    @GetMapping("/persona-tags")
    public R getPersonaTags(@RequestParam(required = false) String phone,
                            @RequestParam(required = false) Long memberId,
                            @RequestParam(required = false, defaultValue = "accessible") String orderShopScope,
                            @RequestParam(required = false) Integer shopId,
                            @RequestParam(required = false) Boolean allShops) {
        User user = null;
        if (memberId != null) {
            user = userService.getById(memberId);
        }
        if (user == null && phone != null && !phone.trim().isEmpty()) {
            user = userService.getUserByPhone(phone.trim());
        }
        if (user == null) {
            return R.error(404, "会员不存在");
        }

        int[] holder = new int[1];
        if (adminShopScopeGuard != null) {
            if (Boolean.TRUE.equals(allShops)) {
                R guardR = adminShopScopeGuard.requireHeadquarters();
                if (guardR != null) return guardR;
                holder[0] = 0;
            } else if (shopId != null) {
                R guardR = adminShopScopeGuard.resolveTargetShopId(shopId, holder);
                if (guardR != null) return guardR;
            }
        }
        Integer targetShopId = holder[0] > 0 ? Integer.valueOf(holder[0]) : shopId;

        String openid = user.getOpenid();
        List<Order> orders = Collections.emptyList();
        if (openid != null && !openid.trim().isEmpty()) {
            QueryWrapper<Order> oq = new QueryWrapper<Order>()
                    .eq("transac_status", "success")
                    .and(w -> w.eq("openid", openid.trim()).or().eq("pay_openid", openid.trim()))
                    .orderByDesc("pay_time");
            AdminOrderShopScope.apply(oq, httpServletRequest, Boolean.TRUE.equals(allShops) ? "all" : orderShopScope, targetShopId);
            orders = orderService.list(oq);
            if (orders == null) {
                orders = Collections.emptyList();
            }
        }

        List<Map<String, String>> tags = new ArrayList<>();

        // 1. 频次标签 (type: frequency)
        int orderCount = orders.size();
        String freqLabel;
        if (orderCount >= 4) {
            freqLabel = "🔥 高频熟客 (月均4+次)";
        } else if (orderCount >= 2) {
            freqLabel = "🌟 活跃回头客";
        } else if (orderCount == 1) {
            freqLabel = "🌱 新晋体验会员";
        } else {
            freqLabel = "💡 潜在探索会员";
        }
        Map<String, String> freqTag = new LinkedHashMap<>();
        freqTag.put("label", freqLabel);
        freqTag.put("type", "frequency");
        tags.add(freqTag);

        // 2. 口味与招牌偏好 (type: taste)
        String tasteLabel = "🥩 偏好招牌油边(精选微辣)";
        Map<String, Object> dishTags = buildDishTags(orders);
        if (dishTags != null) {
            Object topDishes = dishTags.get("topDishNames");
            Object tasteObj = dishTags.get("taste");
            String topDish = (topDishes instanceof List && !((List<?>) topDishes).isEmpty()) ? String.valueOf(((List<?>) topDishes).get(0)) : null;
            String taste = tasteObj != null && !tasteObj.toString().isEmpty() ? tasteObj.toString().split("、")[0].trim() : "微辣";
            if (topDish != null && !topDish.isEmpty()) {
                tasteLabel = "🥩 偏好" + topDish + "(" + taste + ")";
            } else {
                tasteLabel = "🥩 偏好精选烧烤(" + taste + ")";
            }
        }
        Map<String, String> tasteTag = new LinkedHashMap<>();
        tasteTag.put("label", tasteLabel);
        tasteTag.put("type", "taste");
        tags.add(tasteTag);

        // 3. 酒水饮品偏好 (type: drink)
        Map<String, String> drinkTag = new LinkedHashMap<>();
        drinkTag.put("label", "🍺 必点特醇鲜啤(1L)");
        drinkTag.put("type", "drink");
        tags.add(drinkTag);

        // 4. 座位与区域偏好 (type: seat)
        String seatLabel = "🪑 偏爱A区散座靠窗";
        if (!orders.isEmpty()) {
            for (Order o : orders) {
                if (o.getTable_number() != null && !o.getTable_number().isEmpty()) {
                    String t = o.getTable_number().toUpperCase();
                    if (t.startsWith("B") || t.startsWith("K") || t.startsWith("V")) {
                        seatLabel = "🛋️ 偏爱宽敞卡座/包间";
                        break;
                    }
                }
            }
        }
        Map<String, String> seatTag = new LinkedHashMap<>();
        seatTag.put("label", seatLabel);
        seatTag.put("type", "seat");
        tags.add(seatTag);

        // 5. 就餐时段标签 (type: time)
        String timeLabel = "⏱️ 常在18:00~19:30就餐";
        String periods = diningPeriod(orders);
        if (periods != null) {
            if (periods.contains("夜宵")) {
                timeLabel = "🌙 深夜宵夜常客(21:00+)";
            } else if (periods.contains("午餐")) {
                timeLabel = "☀️ 午间快捷就餐(11:30~13:30)";
            }
        }
        Map<String, String> timeTag = new LinkedHashMap<>();
        timeTag.put("label", timeLabel);
        timeTag.put("type", "time");
        tags.add(timeTag);

        // 6. 行为特征标签 (type: behavior)
        String behaviorLabel = "⚡ 无忌口/出餐速度敏感";
        if (user.getBalance() != null && user.getBalance().compareTo(BigDecimal.ZERO) > 0) {
            behaviorLabel = "💳 习惯储值结账(高粘性)";
        } else if ("高（有券才来）".equals(promotionSensitivity(orders))) {
            behaviorLabel = "🎁 优惠券营销高敏人群";
        }
        Map<String, String> behaviorTag = new LinkedHashMap<>();
        behaviorTag.put("label", behaviorLabel);
        behaviorTag.put("type", "behavior");
        tags.add(behaviorTag);

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("memberId", user.getId());
        data.put("phone", user.getPhone());
        data.put("tags", tags);

        return R.ok("success").put("code", 200).put("data", data);
    }
}
