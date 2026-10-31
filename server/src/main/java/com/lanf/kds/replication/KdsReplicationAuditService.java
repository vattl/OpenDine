package com.lanf.kds.replication;

import com.lanf.interceptor.SysInterceptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import javax.servlet.http.HttpServletRequest;

@Service
public class KdsReplicationAuditService {
    private final JdbcTemplate jdbc;

    public KdsReplicationAuditService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Independent commit guarantees an attempted operator action survives business rollback. */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(int shopId, String eventId, String action, String reason,
                       String replacementEventId, HttpServletRequest request) {
        Object admin = request != null ? request.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        Integer adminId = admin instanceof Integer ? (Integer) admin : null;
        String traceId = request != null && request.getAttribute(SysInterceptor.ATTR_TRACE_ID) != null
                ? String.valueOf(request.getAttribute(SysInterceptor.ATTR_TRACE_ID)) : null;
        String subject = adminId != null ? "admin:" + adminId : "unknown";
        jdbc.update("INSERT INTO t_kds_replication_dead_letter_audit "
                        + "(shop_id,event_id,action,reason,replacement_event_id,operator_admin_id,operator_subject,trace_id) "
                        + "VALUES (?,?,?,?,?,?,?,?)",
                shopId, eventId, action, truncate(reason, 500), replacementEventId,
                adminId, subject, truncate(traceId, 128));
    }

    private static String truncate(String value, int max) {
        if (value == null || value.length() <= max) return value;
        return value.substring(0, max);
    }
}
