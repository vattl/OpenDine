package com.lanf.kds.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KdsOrderRevisionOwnershipTest {

    @Test
    void businessOwnerAlreadyAdvancesRevisionForAddDishes() {
        assertFalse(KdsWorkflowV2Service.shouldAdvanceOrderRevisionInWorkflow("pos_add_dishes"));
        assertFalse(KdsWorkflowV2Service.shouldAdvanceOrderRevisionInWorkflow("addDishes"));
    }

    @Test
    void workflowStillAdvancesRevisionForOtherKdsMutations() {
        assertTrue(KdsWorkflowV2Service.shouldAdvanceOrderRevisionInWorkflow("pos_refund_dish"));
        assertTrue(KdsWorkflowV2Service.shouldAdvanceOrderRevisionInWorkflow("refundDish"));
        assertTrue(KdsWorkflowV2Service.shouldAdvanceOrderRevisionInWorkflow("advance_item"));
    }

    @Test
    void statusAggregatorDoesNotMutateOrderRevisionDirectly() {
        KdsOrderStatusAggregator aggregator = new KdsOrderStatusAggregator();
        com.lanf.service.IOrderService orderService = org.mockito.Mockito.mock(com.lanf.service.IOrderService.class);
        com.lanf.kds.mapper.KdsOrderMapper kdsOrderMapper = org.mockito.Mockito.mock(com.lanf.kds.mapper.KdsOrderMapper.class);
        org.springframework.test.util.ReflectionTestUtils.setField(aggregator, "orderService", orderService);
        org.springframework.test.util.ReflectionTestUtils.setField(aggregator, "kdsOrderMapper", kdsOrderMapper);

        com.lanf.kds.entity.KdsOrder kdsOrder = new com.lanf.kds.entity.KdsOrder();
        kdsOrder.setRevision(1);
        org.mockito.Mockito.when(kdsOrderMapper.selectById(101)).thenReturn(kdsOrder);

        org.springframework.test.util.ReflectionTestUtils.invokeMethod(
                aggregator, "upsert", 101, 1, "ORD-1", 20);

        org.mockito.Mockito.verify(kdsOrderMapper).updateById(kdsOrder);
        org.junit.jupiter.api.Assertions.assertEquals(2, kdsOrder.getRevision());
        org.mockito.Mockito.verifyNoInteractions(orderService);
    }
}

