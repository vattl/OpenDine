package com.lanf.notify.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.notify.entity.NotificationDelivery;
import com.lanf.notify.entity.NotificationRule;
import com.lanf.notify.mapper.NotificationDeliveryMapper;
import com.lanf.notify.mapper.NotificationRuleMapper;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 通知规则与发送记录。契约见《系统设置后端协调文档》§2：
 * 规则增删改带 version 乐观锁（409）；删除/停用写审计；接收人脱敏；记录仅在线查询近 30 天。
 */
@Service
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    public static final String ERROR_VERSION_CONFLICT = "NOTIFICATIONS_VERSION_CONFLICT";
    public static final String ERROR_RULE_NOT_FOUND = "NOTIFICATIONS_RULE_NOT_FOUND";
    public static final String ERROR_CONFIRM_REQUIRED = "NOTIFICATIONS_CONFIRM_REQUIRED";
    public static final String ERROR_VALIDATION = "NOTIFICATIONS_VALIDATION_FAILED";
    public static final String ERROR_ARCHIVED_ONLY = "NOTIFICATIONS_ARCHIVED_ONLY";

    /** 在线可查询窗口：30 天 */
    public static final int ONLINE_QUERY_DAYS = 30;

    private static final ZoneId ZONE = ZoneId.of("+08:00");
    private static final DateTimeFormatter ISO = DateTimeFormatter.ISO_OFFSET_DATE_TIME;
    private static final Set<String> KNOWN_EVENT_TYPES = new HashSet<>(Arrays.asList(
            "order_new", "order_refund", "order_cancel", "stock_low", "shift_close",
            "device_offline", "payment_failed", "custom"));
    private static final Set<String> KNOWN_CHANNELS = new HashSet<>(Arrays.asList("app", "sms", "printer", "webhook"));

    @Autowired
    private NotificationRuleMapper ruleMapper;
    @Autowired
    private NotificationDeliveryMapper deliveryMapper;
    @Autowired
    private ObjectMapper objectMapper;

    // ---------------- 规则列表 ----------------

    public Map<String, Object> listRules(int shopId, String eventType, int page, int pageSize) {
        com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<NotificationRule> q =
                new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<>();
        q.eq("shop_id", shopId);
        if (!StringUtil.isEmpty(eventType)) {
            q.eq("event_type", eventType);
        }
        q.orderByAsc("id");
        List<NotificationRule> all = ruleMapper.selectList(q);
        int total = all.size();
        List<Map<String, Object>> items = new ArrayList<>();
        int from = Math.max(0, (page - 1) * pageSize);
        int to = Math.min(total, from + pageSize);
        for (NotificationRule rule : all.subList(from, to)) {
            items.add(toView(rule));
        }
        return pageResult(page, pageSize, total, items);
    }

    // ---------------- 创建 ----------------

    public Map<String, Object> createRule(int shopId, Map<String, Object> body, Integer adminId) {
        NotificationRule rule = new NotificationRule();
        rule.setShop_id(shopId);
        fillFromBody(rule, body);
        rule.setVersion(1);
        rule.setCreated_at(LocalDateTime.now(ZONE));
        rule.setUpdated_at(LocalDateTime.now(ZONE));
        ruleMapper.insert(rule);
        log.info("[notify] rule created: shop_id={}, id={}, by={}", shopId, rule.getId(), adminId);
        return toView(rule);
    }

    // ---------------- 更新 ----------------

    public Map<String, Object> updateRule(int shopId, long ruleId, Map<String, Object> body, Integer adminId) {
        NotificationRule rule = requireRule(shopId, ruleId);
        Integer expectedVersion = body.get("version") instanceof Number
                ? ((Number) body.get("version")).intValue() : null;
        if (expectedVersion == null) {
            throw new ApiException(400, "NOTIFICATIONS_VERSION_REQUIRED", "更新请求必须携带 version 乐观锁");
        }
        if (!expectedVersion.equals(rule.getVersion())) {
            throw versionConflict(rule);
        }
        fillFromBody(rule, body);
        rule.setVersion(rule.getVersion() + 1);
        rule.setUpdated_at(LocalDateTime.now(ZONE));
        ruleMapper.updateById(rule);
        log.info("[notify] rule updated: shop_id={}, id={}, version={}, by={}", shopId, ruleId, rule.getVersion(), adminId);
        return toView(rule);
    }

    // ---------------- 删除 ----------------

    public void deleteRule(int shopId, long ruleId, Integer expectedVersion, boolean confirm, Integer adminId) {
        if (!confirm) {
            throw new ApiException(400, ERROR_CONFIRM_REQUIRED, "删除通知规则需要二次确认（confirm=true）");
        }
        NotificationRule rule = requireRule(shopId, ruleId);
        if (expectedVersion == null || !expectedVersion.equals(rule.getVersion())) {
            throw versionConflict(rule);
        }
        ruleMapper.deleteById(ruleId);
        log.info("[notify] rule deleted: shop_id={}, id={}, by={}", shopId, ruleId, adminId);
    }

    // ---------------- 试发 ----------------

    /**
     * 试发：为规则创建一条发送记录。当前实现仅落库记录（真实通道发送为后续迭代），
     * title 前缀 [试发]，接收人脱敏存储。
     */
    public Map<String, Object> testDelivery(int shopId, long ruleId, Map<String, Object> body, Integer adminId) {
        NotificationRule rule = requireRule(shopId, ruleId);
        List<String> channels = toStringList(parseJson(rule.getChannels_json()));
        if (body != null && body.get("channel") != null) {
            String ch = String.valueOf(body.get("channel"));
            if (!KNOWN_CHANNELS.contains(ch)) {
                throw new ApiException(400, ERROR_VALIDATION, "未知通知渠道: " + ch);
            }
            channels = new ArrayList<>(Collections.singleton(ch));
        }
        String recipientRaw = body != null && body.get("recipient") != null
                ? String.valueOf(body.get("recipient")) : defaultRecipient(rule);
        String masked = maskPhone(recipientRaw);

        List<Map<String, Object>> deliveries = new ArrayList<>();
        for (String channel : channels) {
            NotificationDelivery d = new NotificationDelivery();
            d.setShop_id(shopId);
            d.setRule_id(ruleId);
            d.setEvent_type(rule.getEvent_type());
            d.setChannel(channel);
            d.setRecipient_masked(masked);
            d.setTitle("[试发] " + rule.getName());
            d.setStatus("SENT");
            d.setRetry_count(0);
            d.setCreated_at(LocalDateTime.now(ZONE));
            d.setUpdated_at(LocalDateTime.now(ZONE));
            deliveryMapper.insert(d);
            deliveries.add(toDeliveryView(d));
        }
        log.info("[notify] test delivery: shop_id={}, rule={}, channels={}, by={}", shopId, ruleId, channels, adminId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("deliveryId", deliveries.isEmpty() ? null : deliveries.get(0).get("deliveryId"));
        out.put("deliveries", deliveries);
        out.put("status", "SENT");
        return out;
    }

    // ---------------- 发送记录 ----------------

    public Map<String, Object> listDeliveries(int shopId, Long ruleId, String channel, String status,
                                              String from, String to, int page, int pageSize) {
        LocalDateTime fromTime = parseTime(from);
        LocalDateTime toTime = parseTime(to);
        LocalDateTime windowStart = LocalDateTime.now(ZONE).minusDays(ONLINE_QUERY_DAYS);
        if (toTime != null && toTime.isBefore(windowStart)) {
            throw new ApiException(400, ERROR_ARCHIVED_ONLY,
                    "所选时间已超出在线查询窗口（近 30 天），请改用归档检索");
        }
        com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<NotificationDelivery> q =
                new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<>();
        q.eq("shop_id", shopId);
        if (ruleId != null) {
            q.eq("rule_id", ruleId);
        }
        if (!StringUtil.isEmpty(channel)) {
            q.eq("channel", channel);
        }
        if (!StringUtil.isEmpty(status)) {
            q.eq("status", status.toUpperCase());
        }
        q.ge("created_at", fromTime != null && fromTime.isAfter(windowStart) ? fromTime : windowStart);
        if (toTime != null) {
            q.le("created_at", toTime);
        }
        q.orderByDesc("id");
        List<NotificationDelivery> all = deliveryMapper.selectList(q);
        int total = all.size();
        List<Map<String, Object>> items = new ArrayList<>();
        int fromIdx = Math.max(0, (page - 1) * pageSize);
        int toIdx = Math.min(total, fromIdx + pageSize);
        for (NotificationDelivery d : all.subList(fromIdx, toIdx)) {
            items.add(toDeliveryView(d));
        }
        Map<String, Object> out = pageResult(page, pageSize, total, items);
        out.put("onlineWindowDays", ONLINE_QUERY_DAYS);
        return out;
    }

    // ---------------- 内部 ----------------

    private NotificationRule requireRule(int shopId, long ruleId) {
        NotificationRule rule = ruleMapper.selectById(ruleId);
        if (rule == null || !Integer.valueOf(shopId).equals(rule.getShop_id())) {
            throw new ApiException(404, ERROR_RULE_NOT_FOUND, "通知规则不存在");
        }
        return rule;
    }

    private void fillFromBody(NotificationRule rule, Map<String, Object> body) {
        if (body == null) {
            throw new ApiException(400, ERROR_VALIDATION, "请求体不能为空");
        }
        String name = trim(body.get("name"));
        String eventType = trim(body.get("eventType"));
        if (rule.getId() == null) {
            if (StringUtil.isEmpty(name)) {
                throw new ApiException(400, ERROR_VALIDATION, "规则名称不能为空");
            }
            if (StringUtil.isEmpty(eventType)) {
                throw new ApiException(400, ERROR_VALIDATION, "eventType 不能为空");
            }
        }
        if (name != null) {
            rule.setName(name);
        }
        if (eventType != null) {
            if (!KNOWN_EVENT_TYPES.contains(eventType)) {
                throw new ApiException(400, ERROR_VALIDATION, "未知事件类型: " + eventType);
            }
            rule.setEvent_type(eventType);
        }
        if (body.containsKey("channels")) {
            rule.setChannels_json(json(body.get("channels")));
        }
        if (body.containsKey("recipients")) {
            rule.setRecipients_json(json(body.get("recipients")));
        }
        if (body.containsKey("timeWindow")) {
            rule.setTime_window_json(json(body.get("timeWindow")));
        }
        if (body.containsKey("frequencyControl")) {
            rule.setFrequency_control_json(json(body.get("frequencyControl")));
        }
        if (body.containsKey("enabled")) {
            Object e = body.get("enabled");
            rule.setEnabled(Boolean.TRUE.equals(e) || "1".equals(String.valueOf(e)) ? 1 : 0);
        }
    }

    private ApiException versionConflict(NotificationRule rule) {
        Map<String, Object> latest = new LinkedHashMap<>();
        latest.put("id", rule.getId());
        latest.put("version", rule.getVersion());
        latest.put("name", rule.getName());
        latest.put("updatedAt", iso(rule.getUpdated_at()));
        return new ApiException(409, ERROR_VERSION_CONFLICT, "通知规则已被他人修改，请重新加载", latest);
    }

    private Map<String, Object> toView(NotificationRule rule) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", rule.getId());
        m.put("shopId", rule.getShop_id());
        m.put("name", rule.getName());
        m.put("eventType", rule.getEvent_type());
        m.put("channels", parseJson(rule.getChannels_json()));
        m.put("recipients", maskRecipients(parseJson(rule.getRecipients_json())));
        m.put("timeWindow", parseJson(rule.getTime_window_json()));
        m.put("frequencyControl", parseJson(rule.getFrequency_control_json()));
        m.put("enabled", rule.getEnabled() != null && rule.getEnabled() == 1);
        m.put("version", rule.getVersion());
        m.put("updatedAt", iso(rule.getUpdated_at()));
        return m;
    }

    private Map<String, Object> toDeliveryView(NotificationDelivery d) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("deliveryId", d.getId());
        m.put("ruleId", d.getRule_id());
        m.put("eventType", d.getEvent_type());
        m.put("channel", d.getChannel());
        m.put("recipient", d.getRecipient_masked());
        m.put("title", d.getTitle());
        m.put("status", d.getStatus());
        m.put("error", d.getError());
        m.put("retryCount", d.getRetry_count());
        m.put("createdAt", iso(d.getCreated_at()));
        return m;
    }

    /** 手机号脱敏：138****1234 */
    public static String maskPhone(String raw) {
        if (raw == null) {
            return null;
        }
        String digits = raw.replaceAll("\\D", "");
        if (digits.length() == 11 && digits.startsWith("1")) {
            return digits.substring(0, 3) + "****" + digits.substring(7);
        }
        if (raw.length() <= 3) {
            return raw + "***";
        }
        return raw.substring(0, 2) + "***" + raw.substring(raw.length() - 1);
    }

    @SuppressWarnings("unchecked")
    private Object maskRecipients(Object parsed) {
        if (!(parsed instanceof List)) {
            return parsed;
        }
        List<Object> masked = new ArrayList<>();
        for (Object item : (List<Object>) parsed) {
            if (item instanceof Map) {
                Map<String, Object> r = new LinkedHashMap<>((Map<String, Object>) item);
                if (r.get("phone") != null) {
                    r.put("phone", maskPhone(String.valueOf(r.get("phone"))));
                }
                masked.add(r);
            } else {
                masked.add(item);
            }
        }
        return masked;
    }

    private Object parseJson(String raw) {
        if (StringUtil.isEmpty(raw)) {
            return null;
        }
        try {
            return objectMapper.readValue(raw, new TypeReference<Object>() {
            });
        } catch (Exception e) {
            return null;
        }
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (Exception e) {
            throw new ApiException(500, "NOTIFICATIONS_SERIALIZE_FAILED", "配置序列化失败");
        }
    }

    private List<String> toStringList(Object parsed) {
        if (!(parsed instanceof List)) {
            return new ArrayList<>();
        }
        List<String> out = new ArrayList<>();
        for (Object o : (List<Object>) parsed) {
            if (o != null) {
                out.add(String.valueOf(o));
            }
        }
        return out;
    }

    private String defaultRecipient(NotificationRule rule) {
        Object recipients = parseJson(rule.getRecipients_json());
        if (recipients instanceof List && !((List<Object>) recipients).isEmpty()) {
            Object first = ((List<Object>) recipients).get(0);
            if (first instanceof Map && ((Map<String, Object>) first).get("phone") != null) {
                return String.valueOf(((Map<String, Object>) first).get("phone"));
            }
            return String.valueOf(first);
        }
        return "-";
    }

    private LocalDateTime parseTime(String raw) {
        if (StringUtil.isEmpty(raw)) {
            return null;
        }
        try {
            return LocalDateTime.parse(raw.replace(' ', 'T'));
        } catch (Exception e) {
            throw new ApiException(400, ERROR_VALIDATION, "时间格式应为 yyyy-MM-dd HH:mm:ss: " + raw);
        }
    }

    private String iso(LocalDateTime t) {
        return t == null ? null : t.atZone(ZONE).format(ISO);
    }

    private String trim(Object o) {
        return o == null ? null : String.valueOf(o).trim();
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
