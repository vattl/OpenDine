package com.lanf.kds.support;

import org.springframework.util.StringUtils;

/** Client snapshot hints used to reject stale KDS advance requests. */
public class KdsAdvanceRequestContext {
    private final Integer expectedOrderId;
    private final String expectedTableNumber;
    private final String expectedDishName;

    public KdsAdvanceRequestContext(Integer expectedOrderId, String expectedTableNumber, String expectedDishName) {
        this.expectedOrderId = expectedOrderId;
        this.expectedTableNumber = normalize(expectedTableNumber);
        this.expectedDishName = normalize(expectedDishName);
    }

    public Integer getExpectedOrderId() { return expectedOrderId; }
    public String getExpectedTableNumber() { return expectedTableNumber; }
    public String getExpectedDishName() { return expectedDishName; }

    public boolean hasAnyExpectation() {
        return expectedOrderId != null || StringUtils.hasText(expectedTableNumber) || StringUtils.hasText(expectedDishName);
    }

    private static String normalize(String value) {
        return StringUtils.hasText(value) ? value.trim() : null;
    }
}
