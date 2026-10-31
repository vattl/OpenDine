package com.lanf.access.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.access.model.AccessContext;
import com.lanf.access.model.AccessDecision;
import com.lanf.common.ApiException;
import com.lanf.entity.*;
import com.lanf.mapper.*;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 员工与门店授权 / 角色管理 / 权限解释 / 策略管理 / 生命周期与审计。
 * POS Access Control v2 核心业务服务。
 */
@Service
public class AccessService {

    private static final Logger log = LoggerFactory.getLogger(AccessService.class);

    public static final String ERROR_CONFIRM_REQUIRED = "ACCESS_CONFIRM_REQUIRED";
    public static final String ERROR_ROLE_IN_USE = "ROLE_IN_USE";
    public static final String ERROR_ROLE_VERSION_CONFLICT = "ACCESS_ROLE_VERSION_CONFLICT";
    public static final String ERROR_NOT_FOUND = "ACCESS_NOT_FOUND";
    public static final String ERROR_VALIDATION = "ACCESS_VALIDATION_FAILED";

    @Autowired
    private AdminMapper adminMapper;
    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private AdminShopMapper adminShopMapper;
    @Autowired(required = false)
    private AdminRegionMapper adminRegionMapper;
    @Autowired
    private RoleMapper roleMapper;
    @Autowired
    private PermissionMapper permissionMapper;
    @Autowired
    private RolePermissionMapper rolePermissionMapper;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;

    @Autowired(required = false)
    private OrderMapper orderMapper;
    @Autowired(required = false)
    private ShiftMapper shiftMapper;
    @Autowired(required = false)
    private OperationLogMapper operationLogMapper;
    @Autowired(required = false)
    private AccessApprovalMapper approvalMapper;
    @Autowired
    private AccessConflictService conflictService;
    @Autowired
    private AccessDecisionService accessDecisionService;
    @Autowired
    private AccessPolicyMapper accessPolicyMapper;
    @Autowired
    private RolePolicyMapper rolePolicyMapper;
    @Autowired
    private AdminPermissionOverrideMapper overrideMapper;

    // ---------------- 员工列表 ----------------

