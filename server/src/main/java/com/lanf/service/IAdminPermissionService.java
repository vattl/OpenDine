package com.lanf.service;

import java.util.Set;

/**
 * 管理员权限查询：根据 adminId 查询其拥有的权限码集合（来自角色-权限）
 */
public interface IAdminPermissionService {

    /**
     * 查询管理员拥有的权限码集合。
     * 若管理员未分配任何角色或查询失败，返回空集合并失败关闭。
     *
     * @param adminId 管理员 ID（t_admin.id）
     * @return 权限码集合，如 order:view, dish:manage；super_admin 角色拥有全部权限（从 t_role_permission 查出）
     */
    Set<String> getPermissionCodesByAdminId(Integer adminId);
}
