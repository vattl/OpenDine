package com.lanf.payment.service;

import org.junit.jupiter.api.Test;

import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PaymentNinefoldServiceTest {

    @Test
    void resolvedQualifiesRequiresEnabled() {
        PaymentNinefoldService.ResolvedNinefold r = new PaymentNinefoldService.ResolvedNinefold();
        r.enabled = false;
        r.payRate = 0.9;
        r.minBaseYuan = 60d;
        r.windowStart = java.time.LocalTime.MIDNIGHT;
        r.windowEnd = java.time.LocalTime.of(23, 59, 59);
        r.zone = java.time.ZoneId.of("Asia/Shanghai");
        r.eligibleDiningTypes = Collections.singletonList("堂食");

        assertFalse(r.qualifiesForNineFold(false, new Date(), 100d, "堂食"));

        r.enabled = true;
        assertTrue(r.qualifiesForNineFold(false, new Date(), 100d, "堂食"));
        assertFalse(r.qualifiesForNineFold(false, new Date(), 100d, "外卖"));
    }
}
