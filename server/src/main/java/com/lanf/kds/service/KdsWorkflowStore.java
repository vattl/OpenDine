package com.lanf.kds.service;

import com.lanf.kds.KdsWorkflow;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import java.util.*;

@Repository
@org.springframework.context.annotation.DependsOn("paymentSchemaReadiness")
public class KdsWorkflowStore {
    private final JdbcTemplate jdbc;
    public KdsWorkflowStore(JdbcTemplate jdbc) { this.jdbc=jdbc; }
    public List<String> get(long deviceId) {
        List<String> rows = jdbc.queryForList("SELECT workflows FROM t_kds_device_workflow WHERE device_id=?",String.class,deviceId);
        return rows.isEmpty() ? Collections.emptyList() : KdsWorkflow.normalizeList(Arrays.asList(rows.get(0).split(",")));
    }
    public void save(long deviceId,List<String> workflows) {
        List<String> normalized=KdsWorkflow.normalizeList(workflows);
        if (normalized.isEmpty()) { delete(deviceId); return; }
        jdbc.update("INSERT INTO t_kds_device_workflow(device_id,workflows) VALUES (?,?) "
                + "ON DUPLICATE KEY UPDATE workflows=VALUES(workflows)",deviceId,String.join(",",normalized));
    }
    public void delete(long deviceId) { jdbc.update("DELETE FROM t_kds_device_workflow WHERE device_id=?",deviceId); }
}
