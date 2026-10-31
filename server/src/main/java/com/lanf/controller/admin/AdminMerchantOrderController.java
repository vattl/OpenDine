package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.service.IOrderService;
import com.lanf.service.IShopService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.OrderNetRevenue;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.*;

/**
 * 按 merchantId 查询营业日订单数据接口。
 *
 * <p>营业日窗口以 {@code t_shop.settle_time} 为开始时间（次日同一时刻为结束），共 24 小时，
 * 例如：settle_time=05:00，营业日 2024-01-15 对应 [2024-01-15 05:00, 2024-01-16 05:00)。
 *
 * <p>路由：GET /admin/merchant/orders（列表）、GET /admin/merchant/orders/summary（汇总）
 */
@RestController
@RequestMapping("/admin/merchant/orders")
public class AdminMerchantOrderController {

    /** 默认 merchantId：收银系统自营订单 */
    private static final String DEFAULT_MERCHANT_ID = "1";

    /** 未配置 settle_time 时的缺省结算时间 */
    private static final LocalTime DEFAULT_SETTLE = LocalTime.of(5, 0);

    private static final ZoneId ZONE = ZoneId.systemDefault();

    @Autowired
    private IOrderService orderService;

    @Autowired
    private IShopService shopService;

    @Autowired
    private HttpServletRequest httpServletRequest;

    /**
     * 查询指定 merchantId 在营业日窗口内的订单列表。
     *
     * <p>参数：
     * <ul>
     *   <li>{@code merchant_id} — 商户标识，缺省 "1"</li>
     *   <li>{@code date} — 营业日（yyyy-MM-dd），缺省当前营业日</li>
     *   <li>{@code transac_status} — 结账状态（success/unsettled/cancelled），缺省 success</li>
     *   <li>{@code page} — 页码（1-based），缺省 1</li>
     *   <li>{@code page_size} — 每页条数，缺省 200，最大 500</li>
     * </ul>
     */
    @GetMapping
    public R queryOrders(
            @RequestParam(value = "merchant_id", required = false) String merchantId,
            @RequestParam(required = false) String date,
            @RequestParam(value = "transac_status", required = false) String transacStatus,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(value = "page_size", defaultValue = "200") int pageSize) {

        String mId    = StringUtils.hasText(merchantId)    ? merchantId.trim()    : DEFAULT_MERCHANT_ID;
        String status = StringUtils.hasText(transacStatus) ? transacStatus.trim() : "success";
        page     = Math.max(1, page);
        pageSize = Math.max(1, Math.min(500, pageSize));

        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Shop shop = resolveShop(shopId);

        LocalDate businessDay;
        try {
            businessDay = resolveBusinessDay(shop, date);
        } catch (Exception e) {
            return R.error("日期格式错误，应为 yyyy-MM-dd");
        }

        Date[] window = businessDayWindow24h(shop, businessDay);

        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("merchantId", mId)
                .eq("transac_status", status)
                .ge("order_time", window[0])
                .lt("order_time", window[1]);
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        q.orderByDesc("order_time");

        List<Order> all = orderService.list(q);

        // 分页
        int total = all.size();
        int fromIndex = (page - 1) * pageSize;
        List<Order> paged = fromIndex >= total
                ? Collections.emptyList()
                : all.subList(fromIndex, Math.min(fromIndex + pageSize, total));

        // 汇总金额（对全量，不受分页影响）
        double totalRevenue = round2(
                all.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum());

        return R.ok()
                .put("merchant_id",         mId)
                .put("business_day",        businessDay.toString())
                .put("window_start",        formatDate(window[0]))
                .put("window_end",          formatDate(window[1]))
                .put("transac_status_filter", status)
                .put("total_count",         total)
                .put("total_revenue",       totalRevenue)
                .put("page",                page)
                .put("page_size",           pageSize)
                .put("total_pages",         total == 0 ? 1 : (int) Math.ceil((double) total / pageSize))
                .put("orders",              paged);
    }

    /**
     * 按 merchantId 查询营业日订单汇总（无列表，适合看板聚合）。
     */
    @GetMapping("/summary")
    public R summary(
            @RequestParam(value = "merchant_id", required = false) String merchantId,
            @RequestParam(required = false) String date,
            @RequestParam(value = "transac_status", required = false) String transacStatus) {

        String mId    = StringUtils.hasText(merchantId)    ? merchantId.trim()    : DEFAULT_MERCHANT_ID;
        String status = StringUtils.hasText(transacStatus) ? transacStatus.trim() : "success";

        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Shop shop = resolveShop(shopId);

        LocalDate businessDay;
        try {
            businessDay = resolveBusinessDay(shop, date);
        } catch (Exception e) {
            return R.error("日期格式错误，应为 yyyy-MM-dd");
        }

        Date[] window = businessDayWindow24h(shop, businessDay);

        QueryWrapper<Order> q = new QueryWrapper<Order>()
                .eq("merchantId", mId)
                .eq("transac_status", status)
                .ge("order_time", window[0])
                .lt("order_time", window[1]);
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }

