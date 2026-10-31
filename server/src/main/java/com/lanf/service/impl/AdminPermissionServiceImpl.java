package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.AdminRole;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.RolePermissionMapper;
import com.lanf.service.IAdminPermissionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 管理员权限查询实现，与 docs/权限设计.md 第 3.2 节、docs/db_diancan_permission.sql 对齐。
 * 1. 查 t_admin_role（admin_id）得 role_id 列表；
 * 2. 未分配角色时返回空权限；否则通过 t_role_permission 关联 t_permission 得 permission_code 并集；
 * 3. 权限查询异常时失败关闭，返回空权限。
 */
@Service
public class AdminPermissionServiceImpl implements IAdminPermissionService {

    private static final Logger log = LoggerFactory.getLogger(AdminPermissionServiceImpl.class);

    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private RolePermissionMapper rolePermissionMapper;
    @Override
    public Set<String> getPermissionCodesByAdminId(Integer adminId) {
        if (adminId == null) {
            return Collections.emptySet();
        }
        try {
            List<AdminRole> adminRoles = adminRoleMapper.selectList(
                    new QueryWrapper<AdminRole>().eq("admin_id", adminId));
            List<Integer> roleIds = adminRoles.stream()
                    .map(AdminRole::getRole_id)
                    .collect(Collectors.toList());
            if (roleIds.isEmpty()) {
                log.warn("管理员未绑定角色，按无权限处理：adminId={}", adminId);
                return Collections.emptySet();
            }
            List<String> codes = rolePermissionMapper.selectPermissionCodesByRoleIds(roleIds);
            return codes == null ? Collections.emptySet() : codes.stream().collect(Collectors.toSet());
        } catch (Exception e) {
            log.error("查询管理员权限失败，按无权限处理：adminId={}", adminId, e);
            return Collections.emptySet();
        }
    }
}
