package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * SoD 职责分离权限冲突规则实体，对应 t_access_conflict_rule
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_access_conflict_rule")
public class AccessConflictRule {

    public static final String SEVERITY_HARD = "HARD";
    public static final String SEVERITY_SOFT = "SOFT";

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 冲突权限码A */
    private String permission_a;

    /** 冲突权限码B */
    private String permission_b;

    /** 冲突严重级别: HARD(严禁), SOFT(警告) */
    private String severity;

    /** 是否启用 1=启用 0=禁用 */
    private Integer enabled;

    /** 冲突提示文案 */
    private String message;
}
