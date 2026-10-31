package com.lanf.util;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.interceptor.SysInterceptor;

import javax.servlet.http.HttpServletRequest;
import java.util.Locale;
import java.util.Set;

/**
 * 运营端订单查询的门店范围：与会员画像、一键发券消费筛选等共用。
 * <ul>
 *   <li>{@code resolved} / {@code current}：仅请求头当前门店（X-Shop-Id）</li>
 *   <li>{@code accessible}（默认）：若存在已解析门店上下文（X-Shop-Id）则限定当前店；门店账号限制在可访问门店 {@code IN (...)}；总部账号且无门店头时不写 shop 条件（全连锁）</li>
 *   <li>{@code all} / {@code global}：忽略门店上下文，全平台范围查询</li>
 * </ul>
 */
public final class AdminOrderShopScope {

    private AdminOrderShopScope() {
    }

    public static void apply(QueryWrapper<Order> q, HttpServletRequest req, String orderShopScope) {
        apply(q, req, orderShopScope, null);
    }

    public static void apply(QueryWrapper<Order> q, HttpServletRequest req, String orderShopScope, Integer explicitShopId) {
        String scope = orderShopScope != null ? orderShopScope.trim().toLowerCase(Locale.ROOT) : "accessible";
        if ("all".equals(scope) || "allshops".equals(scope) || "global".equals(scope)) {
            return;
        }
        if (explicitShopId != null && explicitShopId > 0) {
            if (explicitShopId == 1) {
                q.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
            } else {
                q.eq("shop_id", explicitShopId);
            }
            return;
        }
        if ("resolved".equals(scope) || "current".equals(scope)) {
            Integer sid = AdminShopRequest.getResolvedShopId(req);
            if (sid != null && sid > 0) {
                if (sid == 1) {
                    q.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
                } else {
                    q.eq("shop_id", sid);
                }
            }
            return;
        }
        Integer sid = AdminShopRequest.getResolvedShopId(req);
        if (sid != null && sid > 0) {
            if (sid == 1) {
                q.and(w -> w.eq("shop_id", 1).or().isNull("shop_id"));
            } else {
                q.eq("shop_id", sid);
            }
            return;
        }
        Object allowedObj = req.getAttribute(SysInterceptor.ATTR_ALLOWED_SHOP_IDS);
        if (allowedObj instanceof Set) {
            @SuppressWarnings("unchecked")
            Set<Integer> allowed = (Set<Integer>) allowedObj;
            if (allowed != null && !allowed.isEmpty()) {
                q.in("shop_id", allowed);
            }
        }
    }
}
