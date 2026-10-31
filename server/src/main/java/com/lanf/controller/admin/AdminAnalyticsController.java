package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.service.IAnalyticsService;
import com.lanf.service.IShopService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.ShopBusinessWindowResolver;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 数据分析模块：营业、菜品、顾客、会员、营销活动（运营端）。
 * 时间参数格式：支持纯日期 yyyy-MM-dd（自动按门店 settle_time 补全为营业日区间）或带时分秒自定义时间；
 * 门店范围由请求头 X-Shop-Id 解析（与现有后台一致）。
 */
@RestController
@RequestMapping("/admin/analytics")
public class AdminAnalyticsController {

    @Resource
    private IAnalyticsService analyticsService;
    @Resource
    private IShopService shopService;
    @Resource
    private HttpServletRequest httpServletRequest;

    /**
     * 营业数据：核心指标一套；自然日 / 营业日（open_time 起点 / settle_time 截止）两套 derived（翻台、上座率分母不同）；墙钟分时段 + 营业锚点分时段；支付渠道。
     */
    @GetMapping("/business")
    public R business(@RequestParam(required = false) String startTime,
                      @RequestParam(required = false) String endTime,
                      @RequestParam(required = false) String startDate,
                      @RequestParam(required = false) String endDate,
                      @RequestParam(required = false) String start,
                      @RequestParam(required = false) String end) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String[] w = resolveWindow(startTime, endTime, startDate, endDate, start, end, shopId);
        Map<String, Object> data = analyticsService.businessOverview(w[0], w[1], shopId);
        return R.ok().put("data", data);
    }

    /**
     * 营业趋势：granularity=day|week|month|year；返回 natural_calendar 与 business_day 两套 series（分桶基准不同）。
     */
    @GetMapping("/business/trend")
    public R businessTrend(@RequestParam(required = false) String startTime,
                           @RequestParam(required = false) String endTime,
                           @RequestParam(required = false) String startDate,
                           @RequestParam(required = false) String endDate,
                           @RequestParam(required = false) String start,
                           @RequestParam(required = false) String end,
                           @RequestParam(required = false, defaultValue = "day") String granularity) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String[] w = resolveWindow(startTime, endTime, startDate, endDate, start, end, shopId);
        Map<String, Object> data = analyticsService.businessTrend(w[0], w[1], shopId, granularity);
        return R.ok().put("data", data);
    }

    /**
     * 菜品：销量榜、热销/滞销、毛利、套餐/单点占比；新品走势按自然日与营业日各一套。
     */
    @GetMapping("/dishes")
    public R dishes(@RequestParam(required = false) String startTime,
                    @RequestParam(required = false) String endTime,
                    @RequestParam(required = false) String startDate,
                    @RequestParam(required = false) String endDate,
                    @RequestParam(required = false) String start,
                    @RequestParam(required = false) String end,
                    @RequestParam(required = false, defaultValue = "100") int limit) {
        if (limit <= 0 || limit > 500) {
            limit = 100;
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String[] w = resolveWindow(startTime, endTime, startDate, endDate, start, end, shopId);
        Map<String, Object> data = analyticsService.dishAnalysis(w[0], w[1], shopId, limit);
        return R.ok().put("data", data);
    }

    /**
     * 顾客：新客/老客、周期内复购率、到店频次分布、口味与忌口关键词统计。
     */
    @GetMapping("/customers")
    public R customers(@RequestParam(required = false) String startTime,
                       @RequestParam(required = false) String endTime,
                       @RequestParam(required = false) String startDate,
                       @RequestParam(required = false) String endDate,
                       @RequestParam(required = false) String start,
                       @RequestParam(required = false) String end) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String[] w = resolveWindow(startTime, endTime, startDate, endDate, start, end, shopId);
        Map<String, Object> data = analyticsService.customerAnalysis(w[0], w[1], shopId);
        return R.ok().put("data", data);
    }

    /**
     * 会员：订单净额贡献率、充值与赠送金额汇总（t_member_recharge success）。
     */
    @GetMapping("/members")
    public R members(@RequestParam(required = false) String startTime,
                     @RequestParam(required = false) String endTime,
                     @RequestParam(required = false) String startDate,
                     @RequestParam(required = false) String endDate,
                     @RequestParam(required = false) String start,
                     @RequestParam(required = false) String end) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String[] w = resolveWindow(startTime, endTime, startDate, endDate, start, end, shopId);
        Map<String, Object> data = analyticsService.memberAnalysis(w[0], w[1], shopId);
        return R.ok().put("data", data);
    }

    /**
     * 营销：优惠券发放/核销/带动营收；弹窗活动引流与重叠窗口营业额、ROI（需 budget_amount）。
     */
    @GetMapping("/marketing")
    public R marketing(@RequestParam(required = false) String startTime,
                       @RequestParam(required = false) String endTime,
                       @RequestParam(required = false) String startDate,
                       @RequestParam(required = false) String endDate,
                       @RequestParam(required = false) String start,
                       @RequestParam(required = false) String end) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        String[] w = resolveWindow(startTime, endTime, startDate, endDate, start, end, shopId);
        Map<String, Object> data = analyticsService.marketingAnalysis(w[0], w[1], shopId);
        return R.ok().put("data", data);
    }

    public R business(String startTime, String endTime) {
        return business(startTime, endTime, null, null, null, null);
    }

    public R businessTrend(String startTime, String endTime, String granularity) {
        return businessTrend(startTime, endTime, null, null, null, null, granularity);
    }

    public R dishes(String startTime, String endTime, int limit) {
        return dishes(startTime, endTime, null, null, null, null, limit);
    }

    public R customers(String startTime, String endTime) {
        return customers(startTime, endTime, null, null, null, null);
    }

    public R members(String startTime, String endTime) {
        return members(startTime, endTime, null, null, null, null);
    }

    public R marketing(String startTime, String endTime) {
        return marketing(startTime, endTime, null, null, null, null);
    }

    /**
     * 解析时间窗口：
     * 1. 优先提取入参候选（兼容 startTime/startDate/start 以及 endTime/endDate/end）；
     * 2. 纯日期（如 2026-10-08）按门店 settle_time 自动补全为营业日区间 [start settle, (end+1) settle)；
     * 3. 自定义时间（带时分秒）保留输入时分秒；
     * 4. 两端未传时使用门店默认最近已结算营业日窗口。
     */
    private String[] resolveWindow(String startTime, String endTime,
                                   String startDate, String endDate,
                                   String start, String end,
                                   Integer shopId) {
        String startCandidate = firstNonEmpty(startTime, startDate, start);
        String endCandidate = firstNonEmpty(endTime, endDate, end);
        Shop shop = shopId == null ? null : shopService.getById(shopId);
        return ShopBusinessWindowResolver.resolveReportWindowText(shop, startCandidate, endCandidate);
    }

    private static String firstNonEmpty(String... values) {
        if (values == null) {
            return null;
        }
        for (String v : values) {
            if (v != null && !v.trim().isEmpty()) {
                return v.trim();
            }
        }
        return null;
    }
}
