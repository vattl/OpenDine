package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Date;

/**
 * 角色权限策略绑定实体，对应 t_role_policy
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@TableName("t_role_policy")
public class RolePolicy {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 关联角色ID */
    private Integer role_id;

    /** 关联策略ID */
    private Long policy_id;

    /** 门店ID (NULL表示全局适用) */
    private Integer shop_id;

    private Date created_at;
}
