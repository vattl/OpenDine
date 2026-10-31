package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.MemberRecharge;
import com.lanf.mapper.AnalyticsMapper;
import com.lanf.service.IAnalyticsService;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.IShopService;
import com.lanf.entity.Shop;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.*;

/**
 * 数据分析实现：金额口径与 OrderMapper 统计说明一致（success 且接单完成或 NULL）；
 * 净收入 = sett_amount - discount_amount + service_fee - refund_amount - pay_amount_gift；
 * 营业类接口同时给出自然日维度与结算日（settle_time 前 12 小时起点 / settle_time 截止，空值回退默认 16:00/04:00）维度。
 */
@Service
public class AnalyticsServiceImpl implements IAnalyticsService {

    private static final int ASSUMED_SEATS_PER_TABLE = 4;
    private static final int ASSUMED_MEALS_PER_DAY = 2;

    @Resource
    private AnalyticsMapper analyticsMapper;
    @Resource
    private IMemberRechargeService memberRechargeService;
    @Resource
    private IShopService shopService;

    @Override
    public String[] defaultWindow(Integer shopId) {
        Shop shop = shopId == null ? null : shopService.getById(shopId);
        LocalDate day = ShopBusinessWindowResolver.completedSettlementDay(shop, LocalDateTime.now());
        return ShopBusinessWindowResolver.settlementWindowText(shop, day);
    }

