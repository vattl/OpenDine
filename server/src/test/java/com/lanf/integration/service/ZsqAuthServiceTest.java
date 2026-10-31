package com.lanf.integration.service;

import com.lanf.integration.config.ZsqProperties;
import com.lanf.integration.exception.ZsqApiException;
import com.lanf.integration.remote.ZsqRemoteClient;
import com.lanf.integration.remote.dto.ZsqLoginTokenData;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ZsqAuthServiceTest {

    @Test
    void concurrentExpiredTokenCallersShareOneRefresh() throws Exception {
        ZsqRemoteClient remote = mock(ZsqRemoteClient.class);
        when(remote.merchantLogin(any())).thenReturn(token("old"), token("new"));
        ZsqProperties properties = configuredProperties();
        ZsqAuthService auth = new ZsqAuthService(remote, properties);
        assertEquals("Bearer old", auth.getConfigAuthorization());

        CyclicBarrier bothOldRequests = new CyclicBarrier(2);
        Callable<String> call = () -> auth.executeWithConfigAuth(value -> {
            if ("Bearer old".equals(value)) {
                await(bothOldRequests);
                throw new ZsqApiException(401, "token expired", null);
            }
            return value;
        });
        ExecutorService workers = Executors.newFixedThreadPool(2);
        try {
            List<Future<String>> results = workers.invokeAll(Arrays.asList(call, call));
            assertEquals("Bearer new", results.get(0).get());
            assertEquals("Bearer new", results.get(1).get());
        } finally {
            workers.shutdownNow();
        }
        verify(remote, times(2)).merchantLogin(any()); // initial login plus exactly one shared refresh
    }

    private static ZsqProperties configuredProperties() {
        ZsqProperties properties = new ZsqProperties();
        properties.setUsername("merchant");
        properties.setPassword("password");
        return properties;
    }

    private static ZsqLoginTokenData token(String value) {
        ZsqLoginTokenData data = new ZsqLoginTokenData();
        data.setTokenHead("Bearer ");
        data.setToken(value);
        return data;
    }

    private static void await(CyclicBarrier barrier) {
        try {
            barrier.await();
        } catch (Exception e) {
            throw new AssertionError("concurrent test synchronization failed", e);
        }
    }
}
