package com.lanf.payment.support;

import com.lanf.entity.R;
import com.lanf.payment.config.PaymentConfigCache;
import com.lanf.payment.entity.PaymentMerchantConfigEntity;
import com.lanf.util.AdminShopRequest;
import com.lanf.security.AdminShopScopeGuard;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import javax.servlet.http.HttpServletRequest;

/**
 * 支付模块 B 端门店隔离：与 {@link AdminShopRequest} / 连锁 X-Shop-Id 一致。
 * <ul>
 *   <li>门店上下文（{@code X-Shop-Id} 已解析）：仅读写该 {@code shop_id}，不可改全店模板 {@code 0}</li>
 *   <li>总部无门店上下文：可通过 query/header 指定 {@code shopId}，缺省 {@code 0} 为全店默认模板</li>
 * </ul>
 */
@Component
public class PaymentAdminShopScope {

    public static final int GLOBAL_SHOP_ID = PaymentConfigCache.GLOBAL_SHOP_ID;

    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private AdminShopScopeGuard adminShopScopeGuard;

    /**
     * @return 非 null 表示失败；成功时 {@code targetShopId[0]} 为目标门店
     */
    public R resolveTargetShopId(Integer shopIdParam, int[] targetShopId) {
        Integer normalized = shopIdParam == null ? null : PaymentConfigCache.normalizeShopId(shopIdParam);
        return adminShopScopeGuard.resolveTargetShopId(normalized, targetShopId);
    }

    /** 写操作前：门店账号不可写 {@code shop_id=0}，且只能写本店 */
    public R assertWritableShopId(int targetShopId) {
        Integer ctx = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (targetShopId == GLOBAL_SHOP_ID) {
            return adminShopScopeGuard.requireHeadquarters();
        }
        if (ctx == null) {
            return R.error(4003, "缺少已授权的门店上下文");
        }
        if (!ctx.equals(targetShopId)) {
            return R.error(4003, "不能修改其他门店的支付配置");
        }
        return null;
    }

    public R assertMerchantReadable(PaymentMerchantConfigEntity row) {
        if (row == null) {
            return R.error("商户配置不存在");
        }
        Integer ctx = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (ctx == null) {
            return null;
        }
        Integer rowShop = row.getShop_id() != null ? row.getShop_id() : GLOBAL_SHOP_ID;
        if (rowShop == GLOBAL_SHOP_ID || ctx.equals(rowShop)) {
            return null;
        }
        return R.error(4003, "商户配置不属于当前门店");
    }

    public R assertMerchantWritable(PaymentMerchantConfigEntity row) {
        R read = assertMerchantReadable(row);
        if (read != null) {
            return read;
        }
        Integer ctx = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (ctx == null) {
            return null;
        }
        Integer rowShop = row.getShop_id() != null ? row.getShop_id() : GLOBAL_SHOP_ID;
        if (rowShop == GLOBAL_SHOP_ID) {
            return R.error(4003, "门店账号不能修改全店默认商户配置");
        }
        return null;
    }

    public static boolean isGlobalShop(int shopId) {
        return shopId == GLOBAL_SHOP_ID;
    }

    public static String scopeLabel(int shopId) {
        return shopId == GLOBAL_SHOP_ID ? "global" : "shop";
    }
}
