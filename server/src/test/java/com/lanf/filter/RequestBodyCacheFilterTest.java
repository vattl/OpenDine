package com.lanf.filter;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.concurrent.atomic.AtomicBoolean;
import static org.junit.jupiter.api.Assertions.*;

class RequestBodyCacheFilterTest {
    @Test void rejectsOversizedJsonBeforeInvokingDownstreamEvenWithoutContentLength() throws Exception {
        RequestBodyCacheFilter filter = new RequestBodyCacheFilter();
        MockHttpServletRequest request = new MockHttpServletRequest() {
            @Override public int getContentLength() { return -1; }
            @Override public long getContentLengthLong() { return -1; }
        };
        request.setContentType("application/json");
        request.setContent(new byte[1024 * 1024 + 1]);
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicBoolean called = new AtomicBoolean();
        filter.doFilter(request, response, (req, res) -> called.set(true));
        assertEquals(413, response.getStatus());
        assertFalse(called.get());
    }
    @Test void acceptedBodyIsRepeatable() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setContentType("application/json");
        request.setContent("{}".getBytes("UTF-8"));
        new RequestBodyCacheFilter().doFilter(request, new MockHttpServletResponse(), (req, res) -> {
            assertEquals('{', req.getInputStream().read());
            assertEquals('{', req.getInputStream().read());
        });
    }
}
