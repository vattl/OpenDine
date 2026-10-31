package com.lanf.kds;

import com.lanf.kds.service.KdsDeviceService;
import com.lanf.kds.entity.KdsDevice;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.util.*;

class KdsWorkflowDurabilityTest {
    @Test void workflowSelectionSurvivesServiceRecreation() {
        KdsDeviceService first = new KdsDeviceService();
        KdsDeviceService second = new KdsDeviceService();
        org.springframework.jdbc.datasource.DriverManagerDataSource ds = new org.springframework.jdbc.datasource.DriverManagerDataSource(
                "jdbc:h2:mem:workflow-durable;MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        org.springframework.jdbc.core.JdbcTemplate jdbc = new org.springframework.jdbc.core.JdbcTemplate(ds);
        jdbc.execute("CREATE TABLE IF NOT EXISTS t_kds_device_workflow(device_id BIGINT PRIMARY KEY,workflows VARCHAR(64))");
        org.springframework.test.util.ReflectionTestUtils.setField(first,"workflowStore",new com.lanf.kds.service.KdsWorkflowStore(jdbc));
        org.springframework.test.util.ReflectionTestUtils.setField(second,"workflowStore",new com.lanf.kds.service.KdsWorkflowStore(jdbc));
        first.saveWorkflowSelection(5L, Collections.singletonList("serve"));
        KdsDevice device = new KdsDevice();
        device.setId(5L); device.setScreen_tag("meat_grill");
        assertEquals(Collections.singletonList("serve"),second.enrichWorkflows(device).getWorkflows());
        second.saveWorkflowSelection(5L,Collections.singletonList("cook"));
        assertEquals(Collections.singletonList("cook"),first.enrichWorkflows(device).getWorkflows());
    }
}
