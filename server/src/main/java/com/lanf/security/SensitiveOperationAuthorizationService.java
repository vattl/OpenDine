package com.lanf.security;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Admin;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.AdminPasswordUtil;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.Map;
import java.util.Set;

/**
 * 对高风险业务操作执行一次性的现场员工授权。
 *
 * <p>授权员工可以不同于当前登录收银员，但必须同时通过账号密码、操作权限和门店范围校验。
 * 本服务不签发或缓存任何授权令牌。</p>
 */
@Service
public class SensitiveOperationAuthorizationService {

    private static final String INVALID_CREDENTIALS = "员工账号或密码错误";

    private final IAdminService adminService;
    private final IAdminPermissionService permissionService;
    private final IAdminShopAccessService shopAccessService;

    public SensitiveOperationAuthorizationService(IAdminService adminService,
                                                  IAdminPermissionService permissionService,
                                                  IAdminShopAccessService shopAccessService) {
        this.adminService = adminService;
        this.permissionService = permissionService;
        this.shopAccessService = shopAccessService;
    }

    public Decision authorize(Map<String, Object> body,
                              String requiredPermission,
                              Integer shopId,
                              boolean requireSuperAdmin) {
        Credentials credentials = credentialsFrom(body);
        if (credentials == null) {
            return Decision.denied(401, "请输入授权员工账号和密码");
        }

        Admin admin = findByAccount(credentials.account);
        if (admin == null || !AdminPasswordUtil.matches(credentials.password, admin.getPassword())) {
            return Decision.denied(401, INVALID_CREDENTIALS);
        }

        Set<String> permissionCodes = permissionService.getPermissionCodesByAdminId(admin.getId());
        if (!StringUtils.hasText(requiredPermission)
                || permissionCodes == null
                || !permissionCodes.contains(requiredPermission)) {
            return Decision.denied(403, "授权员工无此操作权限");
        }

        Set<Integer> accessibleShopIds = shopAccessService.listAccessibleShopIds(admin.getId());
        if (shopId == null || accessibleShopIds == null || !accessibleShopIds.contains(shopId)) {
            return Decision.denied(403, "授权员工无当前门店权限");
        }

        if (requireSuperAdmin && !shopAccessService.isSuperAdmin(admin.getId())) {
            return Decision.denied(403, "该操作仅允许超级管理员授权");
        }
        return Decision.allowed(admin);
    }

    private Admin findByAccount(String account) {
        Admin admin = adminService.getOne(new QueryWrapper<Admin>().eq("work_no", account).last("LIMIT 1"));
        if (admin != null) {
            return admin;
        }
        return adminService.getOne(new QueryWrapper<Admin>().eq("userName", account).last("LIMIT 1"));
    }

    @SuppressWarnings("unchecked")
    private static Credentials credentialsFrom(Map<String, Object> body) {
        if (body == null || !(body.get("authorization") instanceof Map)) {
            return null;
        }
        Map<String, Object> authorization = (Map<String, Object>) body.get("authorization");
        Object accountValue = authorization.get("account");
        Object passwordValue = authorization.get("password");
        String account = accountValue == null ? null : accountValue.toString().trim();
        String password = passwordValue == null ? null : passwordValue.toString();
        if (!StringUtils.hasText(account) || !StringUtils.hasText(password)
                || account.length() > 128 || password.length() > 512) {
            return null;
        }
        return new Credentials(account, password);
    }

    private static final class Credentials {
        private final String account;
        private final String password;

        private Credentials(String account, String password) {
            this.account = account;
            this.password = password;
        }
    }

    public static final class Decision {
        private final boolean allowed;
        private final int code;
        private final String message;
        private final Admin admin;

        private Decision(boolean allowed, int code, String message, Admin admin) {
            this.allowed = allowed;
            this.code = code;
            this.message = message;
            this.admin = admin;
        }

        public static Decision allowed(Admin admin) {
            return new Decision(true, 0, null, admin);
        }

        public static Decision denied(int code, String message) {
            return new Decision(false, code, message, null);
        }

        public boolean isAllowed() {
            return allowed;
        }

        public int getCode() {
            return code;
        }

        public String getMessage() {
            return message;
        }

        public Admin getAdmin() {
            return admin;
        }
    }
}
