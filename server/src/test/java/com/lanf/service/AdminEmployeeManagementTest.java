package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.constant.AdminDataScope;
import com.lanf.controller.admin.AdminController;
import com.lanf.entity.Admin;
import com.lanf.entity.R;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.security.JwtTokenService;
import com.lanf.security.SecurityAuditService;
import com.lanf.util.AdminNameResolver;
import com.lanf.util.AdminPasswordUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class AdminEmployeeManagementTest {

    private AdminJwtLoginService loginService;
    private IAdminService adminService;
    private IAdminPermissionService adminPermissionService;
    private AdminRoleMapper adminRoleMapper;
    private RoleMapper roleMapper;
    private IAdminShopAccessService adminShopAccessService;
    private JwtTokenService jwtTokenService;

    @BeforeEach
    void setUp() {
        loginService = new AdminJwtLoginService();
        adminService = mock(IAdminService.class);
        adminPermissionService = mock(IAdminPermissionService.class);
        adminRoleMapper = mock(AdminRoleMapper.class);
        roleMapper = mock(RoleMapper.class);
        adminShopAccessService = mock(IAdminShopAccessService.class);
        jwtTokenService = mock(JwtTokenService.class);

        ReflectionTestUtils.setField(loginService, "adminService", adminService);
        ReflectionTestUtils.setField(loginService, "adminPermissionService", adminPermissionService);
        ReflectionTestUtils.setField(loginService, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(loginService, "roleMapper", roleMapper);
        ReflectionTestUtils.setField(loginService, "adminShopAccessService", adminShopAccessService);
        ReflectionTestUtils.setField(loginService, "jwtTokenService", jwtTokenService);

        when(adminShopAccessService.resolveScope(any())).thenReturn(AdminDataScope.HQ);
        when(adminShopAccessService.listAccessibleShops(any())).thenReturn(Collections.emptyList());
        when(jwtTokenService.createToken(any(), any(), anyLong(), any())).thenReturn("mock_token");
    }

    @Test
    @DisplayName("AdminNameResolver: 有 realName 返回 realName，否则返回 userName")
    void testAdminNameResolver() {
        Admin adminWithReal = new Admin();
        adminWithReal.setUserName("cashier01");
        adminWithReal.setRealName("张三");
        assertEquals("张三", AdminNameResolver.resolveDisplayName(adminWithReal));

        Admin adminWithoutReal = new Admin();
        adminWithoutReal.setUserName("admin");
        adminWithoutReal.setRealName(null);
        assertEquals("admin", AdminNameResolver.resolveDisplayName(adminWithoutReal));

        Admin adminWithEmptyReal = new Admin();
        adminWithEmptyReal.setUserName("admin");
        adminWithEmptyReal.setRealName("   ");
        assertEquals("admin", AdminNameResolver.resolveDisplayName(adminWithEmptyReal));

        assertNull(AdminNameResolver.resolveDisplayName(null));
    }

    @Test
    @DisplayName("采用工号(workNo)登录成功，返回工号、姓名、岗位和显示名称")
    void testLoginWithWorkNo() {
        Admin stored = new Admin();
        stored.setId(10);
        stored.setUserName("emp_user");
        stored.setWorkNo("EMP001");
        stored.setRealName("李四");
        stored.setJobTitle("收银主管");
        stored.setPassword(AdminPasswordUtil.encode("123456"));

        when(adminService.getOne(any(QueryWrapper.class))).thenReturn(stored);

        Admin loginParam = new Admin();
        loginParam.setWorkNo("EMP001");
        loginParam.setPassword("123456");

        R r = loginService.login(loginParam);
        assertEquals(0, r.get("code"));

        assertEquals("mock_token", r.get("token"));
        assertEquals(10, r.get("adminId"));
        assertEquals("emp_user", r.get("userName"));
        assertEquals("EMP001", r.get("workNo"));
        assertEquals("李四", r.get("realName"));
        assertEquals("收银主管", r.get("jobTitle"));
        assertEquals("李四", r.get("name"));
        assertEquals("李四", r.get("displayName"));
    }

    @Test
    @DisplayName("向后兼容：历史用户名(userName)登录成功")
    void testLoginWithUserNameFallback() {
        Admin stored = new Admin();
        stored.setId(1);
        stored.setUserName("admin");
        stored.setWorkNo("ROOT01");
        stored.setRealName("超级管理员");
        stored.setJobTitle("系统管理");
        stored.setPassword(AdminPasswordUtil.encode("admin123"));

        when(adminService.getOne(any(QueryWrapper.class))).thenReturn(stored);

        Admin loginParam = new Admin();
        loginParam.setUserName("admin");
        loginParam.setPassword("admin123");

        R r = loginService.login(loginParam);
        assertEquals(0, r.get("code"));

        assertEquals("超级管理员", r.get("displayName"));
        assertEquals("ROOT01", r.get("workNo"));
    }

    @Test
    @DisplayName("创建管理员支持工号唯一性校验与员工信息写入")
    void testCreateAdministrator() {
        AdminController controller = new AdminController();
        IAdminService mockAdminService = mock(IAdminService.class);
        SecurityAuditService mockAudit = mock(SecurityAuditService.class);
        ReflectionTestUtils.setField(controller, "adminService", mockAdminService);
        ReflectionTestUtils.setField(controller, "securityAuditService", mockAudit);
        ReflectionTestUtils.setField(controller, "currentRequest", mock(HttpServletRequest.class));

        // 模拟工号已存在
        Admin existing = new Admin();
        existing.setId(99);
        existing.setWorkNo("EMP002");
        when(mockAdminService.getOne(argThat(qw -> qw != null && qw.getSqlSegment() != null && qw.getSqlSegment().contains("work_no"))))
                .thenReturn(existing);

        Map<String, Object> req = new HashMap<>();
        req.put("userName", "new_user");
        req.put("password", "pass123");
        req.put("workNo", "EMP002");

        R res = controller.createAdministrator(req);
        assertNotEquals(0, res.get("code"));
        assertTrue(res.get("msg").toString().contains("工号已存在"));
    }

    @Test
    @DisplayName("更新管理员/员工资料支持工号唯一性校验")
    void testUpdateAdministrator() {
        AdminController controller = new AdminController();
        IAdminService mockAdminService = mock(IAdminService.class);
        SecurityAuditService mockAudit = mock(SecurityAuditService.class);
        ReflectionTestUtils.setField(controller, "adminService", mockAdminService);
        ReflectionTestUtils.setField(controller, "securityAuditService", mockAudit);
        ReflectionTestUtils.setField(controller, "currentRequest", mock(HttpServletRequest.class));

        Admin admin = new Admin();
        admin.setId(5);
        admin.setUserName("waiter01");
        when(mockAdminService.getById(5)).thenReturn(admin);

        Map<String, Object> req = new HashMap<>();
        req.put("workNo", "EMP005");
        req.put("realName", "王五");
        req.put("jobTitle", "前厅服务员");

        R res = controller.updateAdministrator(5, req);
        assertEquals(0, res.get("code"));
        assertEquals("EMP005", admin.getWorkNo());
        assertEquals("王五", admin.getRealName());
        assertEquals("前厅服务员", admin.getJobTitle());
        verify(mockAdminService).updateById(admin);
    }
}
