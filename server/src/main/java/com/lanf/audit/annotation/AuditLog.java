package com.lanf.audit.annotation;

import com.lanf.audit.diff.DiffProvider;
import com.lanf.audit.diff.NoopDiffProvider;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * 操作审计注解：标注在高价值写操作方法上，由 {@code AuditLogAspect} 统一记录到 t_operation_log。
 * <p>target 为 SpEL 表达式，在方法参数上取值（#p0、#p1… 或 #args），用于定位业务主键；
 * 解析失败时降级为 null 仅记录 module/action/快照，绝不阻断业务。</p>
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface AuditLog {

    /** 业务模块（如 cashier / order / refund / inventory）。 */
    String module();

    /** 操作动作（如 cashier_order_create / admin_refund_dish）。 */
    String action();

    /** SpEL 目标表达式，从方法参数取值，如 #p0['orderNo']。 */
    String target() default "";

    /** 前后状态快照提供者；默认不捕获。 */
    Class<? extends DiffProvider> diff() default NoopDiffProvider.class;
}
