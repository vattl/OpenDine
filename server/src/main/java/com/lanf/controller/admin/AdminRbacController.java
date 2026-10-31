package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.config.DbApiPermissionMapping;
import com.lanf.entity.*;
import com.lanf.mapper.*;
import com.lanf.security.SecurityAuditService;
import com.lanf.util.StringUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.*;
import java.util.stream.Collectors;

/**
 * RBAC 配置管理：角色、权限、角色-权限、接口-权限等。
 * 仅具备 admin:manage 权限的管理员可在前端界面中使用这些接口调整配置。
 */
@RestController
@RequestMapping("/admin/rbac")
public class AdminRbacController {

    @Autowired
    private RoleMapper roleMapper;
    @Autowired
    private PermissionMapper permissionMapper;
    @Autowired
    private RolePermissionMapper rolePermissionMapper;
    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private ApiPermissionMapper apiPermissionMapper;
    @Autowired
    private DbApiPermissionMapping dbApiPermissionMapping;
    @Autowired
    private SecurityAuditService securityAuditService;
    @Autowired
    private HttpServletRequest currentRequest;

    /**
     * 角色列表（含绑定的权限），并返回全部权限列表，便于前端勾选。
     * @deprecated 自 v1.2.132 起废弃，请统一迁移至 {@code GET /admin/access/roles}。
     */
    @Deprecated
    @GetMapping("/roles")
    public R listRoles() {
        List<Role> roles = roleMapper.selectList(new QueryWrapper<Role>()
                .orderByAsc("sort_order")
                .orderByAsc("id"));
        List<Permission> permissions = permissionMapper.selectList(null);
        Map<Integer, Permission> permissionMap = permissions.stream()
                .collect(Collectors.toMap(Permission::getId, p -> p, (a, b) -> a));
        List<RolePermission> allRolePerms = rolePermissionMapper.selectList(null);
        Map<Integer, List<RolePermission>> rolePermGroup = allRolePerms.stream()
                .collect(Collectors.groupingBy(RolePermission::getRole_id));

        List<Map<String, Object>> list = new ArrayList<>();
        for (Role role : roles) {
            Map<String, Object> item = new HashMap<>();
            item.put("id", role.getId());
            item.put("role_code", role.getRole_code());
            item.put("role_name", role.getRole_name());
            item.put("remark", role.getRemark());
            item.put("sort_order", role.getSort_order());

            List<RolePermission> rpList = rolePermGroup.getOrDefault(role.getId(), Collections.emptyList());
            List<Integer> permissionIds = rpList.stream()
                    .map(RolePermission::getPermission_id)
                    .collect(Collectors.toList());
            item.put("permissionIds", permissionIds);

            List<Map<String, Object>> permList = permissionIds.stream()
                    .map(permissionMap::get)
                    .filter(Objects::nonNull)
                    .map(p -> {
                        Map<String, Object> m = new HashMap<>();
                        m.put("id", p.getId());
                        m.put("permission_code", p.getPermission_code());
                        m.put("permission_name", p.getPermission_name());
                        m.put("module", p.getModule());
                        return m;
                    })
                    .collect(Collectors.toList());
            item.put("permissions", permList);
            list.add(item);
        }

        Map<String, Object> data = new HashMap<>();
        data.put("list", list);
        data.put("total", list.size());
        data.put("allPermissions", permissions.stream().map(p -> {
            Map<String, Object> m = new HashMap<>();
            m.put("id", p.getId());
            m.put("permission_code", p.getPermission_code());
            m.put("permission_name", p.getPermission_name());
            m.put("module", p.getModule());
            return m;
        }).collect(Collectors.toList()));
        return R.ok(data);
    }