    @Override
    public Map<String, Object> businessOverview(String startTime, String endTime, Integer shopId) {
        Map<String, Object> core = analyticsMapper.selectBusinessCore(startTime, endTime, shopId);
        if (core == null) {
            core = new HashMap<>();
        }
        double net = toDouble(core.get("net_revenue"));
        double gross = toDouble(core.get("gross_before_discount"));
        double refund = toDouble(core.get("refund_total"));
        long orderCount = toLong(core.get("order_count"));
        double avgTicket = orderCount > 0 ? round2(net / orderCount) : 0;
        double refundRate = gross > 0 ? round4(refund / gross) : 0;

        Long tableCount = analyticsMapper.selectTableCount(shopId);
        long tc = tableCount == null ? 0L : tableCount;
        long calendarDays = inclusiveDays(startTime, endTime);
        Long bizDayCountObj = analyticsMapper.selectDistinctBusinessDayCount(startTime, endTime, shopId, resolveOpenTime(shopId), resolveSettleTime(shopId));
        long businessDays = bizDayCountObj == null ? 0L : Math.max(1L, bizDayCountObj);
        long dineInOrders = toLong(core.get("dine_in_order_count"));
        double dinerDineIn = toDouble(core.get("diner_sum_dine_in"));

        double turnoverNatural = (tc > 0 && calendarDays > 0)
                ? round4((double) dineInOrders / (double) tc / (double) calendarDays)
                : 0;
        double denomOccNat = tc * ASSUMED_SEATS_PER_TABLE * calendarDays * ASSUMED_MEALS_PER_DAY;
        double occupancyNatural = denomOccNat > 0 ? round4(dinerDineIn / denomOccNat) : 0;

        double turnoverBusiness = (tc > 0 && businessDays > 0)
                ? round4((double) dineInOrders / (double) tc / (double) businessDays)
                : 0;
        double denomOccBiz = tc * ASSUMED_SEATS_PER_TABLE * businessDays * ASSUMED_MEALS_PER_DAY;
        double occupancyBusiness = denomOccBiz > 0 ? round4(dinerDineIn / denomOccBiz) : 0;

        Map<String, Object> occNote = mapOf(
                "seats_per_table", ASSUMED_SEATS_PER_TABLE,
                "meals_per_day", ASSUMED_MEALS_PER_DAY,
                "note", "上座率 = 堂食用餐人数合计 ÷ (桌台数×假设餐位数×统计天数×每日餐次)；未维护桌台或人数时仅供参考"
        );

        Map<String, Object> naturalDerived = mapOf(
                "dimension", "natural_calendar",
                "avg_ticket", avgTicket,
                "refund_rate_on_gross", refundRate,
                "table_count", tc,
                "day_count", calendarDays,
                "day_count_note", "自然日：请求起止日期闭区间内的日历天数",
                "table_turnover_per_table_per_day", turnoverNatural,
                "seat_occupancy_rate", occupancyNatural,
                "occupancy_assumption", occNote
        );

        Map<String, Object> businessDerived = mapOf(
                "dimension", "business_day",
                "avg_ticket", avgTicket,
                "refund_rate_on_gross", refundRate,
                "table_count", tc,
                "day_count", businessDays,
                "day_count_note", "营业日：订单按 16:00 为界归入营业日标签后，在筛选结果中去重的营业日个数",
                "table_turnover_per_table_per_day", turnoverBusiness,
                "seat_occupancy_rate", occupancyBusiness,
                "occupancy_assumption", occNote
        );

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("time_definition", mapOf(
                "natural_calendar", "指标按 order_time 落在请求时间窗内统计；日维度分桶按自然日历日",
                "business_day", "营业日标签：D 的 open_time（含）至 D+1 的 settle_time（不含）前订单归属同一营业日；关门时段订单不计入（settle_time 为空回退 close_time / 04:00）",
                "time_slots_natural_clock", "按墙钟 05–10 / 10–16 / 16–22 / 其余 为早/午/晚/夜宵（与营业日锚点分档不同）",
                "time_slots_business_anchor", "以 16:00 为营业日起点：墙钟 [16,22)、[22,24)∪[0,4)、[4,10)、[10,16) 四段，键 bd_evening / bd_late_night / bd_breakfast / bd_lunch",
                "time_slots_hourly", "墙钟小时逐时（00–23），与自然钟点四段同口径；仅返回窗口内有订单的小时",
                "time_slots_business_hourly", "以门店 open_time（默认 16:00）为起点的营业日小时序列（bd_hour_00…bd_hour_23），与营业锚点四段同口径"
        ));
        out.put("core", core);
        out.put("natural_calendar", mapOf("derived", naturalDerived));
        out.put("business_day", mapOf("derived", businessDerived));
        out.put("time_slots_natural_clock", analyticsMapper.selectTimeSlotRevenue(startTime, endTime, shopId,
                resolveOpenTime(shopId), resolveSettleTime(shopId)));
        out.put("time_slots_business_anchor", analyticsMapper.selectTimeSlotRevenueBusinessAnchor(startTime, endTime, shopId,
                resolveOpenTime(shopId), resolveSettleTime(shopId)));
        int openHour = parseHour(resolveOpenTime(shopId));
        out.put("time_slots_hourly", withAvgTicket(analyticsMapper.selectTimeSlotHourly(startTime, endTime, shopId,
                resolveOpenTime(shopId), resolveSettleTime(shopId)), openHour));
        out.put("time_slots_business_hourly", withAvgTicket(analyticsMapper.selectTimeSlotBusinessHourly(startTime, endTime, shopId,
                resolveOpenTime(shopId), resolveSettleTime(shopId)), openHour));
        out.put("payment_channels", analyticsMapper.selectPaymentChannelMix(startTime, endTime, shopId));
        return out;
    }

