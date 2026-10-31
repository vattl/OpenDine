package com.lanf.controller.admin;

import com.lanf.entity.Admin;
import com.lanf.entity.R;
import com.lanf.service.AdminJwtLoginService;
import com.lanf.security.SecurityAuditService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;

/**
 * 登录单独保留根路径 {@code /adminLogin}，与拦截器白名单及历史客户端一致。
 */
@RestController
public class AdminLoginController {

    @Autowired
    private AdminJwtLoginService adminJwtLoginService;
    @Autowired
    private SecurityAuditService securityAuditService;

    @PostMapping("/adminLogin")
    public R adminLogin(@RequestBody Admin admin, HttpServletRequest request) {
        R result = adminJwtLoginService.login(admin, request);
        if (!(result.get("code") instanceof Number) || ((Number) result.get("code")).intValue() != 0) {
            securityAuditService.recordAccessDenied(
                    request, null, null, 401, "admin_login_failed", null);
        }
        return result;
    }
}
