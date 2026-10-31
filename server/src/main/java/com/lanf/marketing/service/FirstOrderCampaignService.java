package com.lanf.marketing.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.common.ApiException;
import com.lanf.marketing.entity.FirstOrderCampaign;
import com.lanf.marketing.entity.FirstOrderRedemption;
import com.lanf.marketing.mapper.FirstOrderCampaignMapper;
import com.lanf.marketing.mapper.FirstOrderRedemptionMapper;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 首单活动：创建/更新（时间窗不可叠加）、资格判定、核销记录。
 * 契约见《系统设置后端协调文档》§2/§4/§5：
 * - 叠加冲突 409 FIRST_ORDER_RULE_CONFLICT；
 * - 版本冲突 409 FIRST_ORDER_CAMPAIGN_VERSION_CONFLICT；
 * - 取消/全额退款后资格恢复（RESTORED 记录不算已核销）。
 */
@Service
public class FirstOrderCampaignService {

    private static final Logger log = LoggerFactory.getLogger(FirstOrderCampaignService.class);

    public static final String ERROR_RULE_CONFLICT = "FIRST_ORDER_RULE_CONFLICT";
    public static final String ERROR_VERSION_CONFLICT = "FIRST_ORDER_CAMPAIGN_VERSION_CONFLICT";
    public static final String ERROR_NOT_FOUND = "FIRST_ORDER_CAMPAIGN_NOT_FOUND";
    public static final String ERROR_VALIDATION = "FIRST_ORDER_VALIDATION_FAILED";

    public static final String STATUS_ACTIVE = "ACTIVE";
    public static final String REDEMPTION_USED = "USED";
    public static final String REDEMPTION_RESTORED = "RESTORED";

    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;

    @Autowired
    private FirstOrderCampaignMapper campaignMapper;
    @Autowired
    private FirstOrderRedemptionMapper redemptionMapper;
    @Autowired
    private JdbcTemplate jdbcTemplate;

    // ---------------- 活动列表 ----------------

    public Map<String, Object> listCampaigns(int shopId, String status, int page, int pageSize) {
        QueryWrapper<FirstOrderCampaign> q = new QueryWrapper<>();
        q.eq("shop_id", shopId);
        if (!StringUtil.isEmpty(status)) {
            q.eq("status", status.toUpperCase());
        }
        q.orderByDesc("id");
        List<FirstOrderCampaign> all = campaignMapper.selectList(q);
        int total = all.size();
        List<Map<String, Object>> items = new ArrayList<>();
        int from = Math.max(0, (page - 1) * pageSize);
        int to = Math.min(total, from + pageSize);
        for (FirstOrderCampaign c : all.subList(from, to)) {
            Map<String, Object> view = toView(c);
            view.put("stats", statsOf(shopId, c.getId()));
            items.add(view);
        }
        return pageResult(page, pageSize, total, items);
    }

    // ---------------- 创建 / 更新 ----------------

    public Map<String, Object> createCampaign(int shopId, Map<String, Object> body, Integer adminId) {
        FirstOrderCampaign c = new FirstOrderCampaign();
        c.setShop_id(shopId);
        fillFromBody(c, body, true);
        if (STATUS_ACTIVE.equals(c.getStatus())) {
            assertNoOverlap(shopId, null, c);
        }
        c.setVersion(1);
        c.setCreated_at(LocalDateTime.now(ZONE));
        c.setUpdated_at(LocalDateTime.now(ZONE));
        campaignMapper.insert(c);
        log.info("[first-order] campaign created: shop_id={}, id={}, by={}", shopId, c.getId(), adminId);
        return toView(c);
    }

