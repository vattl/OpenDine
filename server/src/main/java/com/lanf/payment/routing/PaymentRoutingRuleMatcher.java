package com.lanf.payment.routing;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.*;

/**
 * 门店商户多条件路由匹配器。
 * 支持就餐方式、实付金额区间、菜品/分类明细及下单时段的多维度匹配与 AND/OR 组合。
 */
@Component
public class PaymentRoutingRuleMatcher {

    private static final Logger log = LoggerFactory.getLogger(PaymentRoutingRuleMatcher.class);
    private static final ZoneId DEFAULT_ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private ObjectMapper objectMapper;

    public boolean isMatch(String conditionsJson, String matchMode, PaymentRoutingContext ctx) {
        if (!StringUtils.hasText(conditionsJson)) {
            return true;
        }
        try {
            JsonNode root = objectMapper.readTree(conditionsJson);
            return isMatch(root, matchMode, ctx);
        } catch (Exception e) {
            log.warn("解析路由规则 conditionsJson 失败: {}", e.getMessage());
            return false;
        }
    }

    public boolean isMatch(JsonNode root, String matchMode, PaymentRoutingContext ctx) {
        if (root == null || !root.isObject() || root.size() == 0) {
            return true;
        }
        if (ctx == null) {
            return false;
        }

        boolean isOr = "ANY".equalsIgnoreCase(matchMode);
        List<Boolean> evaluatedResults = new ArrayList<>();

        // 1. 就餐方式维度 (diningTypes)
        JsonNode diningTypesNode = root.path("diningTypes");
        if (diningTypesNode.isArray() && diningTypesNode.size() > 0) {
            evaluatedResults.add(matchDiningTypes(diningTypesNode, ctx.diningType));
        }

        // 2. 金额区间维度 (minPaidYuan / maxPaidYuan)
        boolean hasMin = root.has("minPaidYuan") && root.path("minPaidYuan").isNumber();
        boolean hasMax = root.has("maxPaidYuan") && root.path("maxPaidYuan").isNumber();
        if (hasMin || hasMax) {
            evaluatedResults.add(matchAmount(root, ctx.paidYuan));
        }

        // 3. 菜品/分类维度 (goodsMatch)
        JsonNode goodsNode = root.path("goodsMatch");
        if (goodsNode.isObject() && goodsNode.size() > 0) {
            evaluatedResults.add(matchGoods(goodsNode, ctx.goodsItems));
        }

        // 4. 时段控制维度 (timeRange)
        JsonNode timeNode = root.path("timeRange");
        if (timeNode.isObject() && timeNode.has("startTime") && timeNode.has("endTime")) {
            evaluatedResults.add(matchTimeRange(timeNode, ctx.orderTime));
        }

        if (evaluatedResults.isEmpty()) {
            return true;
        }

        if (isOr) {
            for (boolean r : evaluatedResults) {
                if (r) return true;
            }
            return false;
        } else {
            for (boolean r : evaluatedResults) {
                if (!r) return false;
            }
            return true;
        }
    }

    private boolean matchDiningTypes(JsonNode arrayNode, String actualDiningType) {
        if (!StringUtils.hasText(actualDiningType)) {
            return false;
        }
        String actual = actualDiningType.trim();
        for (JsonNode elem : arrayNode) {
            String expected = elem.asText("").trim();
            if (expected.equals(actual)) {
                return true;
            }
            // 兼容性归一: 打包与自提在部分前端混用时的互认
            if (("打包".equals(expected) || "自提".equals(expected))
                    && ("打包".equals(actual) || "自提".equals(actual))) {
                return true;
            }
        }
        return false;
    }

    private boolean matchAmount(JsonNode root, double paidYuan) {
        BigDecimal actual = BigDecimal.valueOf(paidYuan);
        if (root.has("minPaidYuan") && root.path("minPaidYuan").isNumber()) {
            BigDecimal min = root.path("minPaidYuan").decimalValue();
            if (actual.compareTo(min) < 0) {
                return false;
            }
        }
        if (root.has("maxPaidYuan") && root.path("maxPaidYuan").isNumber()) {
            BigDecimal max = root.path("maxPaidYuan").decimalValue();
            if (actual.compareTo(max) > 0) {
                return false;
            }
        }
        return true;
    }

