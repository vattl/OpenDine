package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.constant.AdminDataScope;
import com.lanf.constant.SystemConstant;
import com.lanf.entity.Admin;
import com.lanf.entity.AdminRole;
import com.lanf.entity.R;
import com.lanf.entity.Role;
import com.lanf.entity.Shop;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.security.JwtTokenService;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.AdminPasswordUtil;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 运营后台登录（密码 + JWT）；由根路径 {@code POST /adminLogin} 单独暴露，避免与 {@code @RequestMapping("/admin")} 叠前缀。
 */
@Service
public class AdminJwtLoginService {

    private static final Logger log = LoggerFactory.getLogger(AdminJwtLoginService.class);

    @Autowired
    private IAdminService adminService;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private RoleMapper roleMapper;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;
    @Autowired
    private JwtTokenService jwtTokenService;

    public R login(Admin admin) {
        return login(admin, null);
    }

    public R login(Admin admin, javax.servlet.http.HttpServletRequest request) {
        if (admin == null) {
            return R.error();
        }
        String account = StringUtils.hasText(admin.getWorkNo()) ? admin.getWorkNo().trim() :
                (StringUtils.hasText(admin.getUserName()) ? admin.getUserName().trim() : null);
        if (StringUtil.isEmpty(account)) {
            return R.error("工号或用户名不能为空！");
        }
        if (StringUtil.isEmpty(admin.getPassword())) {
            return R.error("密码不能为空！");
        }

        Admin resultAdmin = null;
        if (StringUtils.hasText(admin.getWorkNo())) {
            resultAdmin = adminService.getOne(new QueryWrapper<Admin>().eq("work_no", admin.getWorkNo().trim()));
        }
        if (resultAdmin == null && StringUtils.hasText(admin.getUserName())) {
            // 兼容通过用户名输入框输入工号或用户名的情形
            resultAdmin = adminService.getOne(new QueryWrapper<Admin>().eq("work_no", admin.getUserName().trim()));
            if (resultAdmin == null) {
                resultAdmin = adminService.getOne(new QueryWrapper<Admin>().eq("userName", admin.getUserName().trim()));
            }
        }
        if (resultAdmin == null) {
            return R.error("用户名或者密码错误！");
        }

        // 账号状态检查
        String status = resultAdmin.getAccountStatus() != null ? resultAdmin.getAccountStatus() : Admin.STATUS_ACTIVE;
        if (Admin.STATUS_DISABLED.equals(status)) {
            return R.error(403, "账号已被停用，禁止登录");
        }
        if (Admin.STATUS_RESIGNED.equals(status)) {
            return R.error(403, "员工已离职，禁止登录");
        }
        if (Admin.STATUS_LOCKED.equals(status)
                && resultAdmin.getLockedUntil() != null && resultAdmin.getLockedUntil().after(new java.util.Date())) {
            return R.error(423, "账号已被锁定，请联系管理员或稍后重试");
        }

        if (!AdminPasswordUtil.matches(admin.getPassword(), resultAdmin.getPassword())) {
            int fails = (resultAdmin.getFailedLoginCount() != null ? resultAdmin.getFailedLoginCount() : 0) + 1;
            resultAdmin.setFailedLoginCount(fails);
            if (fails >= 5) {
                resultAdmin.setLockedUntil(new java.util.Date(System.currentTimeMillis() + 15 * 60 * 1000L)); // 锁定15分钟
                resultAdmin.setAccountStatus(Admin.STATUS_LOCKED);
            }
            adminService.updateById(resultAdmin);
            return R.error("用户名或者密码错误！");
        }

        // 登录成功重置失败计数并更新审计信息
        resultAdmin.setFailedLoginCount(0);
        resultAdmin.setLockedUntil(null);
        if (Admin.STATUS_LOCKED.equals(resultAdmin.getAccountStatus())) {
            resultAdmin.setAccountStatus(Admin.STATUS_ACTIVE);
        }
        resultAdmin.setLastLoginAt(new java.util.Date());
        if (request != null) {
            String ip = request.getHeader("X-Forwarded-For");
            if (!StringUtils.hasText(ip)) ip = request.getRemoteAddr();
            resultAdmin.setLastLoginIp(ip);
        }

        if (AdminPasswordUtil.needsUpgrade(resultAdmin.getPassword())) {
            resultAdmin.setPassword(AdminPasswordUtil.encode(admin.getPassword()));
        }
        adminService.updateById(resultAdmin);

        int tokenVersion = resultAdmin.getTokenVersion() == null ? 0 : resultAdmin.getTokenVersion();
        long permVersion = resultAdmin.getPermissionVersion() == null ? 1L : resultAdmin.getPermissionVersion();

        Map<String, Object> claims = new HashMap<>();
        claims.put("tokenVersion", tokenVersion);
        claims.put("permissionVersion", permVersion);

        String token = jwtTokenService.createToken(resultAdmin.getId().toString(), "admin", SystemConstant.JWT_TTL, claims);
        Set<String> permissions = null;
        try {
            permissions = adminPermissionService.getPermissionCodesByAdminId(resultAdmin.getId());
        } catch (Exception e) {
            log.warn("登录时获取权限列表异常，返回空列表：{}", e.getMessage());
        }

        Map<String, Object> resultMap = new HashMap<>();
        resultMap.put("token", token);
        resultMap.put("permissions", permissions == null ? Collections.emptyList() : permissions.stream().sorted().collect(Collectors.toList()));
        resultMap.put("adminId", resultAdmin.getId());
        resultMap.put("accountStatus", resultAdmin.getAccountStatus() != null ? resultAdmin.getAccountStatus() : Admin.STATUS_ACTIVE);
        resultMap.put("permissionVersion", permVersion);
        resultMap.put("isSuperAdmin", adminShopAccessService.isSuperAdmin(resultAdmin.getId()));
        resultMap.put("userName", resultAdmin.getUserName());
        resultMap.put("workNo", resultAdmin.getWorkNo());
        resultMap.put("work_no", resultAdmin.getWorkNo());
        resultMap.put("realName", resultAdmin.getRealName());
        resultMap.put("real_name", resultAdmin.getRealName());
        resultMap.put("jobTitle", resultAdmin.getJobTitle());
        resultMap.put("job_title", resultAdmin.getJobTitle());
        String displayName = AdminNameResolver.resolveDisplayName(resultAdmin);
        resultMap.put("name", displayName);
        resultMap.put("displayName", displayName);
        AdminDataScope scope = adminShopAccessService.resolveScope(resultAdmin.getId());
        resultMap.put("scope", scope.name());
        List<Shop> shops = adminShopAccessService.listAccessibleShops(resultAdmin.getId());
        resultMap.put("shops", adminShopAccessService.toShopSummaries(shops));
        // HQ/SHOP 契约下 regionIds 可为空；避免超级管理员无谓查询 t_admin_region（未跑 P3 建表时会报错）
        List<Integer> regionIds = scope == AdminDataScope.REGION
                ? adminShopAccessService.listAccessibleRegionIds(resultAdmin.getId())
                : Collections.emptyList();
        resultMap.put("regionIds", regionIds);
        // 角色编码与名称（一个管理员可关联多个角色）
        List<Map<String, Object>> roles = new ArrayList<>();
        try {
            List<AdminRole> adminRoles = adminRoleMapper.selectList(
                    new QueryWrapper<AdminRole>().eq("admin_id", resultAdmin.getId()));
            if (adminRoles != null && !adminRoles.isEmpty()) {
                List<Integer> roleIds = adminRoles.stream()
                        .map(AdminRole::getRole_id).distinct().collect(Collectors.toList());
                List<Role> roleList = roleMapper.selectBatchIds(roleIds);
                if (roleList != null) {
                    for (Role role : roleList) {
                        Map<String, Object> item = new HashMap<>();
                        item.put("roleCode", role.getRole_code());
                        item.put("roleName", role.getRole_name());
                        roles.add(item);
                    }
                }
            }
        } catch (Exception e) {
            log.warn("登录时获取角色列表异常，返回空列表：{}", e.getMessage());
        }
        resultMap.put("roles", roles);
        return R.ok(resultMap);
    }
}