    public Map<String, Object> listEmployees(String keyword, int page, int pageSize) {
        QueryWrapper<Admin> q = new QueryWrapper<>();
        if (!StringUtil.isEmpty(keyword)) {
            String kw = keyword.trim();
            q.and(w -> w.like("userName", kw)
                    .or().like("work_no", kw)
                    .or().like("real_name", kw)
                    .or().like("job_title", kw));
        }
        q.orderByAsc("id");
        List<Admin> all = adminMapper.selectList(q);
        int total = all.size();
        int from = Math.max(0, (page - 1) * pageSize);
        int to = Math.min(total, from + pageSize);
        List<Admin> pageItems = all.subList(from, to);

        List<Integer> adminIds = pageItems.stream().map(Admin::getId).collect(Collectors.toList());
        Map<Integer, List<Role>> rolesByAdmin = rolesByAdmin(adminIds);
        Map<Integer, List<Integer>> shopsByAdmin = shopsByAdmin(adminIds);

        List<Map<String, Object>> items = new ArrayList<>();
        for (Admin admin : pageItems) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("adminId", admin.getId());
            m.put("userName", admin.getUserName());
            m.put("workNo", admin.getWorkNo());
            m.put("work_no", admin.getWorkNo());
            m.put("realName", admin.getRealName());
            m.put("real_name", admin.getRealName());
            m.put("jobTitle", admin.getJobTitle());
            m.put("job_title", admin.getJobTitle());
            String displayName = com.lanf.util.AdminNameResolver.resolveDisplayName(admin);
            m.put("name", displayName);
            m.put("displayName", displayName);
            m.put("accountStatus", admin.getAccountStatus() != null ? admin.getAccountStatus() : Admin.STATUS_ACTIVE);
            m.put("permissionVersion", admin.getPermissionVersion() != null ? admin.getPermissionVersion() : 1L);
            m.put("lastLoginAt", admin.getLastLoginAt());
            m.put("lastLoginIp", admin.getLastLoginIp());
            List<Map<String, Object>> roles = new ArrayList<>();
            for (Role role : rolesByAdmin.getOrDefault(admin.getId(), Collections.emptyList())) {
                Map<String, Object> r = new LinkedHashMap<>();
                r.put("id", role.getId());
                r.put("roleCode", role.getRole_code());
                r.put("roleName", role.getRole_name());
                roles.add(r);
            }
            m.put("roles", roles);
            m.put("shops", shopsByAdmin.getOrDefault(admin.getId(), Collections.emptyList()));
            items.add(m);
        }
        return pageResult(page, pageSize, total, items);
    }

    // ---------------- 员工授权（角色 + 多店） ----------------

    /**
     * 覆盖式分配：替换该管理员的全部角色与门店授权。敏感操作需 confirm=true。
     */
    @Transactional
    public Map<String, Object> assignEmployee(int adminId, List<Integer> roleIds, List<Integer> shopIds,
                                              boolean confirm, Integer operatorId) {
        if (!confirm) {
            throw new ApiException(400, ERROR_CONFIRM_REQUIRED, "员工授权为敏感操作，需二次确认（confirm=true）");
        }
        Admin admin = adminMapper.selectById(adminId);
        if (admin == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "管理员不存在: " + adminId);
        }
        if (roleIds != null && !roleIds.isEmpty()) {
            Set<Integer> existing = roleMapper.selectBatchIds(roleIds).stream()
                    .map(Role::getId).collect(Collectors.toSet());
            if (existing.size() != roleIds.size()) {
                throw new ApiException(400, ERROR_VALIDATION, "存在无效角色 id");
            }

            // SoD 职责分离冲突检测
            if (conflictService != null) {
                List<RolePermission> rps = rolePermissionMapper.selectList(new QueryWrapper<RolePermission>().in("role_id", roleIds));
                if (!rps.isEmpty()) {
                    List<Integer> permIds = rps.stream().map(RolePermission::getPermission_id).distinct().collect(Collectors.toList());
                    List<Permission> perms = permissionMapper.selectBatchIds(permIds);
                    if (perms != null) {
                        List<String> codes = perms.stream().map(Permission::getPermission_code).collect(Collectors.toList());
                        boolean isSuper = operatorId != null && adminShopAccessService.isSuperAdmin(operatorId);
                        conflictService.validateNoHardConflict(codes, isSuper, null);
                    }
                }
            }
        }

        adminRoleMapper.delete(new QueryWrapper<AdminRole>().eq("admin_id", adminId));
        if (roleIds != null) {
            for (Integer roleId : roleIds) {
                AdminRole ar = new AdminRole();
                ar.setAdmin_id(adminId);
                ar.setRole_id(roleId);
                adminRoleMapper.insert(ar);
            }
        }
        adminShopMapper.delete(new QueryWrapper<AdminShop>().eq("admin_id", adminId));
        if (shopIds != null) {
            for (Integer shopId : shopIds) {
                AdminShop as = new AdminShop();
                as.setAdmin_id(adminId);
                as.setShop_id(shopId);
                adminShopMapper.insert(as);
            }
        }

        // 递增权限版本号，令旧会话权限缓存失效
        admin.setPermissionVersion((admin.getPermissionVersion() != null ? admin.getPermissionVersion() : 1L) + 1);
        adminMapper.updateById(admin);

        log.info("[access] employee assigned: admin={}, roles={}, shops={}, newVer={}, by={}",
                adminId, roleIds, shopIds, admin.getPermissionVersion(), operatorId);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("adminId", adminId);
        result.put("roleIds", roleIds == null ? Collections.emptyList() : roleIds);
        result.put("shopIds", shopIds == null ? Collections.emptyList() : shopIds);
        result.put("permissionVersion", admin.getPermissionVersion());
        return result;
    }

    /**
     * 变更员工状态 (ACTIVE, DISABLED, LOCKED, RESIGNED)
     */
    @Transactional
    public Map<String, Object> updateEmployeeStatus(int adminId, String newStatus, Integer operatorId) {
        if (!Arrays.asList(Admin.STATUS_ACTIVE, Admin.STATUS_DISABLED, Admin.STATUS_LOCKED, Admin.STATUS_RESIGNED).contains(newStatus)) {
            throw new ApiException(400, ERROR_VALIDATION, "无效的员工状态: " + newStatus);
        }
        if (operatorId != null && operatorId.equals(adminId) && !Admin.STATUS_ACTIVE.equals(newStatus)) {
            throw new ApiException(400, ERROR_VALIDATION, "安全保护：不能对当前登录账号执行停用或注销");
        }
        Admin admin = adminMapper.selectById(adminId);
        if (admin == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "管理员不存在: " + adminId);
        }
        admin.setAccountStatus(newStatus);
        admin.setPermissionVersion((admin.getPermissionVersion() != null ? admin.getPermissionVersion() : 1L) + 1);
        if (Admin.STATUS_DISABLED.equals(newStatus) || Admin.STATUS_RESIGNED.equals(newStatus)) {
            admin.setForceLogoutAt(new Date());
            admin.setTokenVersion((admin.getTokenVersion() != null ? admin.getTokenVersion() : 0) + 1);
        }
        int rows = adminMapper.updateById(admin);
        if (rows <= 0) {
            // updateById 影响行数为 0：可能是并发下已先更新为目标状态（幂等），也可能是写库未生效。
            // 回查 DB 区分两种情况，避免「接口返回成功但状态未变」的静默失败。
            Admin latest = adminMapper.selectById(adminId);
            if (latest != null && newStatus.equals(latest.getAccountStatus())) {
                log.info("[access] employee status already target (idempotent): adminId={}, status={}, by={}",
                        adminId, newStatus, operatorId);
            } else {
                log.warn("[access] employee status update affected 0 rows: adminId={}, status={}, dbStatus={}, by={}",
                        adminId, newStatus, latest != null ? latest.getAccountStatus() : "null", operatorId);
                throw new ApiException(500, "ACCESS_STATUS_UPDATE_FAILED",
                        "员工状态更新未生效（数据库未变更），请刷新后重试或联系管理员");
            }
        }
        log.info("[access] employee status updated: adminId={}, status={}, newVer={}, by={}",
                adminId, newStatus, admin.getPermissionVersion(), operatorId);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("adminId", adminId);
        out.put("accountStatus", newStatus);
        out.put("permissionVersion", admin.getPermissionVersion());
        return out;
    }

    /**
     * 强制下线员工全部活跃会话
     */
    @Transactional
    public void forceLogout(int adminId, Integer operatorId) {
        Admin admin = adminMapper.selectById(adminId);
        if (admin == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "管理员不存在: " + adminId);
        }
        admin.setForceLogoutAt(new Date());
        admin.setTokenVersion((admin.getTokenVersion() != null ? admin.getTokenVersion() : 0) + 1);
        admin.setPermissionVersion((admin.getPermissionVersion() != null ? admin.getPermissionVersion() : 1L) + 1);
        adminMapper.updateById(admin);
        log.info("[access] employee force logged out: adminId={}, by={}", adminId, operatorId);
    }

    /**
     * 删除员工：历史有订单/班次/审批/操作日志业务记录时禁止删除 (409)
     */
    @Transactional
    public void deleteEmployee(int adminId, boolean confirm, Integer operatorId) {
        if (!confirm) {
            throw new ApiException(400, ERROR_CONFIRM_REQUIRED, "删除员工操作需要显式确认（confirm=true）");
        }
        if (operatorId != null && operatorId.equals(adminId)) {
            throw new ApiException(400, ERROR_VALIDATION, "安全保护：不能删除当前正在登录的账号");
        }
        Admin admin = adminMapper.selectById(adminId);
        if (admin == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "员工不存在");
        }

        if (hasBusinessHistory(adminId)) {
            throw new ApiException(409, "ACCESS_EMPLOYEE_HAS_HISTORY", "该员工已有业务记录，不能物理删除，可改为离职或停用");
        }

        adminRoleMapper.delete(new QueryWrapper<AdminRole>().eq("admin_id", adminId));
        adminShopMapper.delete(new QueryWrapper<AdminShop>().eq("admin_id", adminId));
        if (adminRegionMapper != null) {
            adminRegionMapper.delete(new QueryWrapper<AdminRegion>().eq("admin_id", adminId));
        }
        adminMapper.deleteById(adminId);
        log.info("[access] employee deleted: adminId={}, userName={}, by={}", adminId, admin.getUserName(), operatorId);
    }

    public boolean hasBusinessHistory(int adminId) {
        if (orderMapper != null) {
            Integer count = orderMapper.selectCount(new QueryWrapper<Order>().eq("order_admin_id", adminId));
            if (count != null && count > 0) return true;
        }
        if (shiftMapper != null) {
            Integer count = shiftMapper.selectCount(new QueryWrapper<Shift>().eq("admin_id", adminId));
            if (count != null && count > 0) return true;
        }
        if (operationLogMapper != null) {
            Integer count = operationLogMapper.selectCount(new QueryWrapper<OperationLog>().eq("admin_id", adminId));
            if (count != null && count > 0) return true;
        }
        if (approvalMapper != null) {
            Integer count = approvalMapper.selectCount(new QueryWrapper<AccessApproval>()
                    .eq("operator_id", adminId).or().eq("authorizer_id", adminId));
            if (count != null && count > 0) return true;
        }
        return false;
    }

    public Map<String, Object> getEffectivePermissions(int adminId, Integer shopId) {
        Admin admin = adminMapper.selectById(adminId);
        if (admin == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "管理员不存在: " + adminId);
        }
        Set<String> rbacCodes = adminPermissionService.getPermissionCodesByAdminId(adminId);
        List<Map<String, Object>> roles = rolesByAdmin(Collections.singletonList(adminId))
                .getOrDefault(adminId, Collections.emptyList())
                .stream().map(this::roleView).collect(Collectors.toList());

        List<AdminPermissionOverride> overrides = overrideMapper.selectList(new QueryWrapper<AdminPermissionOverride>()
                .eq("admin_id", adminId)
                .and(w -> w.isNull("shop_id").or().eq("shop_id", shopId)));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("adminId", adminId);
        out.put("userName", admin.getUserName());
        out.put("realName", admin.getRealName());
        out.put("accountStatus", admin.getAccountStatus() != null ? admin.getAccountStatus() : Admin.STATUS_ACTIVE);
        out.put("permissionVersion", admin.getPermissionVersion() != null ? admin.getPermissionVersion() : 1L);
        out.put("roles", roles);
        out.put("permissions", rbacCodes != null ? rbacCodes : Collections.emptySet());
        out.put("overrides", overrides != null ? overrides : Collections.emptyList());
        return out;
    }

    // ---------------- 角色管理 ----------------

    public List<Map<String, Object>> listRoles() {
        List<Role> roles = roleMapper.selectList(new QueryWrapper<Role>().orderByAsc("sort_order").orderByAsc("id"));
        Map<Integer, List<Map<String, Object>>> permissionsByRole = new HashMap<>();
        List<RolePermission> grants = rolePermissionMapper.selectList(null);
        if (!grants.isEmpty()) {
            List<Integer> permissionIds = grants.stream().map(RolePermission::getPermission_id)
                    .filter(Objects::nonNull).distinct().collect(Collectors.toList());
            if (!permissionIds.isEmpty()) {
                List<Permission> perms = permissionMapper.selectBatchIds(permissionIds);
                Map<Integer, Permission> byId = perms.stream()
                        .collect(Collectors.toMap(Permission::getId, p -> p, (a, b) -> a));
                for (RolePermission rp : grants) {
                    Permission p = byId.get(rp.getPermission_id());
                    if (p == null) continue;
                    Map<String, Object> pm = new LinkedHashMap<>();
                    pm.put("id", p.getId());
                    pm.put("permissionCode", p.getPermission_code());
                    pm.put("permissionName", p.getPermission_name());
                    permissionsByRole.computeIfAbsent(rp.getRole_id(), k -> new ArrayList<>()).add(pm);
                }
            }
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (Role role : roles) {
            Map<String, Object> m = roleView(role);
            Integer adminCount = adminRoleMapper.selectCount(new QueryWrapper<AdminRole>().eq("role_id", role.getId()));
            m.put("adminCount", adminCount == null ? 0 : adminCount);
            m.put("permissions", permissionsByRole.getOrDefault(role.getId(), Collections.emptyList()));
            out.add(m);
        }
        return out;
    }

    public Map<String, Object> createRole(Map<String, Object> body, Integer operatorId) {
        String code = text(body.get("roleCode"));
        String name = text(body.get("roleName"));
        if (StringUtil.isEmpty(code) || StringUtil.isEmpty(name)) {
            throw new ApiException(400, ERROR_VALIDATION, "roleCode 与 roleName 不能为空");
        }
        Integer dup = roleMapper.selectCount(new QueryWrapper<Role>().eq("role_code", code));
        if (dup != null && dup > 0) {
            throw new ApiException(409, "ACCESS_ROLE_CODE_DUPLICATE", "角色编码已存在: " + code);
        }

        // SoD 冲突检测
        validateRoleSoD(body.get("permissionIds"), operatorId, text(body.get("forceReason")));

        Role role = new Role();
        role.setRole_code(code);
        role.setRole_name(name);
        role.setRemark(text(body.get("remark")));
        role.setSort_order(body.get("sortOrder") instanceof Number ? ((Number) body.get("sortOrder")).intValue() : 100);
        role.setRole_type(Role.TYPE_CUSTOM);
        role.setEditable(1);
        role.setSystem_protected(0);
        role.setPriority(100);
        role.setVersion(1);
        roleMapper.insert(role);
        applyPermissionIds(role.getId(), body.get("permissionIds"), operatorId);
        log.info("[access] role created: id={}, code={}, by={}", role.getId(), code, operatorId);
        return roleView(role);
    }

    public Map<String, Object> updateRole(int roleId, Map<String, Object> body, Integer operatorId) {
        Role role = requireRole(roleId);
        if (role.getEditable() != null && role.getEditable() == 0) {
            throw new ApiException(403, "ACCESS_ROLE_READONLY", "该角色为系统受保护只读角色，禁止编辑");
        }

        Integer expectedVersion = body.get("version") instanceof Number
                ? ((Number) body.get("version")).intValue() : null;
        if (expectedVersion == null) {
            throw new ApiException(400, "ACCESS_VERSION_REQUIRED", "更新请求必须携带 version 乐观锁");
        }
        if (!expectedVersion.equals(role.getVersion() != null ? role.getVersion() : 1)) {
            Map<String, Object> latest = new LinkedHashMap<>();
            latest.put("id", role.getId());
            latest.put("version", role.getVersion());
            latest.put("roleName", role.getRole_name());
            throw new ApiException(409, ERROR_ROLE_VERSION_CONFLICT, "角色已被他人修改，请重新加载", latest);
        }

        // SoD 冲突检测
        if (body.get("permissionIds") != null) {
            validateRoleSoD(body.get("permissionIds"), operatorId, text(body.get("forceReason")));
        }

        if (body.get("roleName") != null) {
            role.setRole_name(String.valueOf(body.get("roleName")));
        }
        if (body.get("remark") != null) {
            role.setRemark(String.valueOf(body.get("remark")));
        }
        if (body.get("sortOrder") instanceof Number) {
            role.setSort_order(((Number) body.get("sortOrder")).intValue());
        }
        role.setVersion((role.getVersion() != null ? role.getVersion() : 1) + 1);
        roleMapper.updateById(role);
        applyPermissionIds(roleId, body.get("permissionIds"), operatorId);

        // 联动更新关联管理员的 permission_version
        bumpPermissionVersionForRole(roleId);

        log.info("[access] role updated: id={}, version={}, by={}", roleId, role.getVersion(), operatorId);
        return roleView(role);
    }

    private void validateRoleSoD(Object permissionIdsRaw, Integer operatorId, String forceReason) {
        if (permissionIdsRaw instanceof List && conflictService != null) {
            List<Integer> ids = new ArrayList<>();
            for (Object o : (List<?>) permissionIdsRaw) {
                if (o instanceof Number) ids.add(((Number) o).intValue());
            }
            if (!ids.isEmpty()) {
                List<Permission> perms = permissionMapper.selectBatchIds(ids);
                if (perms != null) {
                    List<String> codes = perms.stream().map(Permission::getPermission_code).collect(Collectors.toList());
                    boolean isSuper = operatorId != null && adminShopAccessService.isSuperAdmin(operatorId);
                    conflictService.validateNoHardConflict(codes, isSuper, forceReason);
                }
            }
        }
    }

    private void bumpPermissionVersionForRole(int roleId) {
        List<AdminRole> bindings = adminRoleMapper.selectList(new QueryWrapper<AdminRole>().eq("role_id", roleId));
        if (bindings != null && !bindings.isEmpty()) {
            for (AdminRole b : bindings) {
                Admin a = adminMapper.selectById(b.getAdmin_id());
                if (a != null) {
                    a.setPermissionVersion((a.getPermissionVersion() != null ? a.getPermissionVersion() : 1L) + 1);
                    adminMapper.updateById(a);
                }
            }
        }
    }

    /** 角色被管理员引用或系统保护时禁止删除 */
    @Transactional
    public void deleteRole(int roleId, boolean confirm, Integer operatorId) {
        if (!confirm) {
            throw new ApiException(400, ERROR_CONFIRM_REQUIRED, "删除角色需二次确认（confirm=true）");
        }
        Role role = requireRole(roleId);
        if (role.getSystem_protected() != null && role.getSystem_protected() == 1) {
            throw new ApiException(403, "ACCESS_ROLE_PROTECTED", "系统预置受保护角色，禁止删除");
        }
        Integer adminCount = adminRoleMapper.selectCount(new QueryWrapper<AdminRole>().eq("role_id", roleId));
        if (adminCount != null && adminCount > 0) {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("adminCount", adminCount);
            throw new ApiException(409, ERROR_ROLE_IN_USE,
                    "角色仍被 " + adminCount + " 个管理员引用，请先解除绑定", data);
        }
        rolePermissionMapper.delete(new QueryWrapper<RolePermission>().eq("role_id", roleId));
        if (rolePolicyMapper != null) {
            rolePolicyMapper.delete(new QueryWrapper<RolePolicy>().eq("role_id", roleId));
        }
        roleMapper.deleteById(roleId);
        log.info("[access] role deleted: id={}, by={}", roleId, operatorId);
    }

    private void applyPermissionIds(int roleId, Object permissionIdsRaw, Integer operatorId) {
        if (permissionIdsRaw == null) {
            return;
        }
        List<Integer> ids = new ArrayList<>();
        if (permissionIdsRaw instanceof List) {
            for (Object o : (List<?>) permissionIdsRaw) {
                if (o instanceof Number) {
                    int v = ((Number) o).intValue();
                    if (!ids.contains(v)) {
                        ids.add(v);
                    }
                }
            }
        }
        if (!ids.isEmpty()) {
            List<Permission> perms = permissionMapper.selectBatchIds(ids);
            if (perms.size() != ids.size()) {
                throw new ApiException(400, "ACCESS_PERMISSION_NOT_FOUND", "部分权限码不存在，请刷新后重试");
            }
        }
        rolePermissionMapper.delete(new QueryWrapper<RolePermission>().eq("role_id", roleId));
        for (Integer pid : ids) {
            RolePermission rp = new RolePermission();
            rp.setRole_id(roleId);
            rp.setPermission_id(pid);
            rolePermissionMapper.insert(rp);
        }
        log.info("[access] role permissions replaced: role={}, count={}, by={}", roleId, ids.size(), operatorId);
    }

    // ---------------- 权限策略管理 ----------------

    public List<AccessPolicy> listPolicies(String permissionCode) {
        QueryWrapper<AccessPolicy> q = new QueryWrapper<AccessPolicy>().orderByAsc("priority").orderByAsc("id");
        if (org.springframework.util.StringUtils.hasText(permissionCode)) {
            q.eq("permission_code", permissionCode.trim());
        }
        return accessPolicyMapper.selectList(q);
    }

    public AccessPolicy createPolicy(AccessPolicy policy, Integer operatorId) {
        if (policy == null || StringUtil.isEmpty(policy.getPolicy_code()) || StringUtil.isEmpty(policy.getPermission_code())) {
            throw new ApiException(400, ERROR_VALIDATION, "policy_code 与 permission_code 必填");
        }
        Integer dup = accessPolicyMapper.selectCount(new QueryWrapper<AccessPolicy>().eq("policy_code", policy.getPolicy_code()));
        if (dup != null && dup > 0) {
            throw new ApiException(409, "ACCESS_POLICY_CODE_DUPLICATE", "策略编码已存在: " + policy.getPolicy_code());
        }
        policy.setCreated_at(new Date());
        policy.setUpdated_at(new Date());
        if (policy.getPriority() == null) policy.setPriority(100);
        if (policy.getEnabled() == null) policy.setEnabled(1);
        accessPolicyMapper.insert(policy);
        log.info("[access] policy created: code={}, by={}", policy.getPolicy_code(), operatorId);
        return policy;
    }

    public AccessPolicy updatePolicy(Long id, AccessPolicy body, Integer operatorId) {
        AccessPolicy db = accessPolicyMapper.selectById(id);
        if (db == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "策略不存在: " + id);
        }
        if (org.springframework.util.StringUtils.hasText(body.getPolicy_name())) db.setPolicy_name(body.getPolicy_name());
        if (org.springframework.util.StringUtils.hasText(body.getPolicy_type())) db.setPolicy_type(body.getPolicy_type());
        if (org.springframework.util.StringUtils.hasText(body.getEffect())) db.setEffect(body.getEffect());
        if (body.getPriority() != null) db.setPriority(body.getPriority());
        if (body.getEnabled() != null) db.setEnabled(body.getEnabled());
        if (body.getConfig_json() != null) db.setConfig_json(body.getConfig_json());
        db.setUpdated_at(new Date());
        accessPolicyMapper.updateById(db);
        log.info("[access] policy updated: id={}, by={}", id, operatorId);
        return db;
    }

    public void deletePolicy(Long id, Integer operatorId) {
        AccessPolicy db = accessPolicyMapper.selectById(id);
        if (db == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "策略不存在: " + id);
        }
        rolePolicyMapper.delete(new QueryWrapper<RolePolicy>().eq("policy_id", id));
        accessPolicyMapper.deleteById(id);
        log.info("[access] policy deleted: id={}, by={}", id, operatorId);
    }

    public void assignPolicyToRole(Integer roleId, Long policyId, Integer shopId, Integer operatorId) {
        Role role = requireRole(roleId);
        AccessPolicy policy = accessPolicyMapper.selectById(policyId);
        if (policy == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "策略不存在: " + policyId);
        }
        QueryWrapper<RolePolicy> qw = new QueryWrapper<RolePolicy>()
                .eq("role_id", roleId)
                .eq("policy_id", policyId);
        if (shopId == null) {
            qw.isNull("shop_id");
        } else {
            qw.eq("shop_id", shopId);
        }
        RolePolicy existing = rolePolicyMapper.selectOne(qw);
        if (existing == null) {
            RolePolicy rp = RolePolicy.builder()
                    .role_id(roleId)
                    .policy_id(policyId)
                    .shop_id(shopId)
                    .created_at(new Date())
                    .build();
            rolePolicyMapper.insert(rp);
            bumpPermissionVersionForRole(roleId);
            log.info("[access] policy assigned to role: role={}, policy={}, shop={}, by={}", roleId, policyId, shopId, operatorId);
        }
    }

    // ---------------- 审批记录查询 ----------------

    public Map<String, Object> listApprovals(Integer shopId, String bizType, String status, int page, int pageSize) {
        QueryWrapper<AccessApproval> q = new QueryWrapper<AccessApproval>().orderByDesc("id");
        if (shopId != null) q.eq("shop_id", shopId);
        if (org.springframework.util.StringUtils.hasText(bizType)) q.eq("biz_type", bizType.trim());
        if (org.springframework.util.StringUtils.hasText(status)) q.eq("status", status.trim());

        List<AccessApproval> all = approvalMapper != null ? approvalMapper.selectList(q) : Collections.emptyList();
        int total = all.size();
        int from = Math.max(0, (page - 1) * pageSize);
        int to = Math.min(total, from + pageSize);
        List<AccessApproval> pageItems = all.subList(from, to);
        Map<Integer, Admin> adminIndex = adminIndexByIds(pageItems);
        List<Map<String, Object>> items = pageItems.stream()
                .map(a -> approvalToMap(a, adminIndex))
                .collect(Collectors.toList());
        return pageResult(page, pageSize, total, items);
    }

    public Map<String, Object> getApproval(Long id) {
        if (approvalMapper == null) throw new ApiException(404, ERROR_NOT_FOUND, "审批记录不存在: " + id);
        AccessApproval db = approvalMapper.selectById(id);
        if (db == null) throw new ApiException(404, ERROR_NOT_FOUND, "审批记录不存在: " + id);
        return approvalToMap(db, adminIndexByIds(Collections.singletonList(db)));
    }

    /**
     * 本门店最近成功授权人（去重、按时间倒序），供收银端授权弹窗快捷选择账号。
     */
    public List<Map<String, Object>> recentAuthors(Integer shopId, int limit) {
        if (approvalMapper == null) return Collections.emptyList();
        if (limit <= 0) limit = 10;
        QueryWrapper<AccessApproval> q = new QueryWrapper<AccessApproval>()
                .eq("shop_id", shopId)
                .isNotNull("authorizer_id")
                .ne("authorizer_id", 0)
                .in("status", AccessApproval.STATUS_APPROVED, AccessApproval.STATUS_CONSUMED)
                .orderByDesc("id");
        List<AccessApproval> all = approvalMapper.selectList(q);
        Set<Integer> seen = new HashSet<>();
        List<Map<String, Object>> out = new ArrayList<>();
        for (AccessApproval a : all) {
            if (a.getAuthorizer_id() == null || seen.contains(a.getAuthorizer_id())) continue;
            seen.add(a.getAuthorizer_id());
            Admin admin = adminMapper.selectById(a.getAuthorizer_id());
            if (admin == null) continue;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("authorizerId", admin.getId());
            m.put("authorizerName", admin.getRealName() != null ? admin.getRealName() : admin.getUserName());
            m.put("authorizerWorkNo", admin.getWorkNo());
            m.put("lastApprovalAt", a.getCreated_at());
            out.add(m);
            if (out.size() >= limit) break;
        }
        return out;
    }

    // ---------------- 审批流水展示增强 ----------------

    private Map<Integer, Admin> adminIndexByIds(List<AccessApproval> approvals) {
        Map<Integer, Admin> index = new HashMap<>();
        if (approvals == null || approvals.isEmpty()) return index;
        Set<Integer> ids = new HashSet<>();
        for (AccessApproval a : approvals) {
            if (a.getOperator_id() != null) ids.add(a.getOperator_id());
            if (a.getAuthorizer_id() != null) ids.add(a.getAuthorizer_id());
        }
        if (ids.isEmpty()) return index;
        List<Admin> admins = adminMapper.selectBatchIds(ids);
        if (admins != null) {
            for (Admin admin : admins) {
                if (admin != null && admin.getId() != null) index.put(admin.getId(), admin);
            }
        }
        return index;
    }

    private Map<String, Object> approvalToMap(AccessApproval a, Map<Integer, Admin> adminIndex) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", a.getId());
        m.put("approvalNo", a.getApproval_no());
        m.put("permissionCode", a.getPermission_code());
        m.put("operatorId", a.getOperator_id());
        m.put("authorizerId", a.getAuthorizer_id());
        m.put("shopId", a.getShop_id());
        m.put("bizType", a.getBiz_type());
        m.put("bizId", a.getBiz_id());
        m.put("amount", a.getAmount());
        m.put("reason", a.getReason());
        m.put("authMethod", a.getAuth_method());
        m.put("bindingVersion", a.getBinding_version() != null ? a.getBinding_version() : 1);
        m.put("legacyBinding", a.getBinding_version() == null || a.getBinding_version() < 2);
        m.put("status", a.getStatus());
        m.put("expiresAt", a.getExpires_at());
        m.put("consumedAt", a.getConsumed_at());
        m.put("requestId", a.getRequest_id());
        m.put("terminalId", a.getTerminal_id());
        m.put("createdAt", a.getCreated_at());
        fillPerson(m, "operator", a.getOperator_id(), adminIndex);
        fillPerson(m, "authorizer", a.getAuthorizer_id(), adminIndex);
        return m;
    }

    private void fillPerson(Map<String, Object> m, String prefix, Integer adminId, Map<Integer, Admin> adminIndex) {
        if (adminId == null) return;
        Admin admin = adminIndex.get(adminId);
        if (admin == null) return;
        String name = admin.getRealName() != null ? admin.getRealName() : admin.getUserName();
        m.put(prefix + "Name", name);
        m.put(prefix + "WorkNo", admin.getWorkNo());
    }

    // ---------------- 权限解释 ----------------

    public Map<String, Object> evaluate(int userId, Integer shopId, String permission) {
        return evaluate(userId, shopId, permission, Collections.emptyMap());
    }

    public Map<String, Object> evaluate(int userId, Integer shopId, String permission, Map<String, Object> context) {
        if (StringUtil.isEmpty(permission)) {
            throw new ApiException(400, ERROR_VALIDATION, "permission 不能为空");
        }
        AccessContext.AccessContextBuilder builder = AccessContext.builder()
                .adminId(userId)
                .shopId(shopId)
                .permissionCode(permission);

        Map<String, Object> safeContext = context != null ? context : Collections.emptyMap();
        if (safeContext.get("amount") != null) {
            try {
                builder.amount(new BigDecimal(safeContext.get("amount").toString()));
            } catch (Exception ignore) {}
        }
        if (safeContext.get("discountRate") != null) {
            try {
                builder.discountRate(new BigDecimal(safeContext.get("discountRate").toString()));
            } catch (Exception ignore) {}
        }
        if (safeContext.get("resourceType") != null) {
            builder.resourceType(String.valueOf(safeContext.get("resourceType")));
        }
        if (safeContext.get("resourceId") != null) {
            builder.resourceId(String.valueOf(safeContext.get("resourceId")));
        }
        if (safeContext.get("terminalId") != null) {
            builder.terminalId(String.valueOf(safeContext.get("terminalId")));
        }
        if (safeContext.get("approvalToken") != null) {
            builder.approvalToken(String.valueOf(safeContext.get("approvalToken")));
        }

        AccessDecision decision = accessDecisionService.evaluate(builder.build());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("userId", userId);
        out.put("shopId", shopId);
        out.put("permission", permission);
        out.put("outcome", decision.getOutcome().name());
        out.put("allow", decision.isAllow());
        out.put("permissionGranted", decision.isPermissionGranted());
        out.put("shopInScope", decision.isShopInScope());
        out.put("policyPassed", decision.isPolicyPassed());
        out.put("approvalRequired", decision.isApprovalRequired());
        out.put("reasonCode", decision.getReasonCode());
        out.put("explanation", decision.getExplanation());
        out.put("matchedRoles", decision.getMatchedRoles() != null ? decision.getMatchedRoles() : Collections.emptyList());
        out.put("matchedPolicies", decision.getMatchedPolicies() != null ? decision.getMatchedPolicies() : Collections.emptyList());
        out.put("approval", decision.getApproval());
        return out;
    }

    private Map<String, Object> evaluateLegacy(int userId, Integer shopId, String permission) {
        if (StringUtil.isEmpty(permission)) {
            throw new ApiException(400, ERROR_VALIDATION, "permission 不能为空");
        }
        Admin admin = adminMapper.selectById(userId);
        if (admin == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "管理员不存在: " + userId);
        }
        Set<String> codes = adminPermissionService.getPermissionCodesByAdminId(userId);
        boolean allow = codes != null && codes.contains(permission);

        List<Role> boundRoles = rolesByAdmin(Collections.singletonList(userId))
                .getOrDefault(userId, Collections.emptyList());
        Set<Integer> boundIds = boundRoles.stream().map(Role::getId).collect(Collectors.toSet());
        List<Map<String, Object>> matchedRoles = new ArrayList<>();
        Integer priority = null;
        if (!boundIds.isEmpty()) {
            List<Permission> perms = permissionMapper.selectList(
                    new QueryWrapper<Permission>().eq("permission_code", permission));
            if (!perms.isEmpty()) {
                Integer permissionId = perms.get(0).getId();
                List<RolePermission> grants = rolePermissionMapper.selectList(
                        new QueryWrapper<RolePermission>().eq("permission_id", permissionId));
                for (Role role : boundRoles) {
                    boolean grantsIt = grants.stream().anyMatch(rp -> rp.getRole_id().equals(role.getId()));
                    if (grantsIt) {
                        Map<String, Object> m = new LinkedHashMap<>();
                        m.put("id", role.getId());
                        m.put("roleCode", role.getRole_code());
                        m.put("roleName", role.getRole_name());
                        matchedRoles.add(m);
                        if (priority == null || (role.getSort_order() != null && role.getSort_order() < priority)) {
                            priority = role.getSort_order();
                        }
                    }
                }
            }
        }

        boolean shopInScope = true;
        if (shopId != null) {
            shopInScope = adminShopAccessService.resolveScope(userId) == com.lanf.constant.AdminDataScope.HQ
                    || (adminShopAccessService.listAccessibleShopIds(userId) != null
                    && adminShopAccessService.listAccessibleShopIds(userId).contains(shopId));
        }
        boolean effectiveAllow = allow && shopInScope;

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("userId", userId);
        out.put("shopId", shopId);
        out.put("permission", permission);
        out.put("allow", effectiveAllow);
        out.put("permissionGranted", allow);
        out.put("shopInScope", shopInScope);
        out.put("matchedRoles", matchedRoles);
        out.put("priority", priority);
        out.put("rule", "deny-wins-on-same-priority");
        out.put("explanation", !allow ? "no role grants this permission"
                : (!shopInScope ? "shop out of admin scope" : "granted by matched roles"));
        return out;
    }

    // ---------------- 内部工具 ----------------

    private Map<Integer, List<Role>> rolesByAdmin(List<Integer> adminIds) {
        if (adminIds.isEmpty()) return Collections.emptyMap();
        List<AdminRole> bindings = adminRoleMapper.selectList(new QueryWrapper<AdminRole>().in("admin_id", adminIds));
        if (bindings.isEmpty()) return Collections.emptyMap();
        List<Integer> roleIds = bindings.stream().map(AdminRole::getRole_id).distinct().collect(Collectors.toList());
        Map<Integer, Role> roleMap = roleMapper.selectBatchIds(roleIds).stream().collect(Collectors.toMap(Role::getId, r -> r, (a, b) -> a));
        Map<Integer, List<Role>> out = new LinkedHashMap<>();
        for (AdminRole b : bindings) {
            Role role = roleMap.get(b.getRole_id());
            if (role != null) {
                out.computeIfAbsent(b.getAdmin_id(), k -> new ArrayList<>()).add(role);
            }
        }
        return out;
    }

    private Map<Integer, List<Integer>> shopsByAdmin(List<Integer> adminIds) {
        if (adminIds.isEmpty()) return Collections.emptyMap();
        List<AdminShop> bindings = adminShopMapper.selectList(new QueryWrapper<AdminShop>().in("admin_id", adminIds));
        Map<Integer, List<Integer>> out = new LinkedHashMap<>();
        for (AdminShop b : bindings) {
            out.computeIfAbsent(b.getAdmin_id(), k -> new ArrayList<>()).add(b.getShop_id());
        }
        return out;
    }

    private Role requireRole(int roleId) {
        Role role = roleMapper.selectById(roleId);
        if (role == null) {
            throw new ApiException(404, ERROR_NOT_FOUND, "角色不存在: " + roleId);
        }
        return role;
    }

    private Map<String, Object> roleView(Role role) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", role.getId());
        m.put("roleCode", role.getRole_code());
        m.put("roleName", role.getRole_name());
        m.put("remark", role.getRemark());
        m.put("sortOrder", role.getSort_order());
        m.put("version", role.getVersion());
        m.put("roleType", role.getRole_type() != null ? role.getRole_type() : Role.TYPE_CUSTOM);
        m.put("editable", role.getEditable() != null ? role.getEditable() : 1);
        m.put("systemProtected", role.getSystem_protected() != null ? role.getSystem_protected() : 0);
        m.put("priority", role.getPriority() != null ? role.getPriority() : 100);
        return m;
    }

    private String text(Object o) {
        return o == null ? null : String.valueOf(o).trim();
    }

    private Map<String, Object> pageResult(int page, int pageSize, int total, List<?> items) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("page", page);
        out.put("pageSize", pageSize);
        out.put("total", total);
        out.put("items", items);
        return out;
    }
}
