package com.lanf.payment.service;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;

class CollectionMatchingSafetyTest {
    private Map<String,Object> row(int shop, long id) {
        Map<String,Object> r = new HashMap<>();
        r.put("id", id); r.put("shop_id", shop); r.put("order_no", "O" + id);
        r.put("session_id", "S" + id); r.put("created_at", new Date());
        return r;
    }
    @Test void missingShopNeverQueriesOrConfirms() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        assertNull(new CashierCollectionIntentService(jdbc).matchAndConfirmByWebhook(null,"wechat",100,new Date()));
        verifyNoInteractions(jdbc);
    }
    @Test void multipleCandidatesNeverChooseOne() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForList(anyString(), anyInt(), anyString(), anyInt(), any(Date.class), any(Date.class)))
                .thenReturn(Arrays.asList(row(1,1),row(1,2)));
        assertThrows(CashierCollectionIntentService.AmbiguousCollectionException.class,
                () -> new CashierCollectionIntentService(jdbc).matchAndConfirmByWebhook(1,"wechat",100,new Date()));
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }
    @Test void queryBindsShopAndArrivalTimeAndChecksTwoCandidates() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        Date arrival = new Date(1700000000000L);
        new CashierCollectionIntentService(jdbc).matchAndConfirmByWebhook(7,"wechat",100,arrival);
        verify(jdbc).queryForList(argThat(s -> s.contains("shop_id = ?") && s.contains("LIMIT 2") && !s.contains("NOW()")),
                eq(7), eq("wechat"), eq(100), any(Date.class), any(Date.class));
    }
}