    public Map<String, Object> updateCampaign(int shopId, long id, Map<String, Object> body, Integer adminId) {
        FirstOrderCampaign c = requireCampaign(shopId, id);
        Integer expectedVersion = body.get("version") instanceof Number
                ? ((Number) body.get("version")).intValue() : null;
        if (expectedVersion == null) {
            throw new ApiException(400, "FIRST_ORDER_VERSION_REQUIRED", "更新请求必须携带 version 乐观锁");
        }
        if (!expectedVersion.equals(c.getVersion())) {
            throw versionConflict(c);
        }
        fillFromBody(c, body, false);
        if (STATUS_ACTIVE.equals(c.getStatus())) {
            assertNoOverlap(shopId, c.getId(), c);
        }
        c.setVersion(c.getVersion() + 1);
        c.setUpdated_at(LocalDateTime.now(ZONE));
        campaignMapper.updateById(c);
        log.info("[first-order] campaign updated: shop_id={}, id={}, version={}, by={}", shopId, id, c.getVersion(), adminId);
        return toView(c);
    }

    // ---------------- 资格判定 ----------------

    /**
     * 判定客户是否可享首单优惠。
     * customerId 支持 openid 或会员手机号；资格规则：
     * 1. 店内存在 ACTIVE 活动；2. 无 USED 核销记录（RESTORED 视为恢复资格）；
     * 3. 店内无已完成订单（transac_status=success，按 openid 或 member_phone 匹配）；
     * 4. 订单金额达标。
     */
    public Map<String, Object> evaluate(int shopId, String customerId, BigDecimal orderAmount) {
        if (StringUtil.isEmpty(customerId)) {
            throw new ApiException(400, ERROR_VALIDATION, "customerId 不能为空");
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("customerId", customerId);
        out.put("shopId", shopId);
        out.put("conflicts", new ArrayList<>());

        List<FirstOrderCampaign> actives = activeCampaigns(shopId);
        if (actives.isEmpty()) {
            out.put("eligible", false);
            out.put("reason", "no_active_campaign");
            return out;
        }
        if (actives.size() > 1) {
            List<Map<String, Object>> conflicts = new ArrayList<>();
            for (FirstOrderCampaign other : actives) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", other.getId());
                m.put("name", other.getName());
                conflicts.add(m);
            }
            out.put("conflicts", conflicts);
        }

        Integer used = redemptionMapper.selectCount(new QueryWrapper<FirstOrderRedemption>()
                .eq("shop_id", shopId).eq("customer_id", customerId).eq("status", REDEMPTION_USED));
        if (used != null && used > 0) {
            out.put("eligible", false);
            out.put("reason", "already_redeemed");
            return out;
        }

        int priorOrders = countCompletedOrders(shopId, customerId);
        if (priorOrders > 0) {
            out.put("eligible", false);
            out.put("reason", "has_prior_order");
            return out;
        }

        FirstOrderCampaign best = actives.get(0);
        if (orderAmount != null && best.getThreshold_amount() != null
                && orderAmount.compareTo(best.getThreshold_amount()) < 0) {
            out.put("eligible", false);
            out.put("reason", "below_threshold");
            out.put("campaign", toView(best));
            return out;
        }

        out.put("eligible", true);
        out.put("reason", null);
        out.put("campaign", toView(best));
        return out;
    }

    // ---------------- 核销记录 ----------------

