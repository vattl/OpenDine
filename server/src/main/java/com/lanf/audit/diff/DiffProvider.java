package com.lanf.audit.diff;

import java.util.Map;

/**
 * 业务可选实现：捕获审计对象在操作前后的状态快照，
 * 写入 t_operation_log.before_state / after_state。
 * 实现需注册为 Spring Bean，并在 @AuditLog.diff() 中指定。
 */
public interface DiffProvider {

    /** 操作执行前捕获（切面在 proceed 之前调用）。targetId 为 @AuditLog.target() 解析出的业务主键。 */
    Map<String, Object> captureBefore(String targetId);

    /** 操作执行成功后捕获（切面在 proceed 返回之后调用）。 */
    Map<String, Object> captureAfter(String targetId);
}