    @Override
    public Map<String, Object> businessTrend(String startTime, String endTime, Integer shopId, String granularity) {
        String g = granularity == null ? "day" : granularity.trim().toLowerCase(Locale.ROOT);
        if (!Arrays.asList("day", "week", "month", "year").contains(g)) {
            g = "day";
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("granularity", g);
        out.put("natural_calendar", mapOf(
                "series", analyticsMapper.selectBusinessTrend(startTime, endTime, shopId, g)
        ));
        out.put("business_day", mapOf(
                "series", analyticsMapper.selectBusinessTrendByBusinessDate(startTime, endTime, shopId, g, resolveOpenTime(shopId), resolveSettleTime(shopId))
        ));
        out.put("time_definition", mapOf(
                "natural_calendar", "分桶字段为自然日/自然周/自然月/自然年（基于 order_time）",
                "business_day", "分桶字段为营业日标签（open_time 起点 / settle_time 截止），同一请求内与 businessOverview 一致"
        ));
        return out;
    }

    @Override
    public Map<String, Object> dishAnalysis(String startTime, String endTime, Integer shopId, int limit) {
        List<Map<String, Object>> raw = analyticsMapper.selectDishSalesAgg(startTime, endTime, shopId);
        if (raw == null) {
            raw = Collections.emptyList();
        }
        int n = raw.size();
        int hotCut = Math.max(1, (int) Math.ceil(n * 0.2));
        int slowCut = Math.max(1, (int) Math.ceil(n * 0.2));

        List<Map<String, Object>> ranked = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Map<String, Object> row = new LinkedHashMap<>(raw.get(i));
            String tag;
            if (n >= 5 && i < hotCut) {
                tag = "hot";
            } else if (n >= 5 && i >= n - slowCut) {
                tag = "slow";
            } else {
                tag = "normal";
            }
            row.put("sales_rank", i + 1);
            row.put("velocity_tag", tag);

            BigDecimal qty = toBigDecimal(row.get("total_quantity"));
            BigDecimal sales = toBigDecimal(row.get("total_sales"));
            BigDecimal unitCost = toBigDecimal(row.get("ref_cost_price"));
            if (unitCost != null && qty != null && sales != null && sales.compareTo(BigDecimal.ZERO) > 0) {
                BigDecimal costTotal = unitCost.multiply(qty).setScale(2, RoundingMode.HALF_UP);
                BigDecimal grossProfit = sales.subtract(costTotal).setScale(2, RoundingMode.HALF_UP);
                BigDecimal marginRate = sales.compareTo(BigDecimal.ZERO) == 0 ? BigDecimal.ZERO
                        : grossProfit.divide(sales, 4, RoundingMode.HALF_UP);
                row.put("estimated_cost_total", costTotal);
                row.put("estimated_gross_profit", grossProfit);
                row.put("estimated_gross_margin_rate", marginRate.doubleValue());
                double mr = marginRate.doubleValue();
                if (mr >= 0.55) {
                    row.put("margin_category", "high");
                } else if (mr < 0.2) {
                    row.put("margin_category", "low");
                } else {
                    row.put("margin_category", "medium");
                }
            } else {
                row.put("margin_category", "unknown");
            }
            ranked.add(row);
            if (limit > 0 && ranked.size() >= limit) {
                break;
            }
        }

        Map<String, Object> combo = analyticsMapper.selectDishComboRatio(startTime, endTime, shopId);
        Map<String, Object> comboOut = new LinkedHashMap<>();
        if (combo != null) {
            BigDecimal ts = toBigDecimal(combo.get("total_sales"));
            BigDecimal cs = toBigDecimal(combo.get("combo_sales"));
            BigDecimal tq = toBigDecimal(combo.get("total_qty"));
            BigDecimal cq = toBigDecimal(combo.get("combo_qty"));
            comboOut.put("combo_sales", cs);
            comboOut.put("single_sales", ts != null && cs != null ? ts.subtract(cs) : null);
            comboOut.put("combo_sales_ratio", ratio(cs, ts));
            comboOut.put("combo_qty_ratio", ratio(cq, tq));
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("dishes", ranked);
        out.put("combo_single", comboOut);
        out.put("new_product_trend_natural_day", analyticsMapper.selectNewDishSalesTrend(startTime, endTime, shopId));
        out.put("new_product_trend_business_day", analyticsMapper.selectNewDishSalesTrendByBusinessDate(startTime, endTime, shopId, resolveOpenTime(shopId), resolveSettleTime(shopId)));
        out.put("time_definition", mapOf(
                "natural_day", "day_label 为订单 order_time 所在自然日",
                "business_day", "day_label 为订单归属的结算日（settle_time 前 12 小时起点 / settle_time 截止），与营业汇总 business_day 一致"
        ));
        return out;
    }

    @Override
    public Map<String, Object> customerAnalysis(String startTime, String endTime, Integer shopId) {
        Map<String, Object> newOld = analyticsMapper.selectCustomerNewOld(startTime, endTime, shopId);
        Map<String, Object> rep = analyticsMapper.selectCustomerRepurchaseInPeriod(startTime, endTime, shopId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("new_vs_returning", newOld);
        if (rep != null) {
            long buyers = toLong(rep.get("buyers"));
            long repu = toLong(rep.get("repurchased_buyers"));
            rep.put("repurchase_rate", buyers > 0 ? round4((double) repu / (double) buyers) : 0);
        }
        out.put("repurchase_in_period", rep);
        out.put("visit_frequency", analyticsMapper.selectCustomerVisitBuckets(startTime, endTime, shopId));
        out.put("taste_preference", analyticsMapper.selectTastePreference(startTime, endTime, shopId));
        out.put("taboo_hints", analyticsMapper.selectTabooHints(startTime, endTime, shopId));
        return out;
    }

    @Override
    public Map<String, Object> memberAnalysis(String startTime, String endTime, Integer shopId) {
        Map<String, Object> orderPart = analyticsMapper.selectMemberOrderContribution(startTime, endTime, shopId,
                resolveOpenTime(shopId), resolveSettleTime(shopId));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("order_contribution", orderPart);
        if (orderPart != null) {
            double mem = toDouble(orderPart.get("member_net_revenue"));
            double tot = toDouble(orderPart.get("total_net_revenue"));
            orderPart.put("member_revenue_share", tot > 0 ? round4(mem / tot) : 0);
        }

        QueryWrapper<MemberRecharge> q = new QueryWrapper<MemberRecharge>()
                .eq("status", "success")
                .ge("pay_time", parseLooseDateTime(startTime))
                .lt("pay_time", parseLooseDateTime(endTime));
        if (shopId != null) {
            q.eq("shop_id", shopId);
        }
        List<MemberRecharge> rows = memberRechargeService.list(q);
        BigDecimal rechargeSum = BigDecimal.ZERO;
        BigDecimal giftSum = BigDecimal.ZERO;
        if (rows != null) {
            for (MemberRecharge r : rows) {
                if (r.getRecharge_amount() != null) {
                    rechargeSum = rechargeSum.add(r.getRecharge_amount());
                }
                if (r.getGift_amount() != null) {
                    giftSum = giftSum.add(r.getGift_amount());
                }
            }
        }
        Map<String, Object> recharge = new LinkedHashMap<>();
        recharge.put("recharge_amount_sum", rechargeSum);
        recharge.put("gift_amount_sum", giftSum);
        recharge.put("recharge_order_count", rows == null ? 0 : rows.size());
        out.put("recharge", recharge);
        return out;
    }

    @Override
    public Map<String, Object> marketingAnalysis(String startTime, String endTime, Integer shopId) {
        List<Map<String, Object>> coupons = analyticsMapper.selectCouponTemplateStats(startTime, endTime, shopId);
        if (coupons != null) {
            for (Map<String, Object> c : coupons) {
                long granted = toLong(c.get("granted_in_range"));
                long used = toLong(c.get("used_in_range"));
                c.put("redemption_rate", granted > 0 ? round4((double) used / (double) granted) : 0);
            }
        }
        List<Map<String, Object>> acts = analyticsMapper.selectActivityPopupStats(startTime, endTime, shopId);
        if (acts != null) {
            for (Map<String, Object> a : acts) {
                double budget = toDouble(a.get("budget_amount"));
                double overlap = toDouble(a.get("overlap_net_revenue"));
                a.put("roi_net_over_budget", budget > 0 ? round4(overlap / budget) : null);
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("coupons", coupons == null ? Collections.emptyList() : coupons);
        out.put("activity_popups", acts == null ? Collections.emptyList() : acts);
        out.put("notes", Arrays.asList(
                "弹窗活动 ROI 使用 overlap_net_revenue ÷ budget_amount；预算见 db_migration_activity_popup_budget.sql",
                "优惠券带动营收 driven_net_revenue 为核销订单净额汇总（与券模板关联的 order_no）"
        ));
        return out;
    }

    private static Date parseLooseDateTime(String s) {
        try {
            String t = s.replace('T', ' ');
            if (t.length() == 10) {
                t = t + " 00:00:00";
            }
            return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(t);
        } catch (Exception e) {
            return new Date(0);
        }
    }

    private static long inclusiveDays(String startTime, String endTime) {
        try {
            LocalDate s = LocalDate.parse(startTime.substring(0, 10), DateTimeFormatter.ISO_LOCAL_DATE);
            LocalDate e = LocalDate.parse(endTime.substring(0, 10), DateTimeFormatter.ISO_LOCAL_DATE);
            long d = ChronoUnit.DAYS.between(s, e) + 1;
            return Math.max(1, d);
        } catch (Exception ex) {
            return 1;
        }
    }

    private static Map<String, Object> mapOf(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) {
            m.put(String.valueOf(kv[i]), kv[i + 1]);
        }
        return m;
    }

    private static Double ratio(BigDecimal num, BigDecimal den) {
        if (num == null || den == null || den.compareTo(BigDecimal.ZERO) == 0) {
            return null;
        }
        return num.divide(den, 4, RoundingMode.HALF_UP).doubleValue();
    }

    /** 24小时周期起始时间为 settle_time。 */
    private String resolveOpenTime(Integer shopId) {
        Shop shop = shopId == null ? null : shopService.getById(shopId);
        return ShopBusinessWindowResolver.requireSettleTime(shop).toString();
    }
    /** 营业日截止（settle_time）：严格校验门店配置，无默认兜底。 */
    private String resolveSettleTime(Integer shopId) {
        Shop shop = shopId == null ? null : shopService.getById(shopId);
        return ShopBusinessWindowResolver.requireSettleTime(shop).toString();
    }

    private static double toDouble(Object o) {
        if (o == null) {
            return 0;
        }
        if (o instanceof Number) {
            return ((Number) o).doubleValue();
        }
        try {
            return Double.parseDouble(o.toString());
        } catch (Exception e) {
            return 0;
        }
    }

    private static long toLong(Object o) {
        if (o == null) {
            return 0;
        }
        if (o instanceof Number) {
            return ((Number) o).longValue();
        }
        try {
            return Long.parseLong(o.toString());
        } catch (Exception e) {
            return 0;
        }
    }

    private static BigDecimal toBigDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof BigDecimal) {
            return (BigDecimal) o;
        }
        if (o instanceof Number) {
            return BigDecimal.valueOf(((Number) o).doubleValue());
        }
        try {
            return new BigDecimal(o.toString());
        } catch (Exception e) {
            return null;
        }
    }

    /** 小时桶补充 start/end 墙钟标签与平均单笔；无单量时 avg_ticket=0。
     *  hour_key 为 bd_hour_NN（营业日偏移）时按 (N + openHour) % 24 换算回墙钟小时；
     *  纯数字键（墙钟小时）直接解析。 */
    private static List<Map<String, Object>> withAvgTicket(List<Map<String, Object>> rows, int openHour) {
        if (rows == null) {
            return Collections.emptyList();
        }
        for (Map<String, Object> row : rows) {
            long orderCount = toLong(row.get("order_count"));
            double net = toDouble(row.get("net_revenue"));
            row.put("avg_ticket", orderCount > 0 ? round2(net / orderCount) : 0);
            String hourKey = row.get("hour_key") == null ? "" : row.get("hour_key").toString();
            int hh;
            if (hourKey.startsWith("bd_hour_")) {
                hh = (parseHour(hourKey.substring("bd_hour_".length())) + openHour) % 24;
            } else {
                hh = parseHour(hourKey) % 24;
            }
            row.put("start", String.format("%02d:00", hh));
            row.put("end", String.format("%02d:00", (hh + 1) % 24));
        }
        return rows;
    }

    private static int parseMinute(String hhmm) {
        try {
            String[] parts = hhmm.split(":");
            if (parts.length > 1) {
                return Integer.parseInt(parts[1]);
            }
            return 0;
        } catch (Exception e) {
            return 0;
        }
    }

    private static int parseHour(String hh) {
        try {
            if (hh != null && hh.contains(":")) {
                hh = hh.substring(0, hh.indexOf(":"));
            }
            return Integer.parseInt(hh);
        } catch (Exception e) {
            return 0;
        }
    }

    private static double round2(double v) {
        return Math.round(v * 100) / 100.0;
    }

    private static double round4(double v) {
        return Math.round(v * 10000) / 10000.0;
    }
}
