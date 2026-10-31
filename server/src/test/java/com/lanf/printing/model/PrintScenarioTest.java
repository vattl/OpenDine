package com.lanf.printing.model;

import com.lanf.entity.Order;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PrintScenarioTest {

    @Test
    void canonicalizesAllBuiltInCodesAndLegacyAliases() {
        assertEquals("checkout", PrintScenario.canonicalCode("CHECKOUT"));
        assertEquals("expedite", PrintScenario.canonicalCode("serve"));
        assertEquals("kitchen", PrintScenario.canonicalCode("kitchen_ticket"));
        assertEquals("checkout", PrintScenario.canonicalCode("receipt"));
        assertEquals("label", PrintScenario.canonicalCode("LABEL"));
        assertEquals("packing", PrintScenario.canonicalCode("PACKING"));
        assertTrue(PrintScenario.isBuiltIn("checkout"));
        assertTrue(PrintScenario.isBuiltIn("packing"));
        assertFalse(PrintScenario.allowsUnconfiguredDeviceFallback("packing"));
        assertTrue(PrintScenario.allowsUnconfiguredDeviceFallback("checkout"));
        assertFalse(PrintScenario.isBuiltIn("pickup_notice"));
    }

    @Test
    void infersLegacyOrderToItsSpecificReceiptScenario() {
        Order paid = new Order();
        paid.setTransac_status("success");
        assertEquals("checkout", PrintScenario.resolveDispatchCode("order", PrintContext.ofOrder(paid, false)));
        assertEquals("full_order", PrintScenario.resolveDispatchCode("order", PrintContext.ofOrder(paid, true)));

        Order unpaid = new Order();
        unpaid.setTransac_status("pending");
        assertEquals("pre_checkout", PrintScenario.resolveDispatchCode("order", PrintContext.ofOrder(unpaid, false)));
    }

    @Test
    void preservesValidCustomCodeAndExposesLegacyRuleFallbacks() {
        assertEquals("pickup_notice", PrintScenario.canonicalCode(" PICKUP_NOTICE "));
        assertEquals("自定义场景(pickup_notice)", PrintScenario.displayName("pickup_notice"));
        assertEquals("打包单", PrintScenario.displayName("packing"));
        assertEquals(Arrays.asList("checkout", "order", "receipt", "bill"),
                PrintScenario.ruleLookupCodes("checkout"));
    }
}