    /**
     * 新增或编辑角色。
     * 新增需传 role_code、role_name；编辑仅允许修改名称/备注/排序，不允许修改 role_code。
     * @deprecated 自 v1.2.132 起废弃，请统一迁移至 {@code POST/PUT /admin/access/roles}（具备版本号乐观锁控制）。
     */
    @Deprecated
    @PostMapping("/roles")
    public R saveRole(@RequestBody Role role) {
        if (role == null) {
            return R.error("参数不能为空");
        }
        boolean creating = role.getId() == null;
        Map<String, Object> before = null;
        if (creating) {
            // 新增
            if (StringUtil.isEmpty(role.getRole_code())) {
                return R.error("角色编码不能为空");
            }
            if (StringUtil.isEmpty(role.getRole_name())) {
                return R.error("角色名称不能为空");
            }
            Role exists = roleMapper.selectOne(new QueryWrapper<Role>()
                    .eq("role_code", role.getRole_code().trim()));
            if (exists != null) {
                return R.error("角色编码已存在");
            }
            roleMapper.insert(role);
        } else {
            // 编辑
            Role db = roleMapper.selectById(role.getId());
            if (db == null) {
                return R.error("角色不存在");
            }
            before = roleState(db);
            if (!StringUtil.isEmpty(role.getRole_name())) {
                db.setRole_name(role.getRole_name());
            }
            db.setRemark(role.getRemark());
            db.setSort_order(role.getSort_order());
            roleMapper.updateById(db);
            role = db;
        }
        securityAuditService.recordPermissionChange(currentRequest,
                creating ? "role_created" : "role_updated", String.valueOf(role.getId()),
                before, roleState(role));
        return R.ok();
    }

    /**
     * 删除角色：若已被管理员或权限引用则不允许删除。
     * @deprecated 自 v1.2.132 起废弃，请统一迁移至 {@code DELETE /admin/access/roles/{id}}（具备更完善的员工引用保护）。
     */
    @Deprecated
    @DeleteMapping("/roles/{id}")
    public R deleteRole(@PathVariable Integer id) {
        if (id == null) {
            return R.error("角色ID不能为空");
        }
        Role role = roleMapper.selectById(id);
        if (role == null) {
            return R.ok();
        }
        Integer adminRef = adminRoleMapper.selectCount(new QueryWrapper<AdminRole>().eq("role_id", id));
        if (adminRef != null && adminRef > 0) {
            return R.error("该角色已绑定管理员，无法删除");
        }
        Integer permRef = rolePermissionMapper.selectCount(new QueryWrapper<RolePermission>().eq("role_id", id));
        if (permRef != null && permRef > 0) {
            return R.error("该角色已绑定权限，请先解除绑定");
        }
        roleMapper.deleteById(id);
        securityAuditService.recordPermissionChange(currentRequest, "role_deleted", String.valueOf(id),
                roleState(role), null);
        return R.ok();
    }

    /**
     * 覆盖指定角色的权限列表（整组替换，事务内完成）。
     * @deprecated 自 v1.2.132 起废弃，请统一迁移至 {@code PUT /admin/access/roles/{id}}。
     */
    @Deprecated
    @PutMapping("/roles/{id}/permissions")
    @Transactional
    public R updateRolePermissions(@PathVariable Integer id, @RequestBody Map<String, Object> body) {
        if (id == null) {
            return R.error("角色ID不能为空");
        }
        Role role = roleMapper.selectById(id);
        if (role == null) {
            return R.error("角色不存在");
        }
        if (body == null || !(body.get("permissionIds") instanceof List)) {
            return R.error("permissionIds 必须为数组；传空数组表示撤销全部权限");
        }
        List<Integer> beforePermissionIds = rolePermissionMapper.selectList(
                        new QueryWrapper<RolePermission>().eq("role_id", id)).stream()
                .map(RolePermission::getPermission_id).filter(Objects::nonNull).distinct().sorted()
                .collect(Collectors.toList());
        Object permissionIdsObj = body != null ? body.get("permissionIds") : null;
        List<Integer> permissionIds = new ArrayList<>();
        if (permissionIdsObj instanceof List) {
            for (Object o : (List<?>) permissionIdsObj) {
                if (o instanceof Number) {
                    permissionIds.add(((Number) o).intValue());
                }
            }
        }
        // 校验权限是否存在
        if (!permissionIds.isEmpty()) {
            Integer count = permissionMapper.selectCount(new QueryWrapper<Permission>().in("id", permissionIds));
            if (count == null || count != permissionIds.size()) {
                return R.error("部分权限ID不存在，请刷新后重试");
            }
        }
        rolePermissionMapper.delete(new QueryWrapper<RolePermission>().eq("role_id", id));
        for (Integer permId : permissionIds) {
            RolePermission rp = new RolePermission();
            rp.setRole_id(id);
            rp.setPermission_id(permId);
            rolePermissionMapper.insert(rp);
        }
        Map<String, Object> before = new LinkedHashMap<>();
        before.put("permissionIds", beforePermissionIds);
        Map<String, Object> after = new LinkedHashMap<>();
        after.put("permissionIds", permissionIds);
        securityAuditService.recordPermissionChange(currentRequest, "role_permissions_changed",
                String.valueOf(id), before, after);
        return R.ok();
    }

