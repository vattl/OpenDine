package com.lanf.config;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
class RestTemplateTimeoutTest {
    @Test void externalClientHasFiniteTimeouts() {
        Object factory = new RestTemplateConfig().restTemplate().getRequestFactory();
        assertTrue((Integer) ReflectionTestUtils.getField(factory,"connectTimeout") > 0);
        assertTrue((Integer) ReflectionTestUtils.getField(factory,"readTimeout") > 0);
    }
}
