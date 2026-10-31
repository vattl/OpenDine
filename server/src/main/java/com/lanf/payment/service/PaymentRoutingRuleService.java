package com.lanf.payment.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.payment.PaymentChannels;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.payment.entity.PaymentRoutingRuleEntity;
import com.lanf.payment.mapper.PaymentRoutingRuleMapper;
import com.lanf.payment.routing.PaymentRoutingContext;
import com.lanf.payment.routing.PaymentRoutingRuleMatcher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class PaymentRoutingRuleService {

    private static final Logger log = LoggerFactory.getLogger(PaymentRoutingRuleService.class);

    @Autowired
    private PaymentRoutingRuleMapper ruleMapper;
    @Autowired
    private PaymentMerchantConfigService merchantConfigService;
    @Autowired
    private PaymentMerchantPolicyService merchantPolicyService;
    @Autowired
    private PaymentRoutingRuleMatcher ruleMatcher;
    @Autowired
    private ObjectMapper objectMapper;

    public List<PaymentRoutingRuleEntity> listRuntimeRules(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String ch = StringUtils.hasText(channel) ? channel.trim().toLowerCase() : PaymentChannels.WECHAT;
        List<PaymentRoutingRuleEntity> rows = listFromDb(sid, ch).stream()
                .filter(r -> r.getEnabled() != null && r.getEnabled() == 1)
                .collect(Collectors.toList());
        if (rows.isEmpty() && sid > 0 && merchantPolicyService != null && merchantPolicyService.allowsGlobalFallback(sid)) {
            rows = listFromDb(PaymentConfigCache.GLOBAL_SHOP_ID, ch).stream()
                    .filter(r -> r.getEnabled() != null && r.getEnabled() == 1)
                    .collect(Collectors.toList());
        }
        return rows;
    }

    public List<PaymentRoutingRuleEntity> listFromDb(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        QueryWrapper<PaymentRoutingRuleEntity> qw = new QueryWrapper<PaymentRoutingRuleEntity>()
                .eq("shop_id", sid);
        if (StringUtils.hasText(channel)) {
            qw.eq("channel", channel.trim().toLowerCase());
        }
        qw.orderByDesc("priority").orderByAsc("id");
        return ruleMapper.selectList(qw);
    }

    public Map<String, Object> listForAdmin(int shopId, String channel) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String ch = StringUtils.hasText(channel) ? channel.trim().toLowerCase() : PaymentChannels.WECHAT;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("targetShopId", sid);
        out.put("scope", sid == PaymentConfigCache.GLOBAL_SHOP_ID ? "global" : "shop");
        out.put("channel", ch);

        List<PaymentRoutingRuleEntity> ownedRows = listFromDb(sid, ch);
        out.put("rules", ownedRows.stream().map(this::toRuleMap).collect(Collectors.toList()));

        if (sid != PaymentConfigCache.GLOBAL_SHOP_ID) {
            List<PaymentRoutingRuleEntity> globalRows = listFromDb(PaymentConfigCache.GLOBAL_SHOP_ID, ch);
            out.put("inheritedTemplates", globalRows.stream().map(r -> {
                Map<String, Object> m = toRuleMap(r);
                m.put("inherited", true);
                m.put("readOnly", true);
                return m;
            }).collect(Collectors.toList()));
        } else {
            out.put("inheritedTemplates", Collections.emptyList());
        }
        return out;
    }

    public PaymentRoutingRuleEntity getById(Long id) {
        return id == null ? null : ruleMapper.selectById(id);
    }

    @Transactional(rollbackFor = Exception.class)
    public PaymentRoutingRuleEntity create(int shopId, Map<String, Object> body) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        PaymentRoutingRuleEntity entity = new PaymentRoutingRuleEntity();
        entity.setShop_id(sid);
        applyBody(entity, body, true);
        Date now = new Date();
        entity.setCreated_at(now);
        entity.setUpdated_at(now);
        ruleMapper.insert(entity);
        return entity;
    }

    @Transactional(rollbackFor = Exception.class)
    public PaymentRoutingRuleEntity update(Long id, int shopId, Map<String, Object> body) {
        PaymentRoutingRuleEntity entity = getById(id);
        if (entity == null) {
            throw new IllegalArgumentException("路由规则不存在: id=" + id);
        }
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        if (entity.getShop_id() != null && !entity.getShop_id().equals(sid)) {
            throw new IllegalArgumentException("无权修改其他门店的路由规则");
        }
        applyBody(entity, body, false);
        entity.setUpdated_at(new Date());
        ruleMapper.updateById(entity);
        return entity;
    }

    @Transactional(rollbackFor = Exception.class)
    public boolean delete(Long id, int shopId) {
        PaymentRoutingRuleEntity entity = getById(id);
        if (entity == null) {
            return false;
        }
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        if (entity.getShop_id() != null && !entity.getShop_id().equals(sid)) {
            throw new IllegalArgumentException("无权删除其他门店的路由规则");
        }
        return ruleMapper.deleteById(id) > 0;
    }

    @Transactional(rollbackFor = Exception.class)
    public void sort(int shopId, String channel, List<Long> ruleIds) {
        if (ruleIds == null || ruleIds.isEmpty()) return;
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        int total = ruleIds.size();
        for (int i = 0; i < total; i++) {
            Long id = ruleIds.get(i);
            PaymentRoutingRuleEntity e = getById(id);
            if (e != null && Objects.equals(e.getShop_id(), sid)) {
                e.setPriority((total - i) * 10);
                e.setUpdated_at(new Date());
                ruleMapper.updateById(e);
            }
        }
    }

    public Map<String, Object> simulate(int shopId, Map<String, Object> body) {
        int sid = PaymentConfigCache.normalizeShopId(shopId);
        String channel = body.get("channel") != null ? body.get("channel").toString() : PaymentChannels.WECHAT;
        double paidYuan = body.get("paidYuan") instanceof Number ? ((Number) body.get("paidYuan")).doubleValue() : 0.0;
        String diningType = body.get("diningType") != null ? body.get("diningType").toString() : "";

        PaymentRoutingContext ctx = new PaymentRoutingContext(sid, paidYuan, diningType, null);

        if (body.get("goodsItems") instanceof List) {
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> rawGoods = (List<Map<String, Object>>) body.get("goodsItems");
            for (Map<String, Object> g : rawGoods) {
                Long goodsId = g.get("goodsId") instanceof Number ? ((Number) g.get("goodsId")).longValue() : null;
                String goodsName = g.get("goodsName") != null ? g.get("goodsName").toString() : "";
                Long catId = g.get("categoryId") instanceof Number ? ((Number) g.get("categoryId")).longValue() : null;
                BigDecimal price = g.get("price") instanceof Number ? BigDecimal.valueOf(((Number) g.get("price")).doubleValue()) : BigDecimal.ZERO;
                Integer qty = g.get("quantity") instanceof Number ? ((Number) g.get("quantity")).intValue() : 1;
                ctx.goodsItems.add(new PaymentRoutingContext.RoutingGoodsItem(goodsId, goodsName, catId, price, qty));
            }
        }

        List<PaymentRoutingRuleEntity> rules = listRuntimeRules(sid, channel);
        PaymentRoutingRuleEntity matchedRule = null;
        for (PaymentRoutingRuleEntity r : rules) {
            if (ruleMatcher.isMatch(r.getConditions_json(), r.getMatch_mode(), ctx)) {
                matchedRule = r;
                break;
            }
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("shopId", sid);
        out.put("channel", channel);
        out.put("inputPaidYuan", paidYuan);
        out.put("inputDiningType", diningType);
        out.put("inputGoodsCount", ctx.goodsItems.size());
        if (matchedRule != null) {
            out.put("matched", true);
            out.put("matchedRuleId", matchedRule.getId());
            out.put("matchedRuleName", matchedRule.getRule_name());
            out.put("targetMerchantKey", matchedRule.getTarget_merchant_key());
            boolean ready = merchantConfigService.isMerchantPayReady(sid, channel, matchedRule.getTarget_merchant_key());
            out.put("targetMerchantPayReady", ready);
            out.put("effectiveMerchantKey", ready ? matchedRule.getTarget_merchant_key() : "default");
            out.put("fallbackOccurred", !ready);
        } else {
            out.put("matched", false);
            out.put("effectiveMerchantKey", "default");
            out.put("targetMerchantPayReady", merchantConfigService.isMerchantPayReady(sid, channel, "default"));
            out.put("reason", "未命中任何启用的分流规则，走默认主商户");
        }
        return out;
    }

    private void applyBody(PaymentRoutingRuleEntity entity, Map<String, Object> body, boolean isCreate) {
        String ruleName = body.get("ruleName") != null ? body.get("ruleName").toString().trim()
                : body.get("rule_name") != null ? body.get("rule_name").toString().trim() : null;
        if (isCreate || ruleName != null) {
            if (!StringUtils.hasText(ruleName)) {
                throw new IllegalArgumentException("ruleName 不能为空");
            }
            if (ruleName.length() > 64) {
                throw new IllegalArgumentException("ruleName 长度不能超过 64 个字符");
            }
            entity.setRule_name(ruleName);
        }

        String channel = body.get("channel") != null ? body.get("channel").toString().trim().toLowerCase() : null;
        if (isCreate || channel != null) {
            entity.setChannel(StringUtils.hasText(channel) ? channel : PaymentChannels.WECHAT);
        }

        String targetKey = body.get("targetMerchantKey") != null ? body.get("targetMerchantKey").toString().trim()
                : body.get("target_merchant_key") != null ? body.get("target_merchant_key").toString().trim() : null;
        if (isCreate || targetKey != null) {
            if (!StringUtils.hasText(targetKey)) {
                throw new IllegalArgumentException("targetMerchantKey 不能为空");
            }
            entity.setTarget_merchant_key(targetKey);
        }

        String matchMode = body.get("matchMode") != null ? body.get("matchMode").toString().trim().toUpperCase()
                : body.get("match_mode") != null ? body.get("match_mode").toString().trim().toUpperCase() : null;
        if (isCreate || matchMode != null) {
            entity.setMatch_mode("ANY".equals(matchMode) ? "ANY" : "ALL");
        }

        Object condObj = body.get("conditionsJson") != null ? body.get("conditionsJson") : body.get("conditions_json");
        if (condObj == null) {
            condObj = body.get("conditions");
        }
        if (isCreate || condObj != null) {
            String condStr = "";
            if (condObj instanceof Map) {
                try {
                    condStr = objectMapper.writeValueAsString(condObj);
                } catch (Exception e) {
                    throw new IllegalArgumentException("conditions 序列化失败: " + e.getMessage());
                }
            } else if (condObj != null) {
                condStr = condObj.toString().trim();
            }
            ruleMatcher.validateConditionsJson(condStr);
            entity.setConditions_json(condStr);
        }

        Object priorityObj = body.get("priority");
        if (priorityObj instanceof Number) {
            entity.setPriority(((Number) priorityObj).intValue());
        } else if (isCreate && entity.getPriority() == null) {
            entity.setPriority(100);
        }

        Object enabledObj = body.get("enabled");
        if (enabledObj instanceof Boolean) {
            entity.setEnabled((Boolean) enabledObj ? 1 : 0);
        } else if (enabledObj instanceof Number) {
            entity.setEnabled(((Number) enabledObj).intValue() != 0 ? 1 : 0);
        } else if (isCreate && entity.getEnabled() == null) {
            entity.setEnabled(1);
        }

        String remark = body.get("remark") != null ? body.get("remark").toString().trim() : null;
        if (remark != null) {
            entity.setRemark(remark);
        }
    }

    public Map<String, Object> toRuleMap(PaymentRoutingRuleEntity entity) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", entity.getId());
        m.put("shopId", entity.getShop_id());
        m.put("channel", entity.getChannel());
        m.put("ruleName", entity.getRule_name());
        m.put("priority", entity.getPriority());
        m.put("enabled", entity.getEnabled() != null && entity.getEnabled() == 1);
        m.put("targetMerchantKey", entity.getTarget_merchant_key());
        m.put("matchMode", entity.getMatch_mode());
        m.put("conditionsJson", entity.getConditions_json());
        m.put("remark", entity.getRemark());
        m.put("createdAt", entity.getCreated_at());
        m.put("updatedAt", entity.getUpdated_at());
        boolean ready = merchantConfigService.isMerchantPayReady(
                entity.getShop_id(), entity.getChannel(), entity.getTarget_merchant_key());
        m.put("targetMerchantPayReady", ready);
        return m;
    }
}
