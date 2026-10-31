package com.lanf.service;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

/** 成功会员充值汇总；本金为实际收款，赠送额仅为会员权益。 */
public final class MemberRechargeSummary {

    private final long successCount;
    private final long principalFen;
    private final long giftFen;

    public MemberRechargeSummary(long successCount, long principalFen, long giftFen) {
        this.successCount = successCount;
        this.principalFen = principalFen;
        this.giftFen = giftFen;
    }

    public static MemberRechargeSummary empty() {
        return new MemberRechargeSummary(0L, 0L, 0L);
    }

    public long getSuccessCount() {
        return successCount;
    }

    public long getPrincipalFen() {
        return principalFen;
    }

    public long getGiftFen() {
        return giftFen;
    }

    public long getCreditedTotalFen() {
        return principalFen + giftFen;
    }

    public Map<String, Object> toMap() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("success_count", successCount);
        result.put("principal_fen", principalFen);
        result.put("gift_fen", giftFen);
        result.put("credited_total_fen", getCreditedTotalFen());
        result.put("principal_amount", BigDecimal.valueOf(principalFen, 2));
        result.put("gift_amount", BigDecimal.valueOf(giftFen, 2));
        result.put("credited_total_amount", BigDecimal.valueOf(getCreditedTotalFen(), 2));
        return result;
    }
}
