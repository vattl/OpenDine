package com.lanf.config.properties;

import org.junit.jupiter.api.Test;

import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UserIdentityCompatibilityPropertiesTest {

    @Test
    void defaultConfigurationIsEffectiveUntilYearEnd2026() {
        UserIdentityCompatibilityProperties props = new UserIdentityCompatibilityProperties();
        assertTrue(props.isCompatibilityEnabled());
        assertTrue(props.getCompatibilityDeadline().startsWith("2026-12-31"));
        assertTrue(props.isEffective());
    }

    @Test
    void disabledCompatibilityIsNotEffective() {
        UserIdentityCompatibilityProperties props = new UserIdentityCompatibilityProperties();
        props.setCompatibilityEnabled(false);
        assertFalse(props.isEffective());
    }

    @Test
    void expiredDeadlineIsNotEffective() {
        UserIdentityCompatibilityProperties props = new UserIdentityCompatibilityProperties();
        props.setCompatibilityDeadline("2020-01-01T00:00:00+08:00");
        assertFalse(props.isEffective());
    }

    @Test
    void futureDeadlineIsEffective() {
        UserIdentityCompatibilityProperties props = new UserIdentityCompatibilityProperties();
        String future = ZonedDateTime.now().plusDays(10).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        props.setCompatibilityDeadline(future);
        assertTrue(props.isEffective());
    }
}