    private boolean matchGoods(JsonNode goodsNode, List<PaymentRoutingContext.RoutingGoodsItem> goodsItems) {
        if (goodsItems == null || goodsItems.isEmpty()) {
            return false;
        }

        Set<Long> targetGoodsIds = new HashSet<>();
        if (goodsNode.path("goodsIds").isArray()) {
            for (JsonNode n : goodsNode.path("goodsIds")) {
                if (n.canConvertToLong()) targetGoodsIds.add(n.asLong());
            }
        }

        Set<Long> targetCategoryIds = new HashSet<>();
        if (goodsNode.path("categoryIds").isArray()) {
            for (JsonNode n : goodsNode.path("categoryIds")) {
                if (n.canConvertToLong()) targetCategoryIds.add(n.asLong());
            }
        }

        List<String> keywords = new ArrayList<>();
        if (goodsNode.path("goodsNameKeywords").isArray()) {
            for (JsonNode n : goodsNode.path("goodsNameKeywords")) {
                String kw = n.asText("").trim().toLowerCase();
                if (!kw.isEmpty()) keywords.add(kw);
            }
        }

        String mode = goodsNode.path("mode").asText("CONTAINS_ANY").trim().toUpperCase();

        if ("ONLY".equals(mode)) {
            // 订单中的每一个菜品都必须满足指定规则
            for (PaymentRoutingContext.RoutingGoodsItem item : goodsItems) {
                if (!itemMatches(item, targetGoodsIds, targetCategoryIds, keywords)) {
                    return false;
                }
            }
            return true;
        } else if ("CONTAINS_ALL".equals(mode)) {
            // 所有指定的菜品ID必须全部出现在订单中
            if (!targetGoodsIds.isEmpty()) {
                Set<Long> orderGoodsIds = new HashSet<>();
                for (PaymentRoutingContext.RoutingGoodsItem item : goodsItems) {
                    if (item.goodsId != null) orderGoodsIds.add(item.goodsId);
                }
                if (!orderGoodsIds.containsAll(targetGoodsIds)) {
                    return false;
                }
            }
            return true;
        } else {
            // 默认 CONTAINS_ANY: 订单中只要有任意一个菜品满足即可
            for (PaymentRoutingContext.RoutingGoodsItem item : goodsItems) {
                if (itemMatches(item, targetGoodsIds, targetCategoryIds, keywords)) {
                    return true;
                }
            }
            return false;
        }
    }

    private boolean itemMatches(PaymentRoutingContext.RoutingGoodsItem item,
                                Set<Long> goodsIds, Set<Long> categoryIds, List<String> keywords) {
        if (item.goodsId != null && goodsIds.contains(item.goodsId)) {
            return true;
        }
        if (item.categoryId != null && categoryIds.contains(item.categoryId)) {
            return true;
        }
        if (StringUtils.hasText(item.goodsName)) {
            String name = item.goodsName.toLowerCase();
            for (String kw : keywords) {
                if (name.contains(kw)) {
                    return true;
                }
            }
        }
        return false;
    }

    private boolean matchTimeRange(JsonNode timeNode, Date orderTime) {
        String startStr = timeNode.path("startTime").asText("").trim();
        String endStr = timeNode.path("endTime").asText("").trim();
        if (!StringUtils.hasText(startStr) || !StringUtils.hasText(endStr)) {
            return true;
        }
        try {
            LocalTime start = LocalTime.parse(startStr);
            LocalTime end = LocalTime.parse(endStr);
            Instant instant = orderTime != null ? orderTime.toInstant() : Instant.now();
            LocalTime actualTime = instant.atZone(DEFAULT_ZONE).toLocalTime();
            return isLocalTimeInWindow(actualTime, start, end);
        } catch (DateTimeParseException e) {
            log.warn("路由时段格式不合法: start={}, end={}", startStr, endStr);
            return true;
        }
    }

    public static boolean isLocalTimeInWindow(LocalTime t, LocalTime start, LocalTime end) {
        if (start.equals(end)) {
            return true;
        }
        if (start.isBefore(end)) {
            return !t.isBefore(start) && t.isBefore(end);
        } else {
            return !t.isBefore(start) || t.isBefore(end);
        }
    }

    public void validateConditionsJson(String conditionsJson) {
        if (!StringUtils.hasText(conditionsJson)) {
            return;
        }
        try {
            JsonNode root = objectMapper.readTree(conditionsJson);
            if (!root.isObject()) {
                throw new IllegalArgumentException("conditionsJson 必须为有效的 JSON 对象");
            }
            if (root.has("diningTypes") && !root.path("diningTypes").isArray()) {
                throw new IllegalArgumentException("conditionsJson.diningTypes 必须为数组");
            }
            if (root.has("minPaidYuan") && !root.path("minPaidYuan").isNumber()) {
                throw new IllegalArgumentException("conditionsJson.minPaidYuan 必须为数字");
            }
            if (root.has("maxPaidYuan") && !root.path("maxPaidYuan").isNumber()) {
                throw new IllegalArgumentException("conditionsJson.maxPaidYuan 必须为数字");
            }
            if (root.has("goodsMatch") && !root.path("goodsMatch").isObject()) {
                throw new IllegalArgumentException("conditionsJson.goodsMatch 必须为对象");
            }
            if (root.has("timeRange") && !root.path("timeRange").isObject()) {
                throw new IllegalArgumentException("conditionsJson.timeRange 必须为对象");
            }
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("conditionsJson 格式无效: " + e.getMessage());
        }
    }
}
