package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.RolePermission;
import org.apache.ibatis.annotations.Param;

import java.util.List;

/**
 * 角色-权限关联 Mapper，对应 t_role_permission
 */
public interface RolePermissionMapper extends BaseMapper<RolePermission> {

    /**
     * 根据角色 ID 列表查询权限编码列表（去重）
     * @Param("roleIds") 使 XML 中 collection="roleIds" 可正确绑定
     */
    List<String> selectPermissionCodesByRoleIds(@Param("roleIds") List<Integer> roleIds);
}
