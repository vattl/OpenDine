package com.lanf.audit.aspect;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.adminlog.util.LogMaskUtil;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.audit.context.AuditContext;
import com.lanf.audit.diff.DiffProvider;
import com.lanf.audit.diff.NoopDiffProvider;
import com.lanf.security.SecurityAuditService;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.expression.Expression;
import org.springframework.expression.spel.standard.SpelExpressionParser;
import org.springframework.expression.spel.support.StandardEvaluationContext;
import org.springframework.stereotype.Component;

import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.multipart.MultipartFile;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 操作审计切面：拦截标注 {@link AuditLog} 的方法，记录操作者/门店/IP/参数快照（脱敏截断）/
 * 结果状态，并支持 {@link DiffProvider} 捕获前后状态，写入 t_operation_log。
 * 任何审计异常仅记录 error，绝不阻断或改变业务返回值。
 */
@Aspect
@Component
public class AuditLogAspect {

    private static final Logger log = LoggerFactory.getLogger(AuditLogAspect.class);
    private static final int MAX_SNAPSHOT_LENGTH = 2000;
    private static final int MAX_REASON_LENGTH = 255;
    private static final SpelExpressionParser SPEL = new SpelExpressionParser();

    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private ApplicationContext applicationContext;
    @Autowired
    private ObjectMapper objectMapper;

    @Around("@annotation(auditLog)")
    public Object around(ProceedingJoinPoint pjp, AuditLog auditLog) throws Throwable {
        HttpServletRequest request = AuditContext.currentRequest();
        Integer adminId = AuditContext.currentAdminId(request);
        Integer shopId = AuditContext.currentShopId(request);

        String targetId = resolveTarget(pjp.getArgs(), auditLog.target());
        DiffProvider diff = resolveDiff(auditLog);
        Map<String, Object> before = safeDiff(diff, true, targetId);
        Map<String, Object> snapshot = buildSnapshot(pjp.getArgs());

        try {
            Object result = pjp.proceed();
            Map<String, Object> after = safeDiff(diff, false, targetId);
            try {
                securityAuditService.recordPrivilegedActionWithState(
                        request, shopId, auditLog.module(), auditLog.action(),
                        targetId, adminId, snapshot, before, after, null);
            } catch (Exception e) {
                log.error("[audit] 记录审计日志失败 module={} action={} err={}",
                        auditLog.module(), auditLog.action(), e.getMessage());
            }
            return result;
        } catch (Throwable t) {
            try {
                securityAuditService.recordFailed(
                        request, shopId, auditLog.module(), auditLog.action(),
                        targetId, adminId, snapshot, truncate(t.getMessage(), MAX_REASON_LENGTH));
            } catch (Exception e) {
                log.error("[audit] 记录失败审计日志失败 module={} action={} err={}",
                        auditLog.module(), auditLog.action(), e.getMessage());
            }
            throw t;
        }
    }

    private DiffProvider resolveDiff(AuditLog auditLog) {
        if (auditLog.diff() == null || auditLog.diff() == NoopDiffProvider.class) {
            return null;
        }
        try {
            return applicationContext.getBean(auditLog.diff());
        } catch (Exception e) {
            log.warn("[audit] DiffProvider 实例化失败 {}，降级无前后状态", auditLog.diff().getSimpleName());
            return null;
        }
    }

    private Map<String, Object> safeDiff(DiffProvider diff, boolean before, String targetId) {
        if (diff == null || targetId == null) {
            return null;
        }
        try {
            return before ? diff.captureBefore(targetId) : diff.captureAfter(targetId);
        } catch (Exception e) {
            log.warn("[audit] 前后状态捕获失败 before={} targetId={} err={}", before, targetId, e.getMessage());
            return null;
        }
    }

    /** SpEL target：支持 #p0..#pN（按参数位置）与 #args；解析失败返回 null（不阻断）。 */
    private String resolveTarget(Object[] args, String expression) {
        if (expression == null || expression.trim().isEmpty()) {
            return null;
        }
        try {
            StandardEvaluationContext ctx = new StandardEvaluationContext();
            ctx.setVariable("args", args);
            if (args != null) {
                for (int i = 0; i < args.length; i++) {
                    ctx.setVariable("p" + i, args[i]);
                }
            }
            Expression exp = SPEL.parseExpression(expression.trim());
            Object v = exp.getValue(ctx);
            return v == null ? null : String.valueOf(v).trim();
        } catch (Exception e) {
            log.debug("[audit] target SpEL 解析失败 expr={} err={}", expression, e.getMessage());
            return null;
        }
    }

    private Map<String, Object> buildSnapshot(Object[] args) {
        Map<String, Object> snapshot = new LinkedHashMap<>();
        if (args == null || args.length == 0) {
            return snapshot;
        }
        try {
            Object[] sanitized = sanitizeArgsForSnapshot(args);
            String json = objectMapper.writeValueAsString(sanitized);
            if (json != null && json.length() > MAX_SNAPSHOT_LENGTH) {
                json = json.substring(0, MAX_SNAPSHOT_LENGTH);
            }
            snapshot.put("args", LogMaskUtil.mask(json));
        } catch (Throwable t) {
            snapshot.put("args", "[serialization-error]");
        }
        return snapshot;
    }

    private Object[] sanitizeArgsForSnapshot(Object[] args) {
        if (args == null || args.length == 0) {
            return args;
        }
        Object[] sanitized = new Object[args.length];
        for (int i = 0; i < args.length; i++) {
            Object arg = args[i];
            if (arg instanceof MultipartFile) {
                MultipartFile mf = (MultipartFile) arg;
                Map<String, Object> fileInfo = new LinkedHashMap<>();
                fileInfo.put("type", "MultipartFile");
                fileInfo.put("name", mf.getName());
                fileInfo.put("originalFilename", mf.getOriginalFilename());
                fileInfo.put("size", mf.getSize());
                fileInfo.put("contentType", mf.getContentType());
                sanitized[i] = fileInfo;
            } else if (arg instanceof InputStream || arg instanceof OutputStream ||
                       arg instanceof ServletRequest || arg instanceof ServletResponse) {
                sanitized[i] = "[" + arg.getClass().getSimpleName() + "]";
            } else {
                sanitized[i] = arg;
            }
        }
        return sanitized;
    }

    private static String truncate(String s, int limit) {
        if (s == null) {
            return null;
        }
        return s.length() <= limit ? s : s.substring(0, limit);
    }
}