    /**
     * 权限列表。
     */
    @GetMapping("/permissions")
    public R listPermissions() {
        List<Permission> list = permissionMapper.selectList(new QueryWrapper<Permission>()
                .orderByAsc("sort_order")
                .orderByAsc("id"));
        Map<String, Object> data = new HashMap<>();
        data.put("list", list);
        data.put("total", list.size());
        return R.ok(data);
    }

    /**
     * 新增或编辑权限。
     * 新增需传 permission_code、permission_name；编辑不允许修改 permission_code。
     */
    @PostMapping("/permissions")
    public R savePermission(@RequestBody Permission permission) {
        if (permission == null) {
            return R.error("参数不能为空");
        }
        boolean creating = permission.getId() == null;
        Map<String, Object> before = null;
        if (creating) {
            if (StringUtil.isEmpty(permission.getPermission_code())) {
                return R.error("权限编码不能为空");
            }
            if (StringUtil.isEmpty(permission.getPermission_name())) {
                return R.error("权限名称不能为空");
            }
            Permission exists = permissionMapper.selectOne(new QueryWrapper<Permission>()
                    .eq("permission_code", permission.getPermission_code().trim()));
            if (exists != null) {
                return R.error("权限编码已存在");
            }
            permissionMapper.insert(permission);
        } else {
            Permission db = permissionMapper.selectById(permission.getId());
            if (db == null) {
                return R.error("权限不存在");
            }
            before = permissionState(db);
            if (!StringUtil.isEmpty(permission.getPermission_name())) {
                db.setPermission_name(permission.getPermission_name());
            }
            db.setModule(permission.getModule());
            db.setRemark(permission.getRemark());
            db.setSort_order(permission.getSort_order());
            permissionMapper.updateById(db);
            permission = db;
        }
        securityAuditService.recordPermissionChange(currentRequest,
                creating ? "permission_created" : "permission_updated",
                String.valueOf(permission.getId()), before, permissionState(permission));
        return R.ok();
    }

    /**
     * 删除权限：如被角色或接口映射引用则不允许删除。
     */
    @DeleteMapping("/permissions/{id}")
    public R deletePermission(@PathVariable Integer id) {
        if (id == null) {
            return R.error("权限ID不能为空");
        }
        Permission permission = permissionMapper.selectById(id);
        if (permission == null) {
            return R.ok();
        }
        Integer rpRef = rolePermissionMapper.selectCount(new QueryWrapper<RolePermission>().eq("permission_id", id));
        if (rpRef != null && rpRef > 0) {
            return R.error("该权限已绑定角色，无法删除");
        }
        Integer apiRef = apiPermissionMapper.selectCount(new QueryWrapper<ApiPermission>()
                .eq("permission_code", permission.getPermission_code()));
        if (apiRef != null && apiRef > 0) {
            return R.error("该权限已绑定接口映射，请先解除绑定");
        }
        permissionMapper.deleteById(id);
        securityAuditService.recordPermissionChange(currentRequest, "permission_deleted", String.valueOf(id),
                permissionState(permission), null);
        return R.ok();
    }

    /**
     * 接口-权限映射列表。
     */
    @GetMapping("/api-permissions")
    public R listApiPermissions() {
        List<ApiPermission> list = apiPermissionMapper.selectList(new QueryWrapper<ApiPermission>()
                .orderByAsc("path_pattern")
                .orderByAsc("method"));
        Map<String, Object> data = new HashMap<>();
        data.put("list", list);
        data.put("total", list.size());
        return R.ok(data);
    }