    public Map<String, Object> listRedemptions(int shopId, Long campaignId, String customerId,
                                               String orderNo, int page, int pageSize) {
        QueryWrapper<FirstOrderRedemption> q = new QueryWrapper<>();
        q.eq("shop_id", shopId);
        if (campaignId != null) {
            q.eq("campaign_id", campaignId);
        }
        if (!StringUtil.isEmpty(customerId)) {
            q.eq("customer_id", customerId);
        }
        if (!StringUtil.isEmpty(orderNo)) {
            q.eq("order_no", orderNo);
        }
        q.orderByDesc("id");
        List<FirstOrderRedemption> all = redemptionMapper.selectList(q);
        int total = all.size();
        List<Map<String, Object>> items = new ArrayList<>();
        int from = Math.max(0, (page - 1) * pageSize);
        int to = Math.min(total, from + pageSize);
        for (FirstOrderRedemption r : all.subList(from, to)) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", r.getId());
            m.put("campaignId", r.getCampaign_id());
            m.put("customerId", r.getCustomer_id());
            m.put("orderNo", r.getOrder_no());
            m.put("orderId", r.getOrder_id());
            m.put("amount", r.getAmount());
            m.put("status", r.getStatus());
            m.put("restoredReason", r.getRestored_reason());
            m.put("restoredAt", iso(r.getRestored_at()));
            m.put("createdAt", iso(r.getCreated_at()));
            items.add(m);
        }
        return pageResult(page, pageSize, total, items);
    }

    // ---------------- 内部 ----------------

    private List<FirstOrderCampaign> activeCampaigns(int shopId) {
        LocalDateTime now = LocalDateTime.now(ZONE);
        return campaignMapper.selectList(new QueryWrapper<FirstOrderCampaign>()
                .eq("shop_id", shopId).eq("status", STATUS_ACTIVE)
                .le("start_time", now).ge("end_time", now)
                .orderByDesc("discount_value"));
    }

    /** 不可叠加：同店时间窗重叠的 ACTIVE 活动只能有一个 */
    private void assertNoOverlap(int shopId, Long selfId, FirstOrderCampaign c) {
        QueryWrapper<FirstOrderCampaign> q = new QueryWrapper<>();
        q.eq("shop_id", shopId).eq("status", STATUS_ACTIVE)
                .lt("start_time", c.getEnd_time()).gt("end_time", c.getStart_time());
        if (selfId != null) {
            q.ne("id", selfId);
        }
        List<FirstOrderCampaign> conflicts = campaignMapper.selectList(q);
        if (!conflicts.isEmpty()) {
            List<Map<String, Object>> data = new ArrayList<>();
            for (FirstOrderCampaign other : conflicts) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", other.getId());
                m.put("name", other.getName());
                m.put("startTime", iso(other.getStart_time()));
                m.put("endTime", iso(other.getEnd_time()));
                data.add(m);
            }
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("conflicts", data);
            throw new ApiException(409, ERROR_RULE_CONFLICT, "与现有生效活动时间窗重叠，首单活动不可叠加", body);
        }
    }

    private int countCompletedOrders(int shopId, String customerId) {
        try {
            Integer count = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM t_order WHERE shop_id=? AND transac_status='success' "
                            + "AND (openid=? OR member_phone=? OR pay_openid=?)",
                    Integer.class, shopId, customerId, customerId, customerId);
            return count != null ? count : 0;
        } catch (Exception e) {
            log.warn("[first-order] 历史订单计数失败（缺列/缺表时视为无历史单）: {}", e.getMessage());
            return 0;
        }
    }

    private Map<String, Object> statsOf(int shopId, Long campaignId) {
        Integer used = redemptionMapper.selectCount(new QueryWrapper<FirstOrderRedemption>()
                .eq("shop_id", shopId).eq("campaign_id", campaignId).eq("status", REDEMPTION_USED));
        Integer restored = redemptionMapper.selectCount(new QueryWrapper<FirstOrderRedemption>()
                .eq("shop_id", shopId).eq("campaign_id", campaignId).eq("status", REDEMPTION_RESTORED));
        Map<String, Object> stats = new LinkedHashMap<>();
        stats.put("redemptions", used != null ? used : 0);
        stats.put("restorations", restored != null ? restored : 0);
        return stats;
    }

    private void fillFromBody(FirstOrderCampaign c, Map<String, Object> body, boolean creating) {
        if (body == null) {
            throw new ApiException(400, ERROR_VALIDATION, "请求体不能为空");
        }
        if (creating) {
            requireText(body, "name");
            requireText(body, "campaignType");
            requireText(body, "startTime");
            requireText(body, "endTime");
        }
        if (body.get("name") != null) {
            c.setName(String.valueOf(body.get("name")));
        }
        if (body.get("campaignType") != null) {
            String type = String.valueOf(body.get("campaignType"));
            if (!type.matches("DISCOUNT|GIFT|FREEBIE")) {
                throw new ApiException(400, ERROR_VALIDATION, "campaignType 仅支持 DISCOUNT/GIFT/FREEBIE");
            }
            c.setCampaign_type(type);
        }
        if (body.get("thresholdAmount") != null) {
            c.setThreshold_amount(new BigDecimal(String.valueOf(body.get("thresholdAmount"))));
        }
        if (body.get("discountValue") != null) {
            c.setDiscount_value(new BigDecimal(String.valueOf(body.get("discountValue"))));
        }
        if (body.get("discountDesc") != null) {
            c.setDiscount_desc(String.valueOf(body.get("discountDesc")));
        }
        if (body.get("startTime") != null) {
            c.setStart_time(parseTime(body.get("startTime"), "startTime"));
        }
        if (body.get("endTime") != null) {
            c.setEnd_time(parseTime(body.get("endTime"), "endTime"));
        }
        if (body.get("status") != null) {
            String status = String.valueOf(body.get("status")).toUpperCase();
            if (!status.matches("DRAFT|ACTIVE|PAUSED|EXPIRED")) {
                throw new ApiException(400, ERROR_VALIDATION, "status 仅支持 DRAFT/ACTIVE/PAUSED/EXPIRED");
            }
            c.setStatus(status);
        } else if (creating) {
            c.setStatus("DRAFT");
        }
        if (c.getStart_time() != null && c.getEnd_time() != null && !c.getStart_time().isBefore(c.getEnd_time())) {
            throw new ApiException(400, ERROR_VALIDATION, "startTime 必须早于 endTime");
        }
        if (c.getThreshold_amount() == null) {
            c.setThreshold_amount(BigDecimal.ZERO);
        }
        if (c.getDiscount_value() == null) {
            c.setDiscount_value(BigDecimal.ZERO);
        }
    }

    private void requireText(Map<String, Object> body, String field) {
        if (body.get(field) == null || String.valueOf(body.get(field)).trim().isEmpty()) {
            throw new ApiException(400, ERROR_VALIDATION, field + " 不能为空");
        }
    }

    private LocalDateTime parseTime(Object raw, String field) {
        try {
            return LocalDateTime.parse(String.valueOf(raw).replace(' ', 'T'));
        } catch (Exception e) {
            throw new ApiException(400, ERROR_VALIDATION, field + " 格式应为 yyyy-MM-dd HH:mm:ss");
        }
    }

    private FirstOrderCampaign requireCampaign(int shopId, long id) {
        FirstOrderCampaign c = campaignMapper.selectById(id);
        if (c == null || !Integer.valueOf(shopId).equals(c.getShop_id())) {
            throw new ApiException(404, ERROR_NOT_FOUND, "首单活动不存在");
        }
        return c;
    }

    private ApiException versionConflict(FirstOrderCampaign c) {
        Map<String, Object> latest = new LinkedHashMap<>();
        latest.put("id", c.getId());
        latest.put("version", c.getVersion());
        latest.put("name", c.getName());
        latest.put("updatedAt", iso(c.getUpdated_at()));
        return new ApiException(409, ERROR_VERSION_CONFLICT, "活动已被他人修改，请重新加载", latest);
    }

    private Map<String, Object> toView(FirstOrderCampaign c) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", c.getId());
        m.put("shopId", c.getShop_id());
        m.put("name", c.getName());
        m.put("campaignType", c.getCampaign_type());
        m.put("thresholdAmount", c.getThreshold_amount());
        m.put("discountValue", c.getDiscount_value());
        m.put("discountDesc", c.getDiscount_desc());
        m.put("startTime", iso(c.getStart_time()));
        m.put("endTime", iso(c.getEnd_time()));
        m.put("status", c.getStatus());
        m.put("version", c.getVersion());
        m.put("updatedAt", iso(c.getUpdated_at()));
        return m;
    }

    private String iso(LocalDateTime t) {
        return t == null ? null : t.atZone(ZONE).format(ISO);
    }

    private Map<String, Object> pageResult(int page, int pageSize, int total, List<?> items) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("page", page);
        out.put("pageSize", pageSize);
        out.put("total", total);
        out.put("items", items);
        return out;
    }
}
