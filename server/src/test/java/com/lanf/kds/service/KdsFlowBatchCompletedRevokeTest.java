package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.lanf.kds.KdsFlowBatchStatus;
import com.lanf.kds.entity.KdsFlowBatch;
import com.lanf.kds.mapper.KdsFlowBatchMapper;
import com.lanf.kds.mapper.KdsTicketMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;
import java.util.Date;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class KdsFlowBatchCompletedRevokeTest {

    private KdsFlowBatchService service;
    private KdsFlowBatchMapper batchMapper;

    @BeforeEach
    void setUp() {
        service = new KdsFlowBatchService();
        batchMapper = mock(KdsFlowBatchMapper.class);
        ReflectionTestUtils.setField(service, "batchMapper", batchMapper);
        ReflectionTestUtils.setField(service, "ticketMapper", mock(KdsTicketMapper.class));
    }

    @Test
    void revokeServeMovesMostRecentCompletedQuantityBackAndClearsServedTime() {
        KdsFlowBatch completed = new KdsFlowBatch();
        completed.setId(81L);
        completed.setShop_id(7);
        completed.setTicket_id(91L);
        completed.setDetail_id(501);
        completed.setOrder_id(1001);
        completed.setQuantity(2);
        completed.setQueue_status(KdsFlowBatchStatus.DONE);
        completed.setServed_at(new Date(1_000L));
        when(batchMapper.selectList(any(Wrapper.class)))
                .thenReturn(Collections.singletonList(completed));

        int moved = service.revokeServe(7, 91L, 1);

        assertEquals(1, moved);
        assertEquals(1, completed.getQuantity());
        ArgumentCaptor<KdsFlowBatch> inserted = ArgumentCaptor.forClass(KdsFlowBatch.class);
        verify(batchMapper).insert(inserted.capture());
        assertEquals(KdsFlowBatchStatus.READY_SERVE, inserted.getValue().getQueue_status());
        assertEquals(1, inserted.getValue().getQuantity());
        assertNull(inserted.getValue().getServed_at());
    }
}
