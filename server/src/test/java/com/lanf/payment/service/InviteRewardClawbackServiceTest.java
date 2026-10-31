package com.lanf.payment.service;

import com.lanf.service.IUserService;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class InviteRewardClawbackServiceTest {

    @SuppressWarnings("unchecked")
    @Test
    void successfulClawbackClearsOutstandingAmount() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        TransactionTemplate transactions = mock(TransactionTemplate.class);
        IUserService users = mock(IUserService.class);
        InviteRewardClawbackService service =
                new InviteRewardClawbackService(jdbc, transactions, users);
        Map<String, Object> row = new HashMap<>();
        row.put("inviter_user_id", 7);
        row.put("outstanding_amount", new BigDecimal("2.00"));
        row.put("status", "PENDING");
        when(jdbc.queryForList(any(String.class), eq(1L)))
                .thenReturn(Collections.singletonList(row));
        when(users.subtractGiftBalanceIfEnough(7, new BigDecimal("2.00")))
                .thenReturn(true);
        doAnswer(invocation -> {
            Consumer<TransactionStatus> callback = invocation.getArgument(0);
            callback.accept(mock(TransactionStatus.class));
            return null;
        }).when(transactions).executeWithoutResult(any());

        ReflectionTestUtils.invokeMethod(service, "processOne", 1L);

        verify(jdbc).update(contains("outstanding_amount = 0"), eq(1L));
    }
}