    /**
     * 新增或编辑接口-权限映射。
     * 新增和编辑均会校验 method 合法性以及 permission_code 是否存在于 t_permission。
     */
    @PostMapping("/api-permissions")
    public R saveApiPermission(@RequestBody ApiPermission apiPermission) {
        if (apiPermission == null) {
            return R.error("参数不能为空");
        }
        if (StringUtil.isEmpty(apiPermission.getMethod()) || StringUtil.isEmpty(apiPermission.getPath_pattern())) {
            return R.error("method 和 path_pattern 不能为空");
        }
        String method = apiPermission.getMethod().trim().toUpperCase();
        if (!Arrays.asList("GET", "POST", "PUT", "DELETE", "*").contains(method)) {
            return R.error("method 仅支持 GET/POST/PUT/DELETE/*（* 表示任意方法）");
        }
        apiPermission.setMethod(method);
        if (StringUtil.isEmpty(apiPermission.getPermission_code())) {
            return R.error("permission_code 不能为空");
        }
        Integer permExists = permissionMapper.selectCount(new QueryWrapper<Permission>()
                .eq("permission_code", apiPermission.getPermission_code().trim()));
        if (permExists == null || permExists == 0) {
            return R.error("permission_code 不存在，请先在权限列表中创建");
        }
        boolean creating = apiPermission.getId() == null;
        ApiPermission beforeRow = creating ? null : apiPermissionMapper.selectById(apiPermission.getId());
        if (!creating && beforeRow == null) {
            return R.error("接口权限映射不存在");
        }
        // t_api_permission 唯一键 uk_path_pattern 按 path_pattern 全局唯一（同一路径仅一条映射），
        // 新增/编辑（含改路径）前预检，避免撞唯一键直接 500
        QueryWrapper<ApiPermission> dupQw = new QueryWrapper<ApiPermission>()
                .eq("path_pattern", apiPermission.getPath_pattern());
        if (!creating) {
            dupQw.ne("id", apiPermission.getId());
        }
        Integer dupCount = apiPermissionMapper.selectCount(dupQw);
        if (dupCount != null && dupCount > 0) {
            return R.error("path_pattern 已存在映射（同一路径仅允许一条记录），如需支持多方法请将原记录的 method 改为 *");
        }
        if (creating) {
            try {
                apiPermissionMapper.insert(apiPermission);
            } catch (org.springframework.dao.DuplicateKeyException e) {
                // 并发兜底：另一请求已插入同 path_pattern
                return R.error("path_pattern 已存在映射，请编辑原记录（同一路径仅允许一条记录）");
            }
        } else {
            apiPermissionMapper.updateById(apiPermission);
        }
        // 配置变更后刷新内存映射，使拦截器即时生效
        dbApiPermissionMapping.reload();
        securityAuditService.recordPermissionChange(currentRequest,
                creating ? "api_permission_created" : "api_permission_updated",
                String.valueOf(apiPermission.getId()), apiPermissionState(beforeRow), apiPermissionState(apiPermission));
        return R.ok();
    }

    /**
     * 删除接口-权限映射。
     */
    @DeleteMapping("/api-permissions/{id}")
    public R deleteApiPermission(@PathVariable Integer id) {
        if (id == null) {
            return R.error("ID 不能为空");
        }
        ApiPermission before = apiPermissionMapper.selectById(id);
        apiPermissionMapper.deleteById(id);
        dbApiPermissionMapping.reload();
        if (before != null) {
            securityAuditService.recordPermissionChange(currentRequest, "api_permission_deleted",
                    String.valueOf(id), apiPermissionState(before), null);
        }
        return R.ok();
    }

    /**
     * 热刷新接口-权限映射内存缓存。
     * 直接修改 t_api_permission 表后调用本接口即可生效，无需重启服务。
     */
    @PostMapping("/api-permissions/reload")
    public R reloadApiPermissions() {
        dbApiPermissionMapping.reload();
        return R.ok("接口权限映射已刷新");
    }

    private static Map<String, Object> roleState(Role role) {
        if (role == null) return null;
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("roleCode", role.getRole_code());
        state.put("roleName", role.getRole_name());
        return state;
    }

    private static Map<String, Object> permissionState(Permission permission) {
        if (permission == null) return null;
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("permissionCode", permission.getPermission_code());
        state.put("module", permission.getModule());
        return state;
    }

    private static Map<String, Object> apiPermissionState(ApiPermission mapping) {
        if (mapping == null) return null;
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("method", mapping.getMethod());
        state.put("pathPattern", mapping.getPath_pattern());
        state.put("permissionCode", mapping.getPermission_code());
        return state;
    }
}