        List<Order> orders = orderService.list(q);

        double totalRevenue  = round2(orders.stream().mapToDouble(OrderNetRevenue::netRevenueYuan).sum());
        double totalDiscount = round2(orders.stream().mapToDouble(o -> nz(o.getDiscount_amount())).sum());
        double totalRefund   = round2(orders.stream().mapToDouble(o -> nz(o.getRefund_amount())).sum());

        // 按支付渠道分组
        Map<String, Double> byChannel = new LinkedHashMap<>();
        for (Order o : orders) {
            String ch = StringUtils.hasText(o.getPayment_method()) ? o.getPayment_method() : "其他";
            byChannel.merge(ch, OrderNetRevenue.netRevenueYuan(o), Double::sum);
        }
        byChannel.replaceAll((k, v) -> round2(v));

        // 按就餐类型分组（订单数）
        Map<String, Long> byDiningType = new LinkedHashMap<>();
        for (Order o : orders) {
            String t = StringUtils.hasText(o.getDineInOrTakeOut()) ? o.getDineInOrTakeOut() : "未知";
            byDiningType.merge(t, 1L, Long::sum);
        }

        return R.ok()
                .put("merchant_id",           mId)
                .put("business_day",          businessDay.toString())
                .put("window_start",          formatDate(window[0]))
                .put("window_end",            formatDate(window[1]))
                .put("transac_status_filter", status)
                .put("order_count",           orders.size())
                .put("total_revenue",         totalRevenue)
                .put("total_discount",        totalDiscount)
                .put("total_refund",          totalRefund)
                .put("by_channel",            byChannel)
                .put("by_dining_type",        byDiningType);
    }

    // ─── 内部工具方法 ─────────────────────────────────────────────────────────

    /**
     * 24小时营业日窗口：[businessDay settle_time, businessDay+1 settle_time)。
     */
    private static Date[] businessDayWindow24h(Shop shop, LocalDate businessDay) {
        LocalTime settle = resolveSettleTime(shop);
        LocalDateTime start = LocalDateTime.of(businessDay, settle);
        LocalDateTime end   = start.plusDays(1);
        return new Date[]{
                Date.from(start.atZone(ZONE).toInstant()),
                Date.from(end.atZone(ZONE).toInstant())
        };
    }

    /**
     * 解析营业日：传 date 参数直接 parse；否则按当前时刻推算。
     * 若当前时刻早于今日 settle_time → 属于昨日营业日，否则为今日。
     */
    private static LocalDate resolveBusinessDay(Shop shop, String date) {
        if (StringUtils.hasText(date)) {
            return LocalDate.parse(date.trim()); // DateTimeParseException → caller returns R.error
        }
        LocalTime settle = resolveSettleTime(shop);
        LocalDateTime now  = LocalDateTime.now();
        LocalDateTime todayWindowStart = LocalDateTime.of(now.toLocalDate(), settle);
        return now.isBefore(todayWindowStart)
                ? now.toLocalDate().minusDays(1)
                : now.toLocalDate();
    }

    private static LocalTime resolveSettleTime(Shop shop) {
        if (shop == null) return DEFAULT_SETTLE;
        LocalTime t = parseTime(shop.getSettle_time());
        if (t != null) return t;
        t = parseTime(shop.getClose_time());
        return t != null ? t : DEFAULT_SETTLE;
    }

    private static LocalTime parseTime(String text) {
        if (!StringUtils.hasText(text)) return null;
        String t = text.trim();
        if (t.length() > 5) t = t.substring(0, 5);
        try { return LocalTime.parse(t); } catch (Exception e) { return null; }
    }

    private Shop resolveShop(Integer shopId) {
        try {
            if (shopId != null) {
                Shop s = shopService.getById(shopId);
                if (s != null) return s;
            }
            return shopService.getOne(
                    new QueryWrapper<Shop>().orderByAsc("id").last("LIMIT 1"), false);
        } catch (Exception e) {
            return null;
        }
    }

    private static double round2(double v) {
        return Math.round(v * 100d) / 100d;
    }

    private static double nz(Double v) {
        return v != null ? v : 0d;
    }

    private static String formatDate(Date date) {
        return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(date);
    }
}
