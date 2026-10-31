package com.lanf.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.controller.admin.AdminMemberController;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.controller.admin.AdminUserController;
import com.lanf.entity.Order;
import com.lanf.entity.PageBean;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.UserMapper;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IOrderService;
import com.lanf.service.IUserService;
import com.lanf.service.impl.IUserServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

public class AdminMemberStoreIsolationTest {

    private AdminOrderController adminOrderController;
    private AdminMemberController adminMemberController;
    private AdminUserController adminUserController;
    private IUserService userService;
    private IOrderService orderService;
    private UserMapper userMapper;
    private AdminShopScopeGuard adminShopScopeGuard;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        adminOrderController = new AdminOrderController();
        adminMemberController = new AdminMemberController();
        adminUserController = new AdminUserController();

        userService = mock(IUserService.class);
        orderService = mock(IOrderService.class);
        adminShopScopeGuard = mock(AdminShopScopeGuard.class);
        request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(adminOrderController, "UserService", userService);
        ReflectionTestUtils.setField(adminOrderController, "adminShopScopeGuard", adminShopScopeGuard);
        ReflectionTestUtils.setField(adminOrderController, "httpServletRequest", request);

        ReflectionTestUtils.setField(adminMemberController, "userService", userService);
        ReflectionTestUtils.setField(adminMemberController, "orderService", orderService);
        ReflectionTestUtils.setField(adminMemberController, "adminShopScopeGuard", adminShopScopeGuard);
        ReflectionTestUtils.setField(adminMemberController, "httpServletRequest", request);
        ReflectionTestUtils.setField(adminMemberController, "adminOrderController", adminOrderController);

        ReflectionTestUtils.setField(adminUserController, "userService", userService);
        ReflectionTestUtils.setField(adminUserController, "adminShopScopeGuard", adminShopScopeGuard);
        ReflectionTestUtils.setField(adminUserController, "httpServletRequest", request);
    }

    @Test
    void testGetAllUser_WithStoreId_FiltersByStore() {
        PageBean pageBean = new PageBean();
        pageBean.setPageNum(1);
        pageBean.setPageSize(10);
        pageBean.setShopId(5);

        doAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 5;
            return null;
        }).when(adminShopScopeGuard).resolveTargetShopId(eq(5), any(int[].class));

        Page<User> mockPage = new Page<>(1, 10);
        when(userService.pageUserList(1, 10, null, 5)).thenReturn(mockPage);

        R r = adminOrderController.getAllUser(pageBean);
        assertEquals(0, r.get("code"));
        verify(userService, times(1)).pageUserList(1, 10, null, 5);
    }

    @Test
    void testGetAllUser_WithAllShops_AllowsHQ() {
        PageBean pageBean = new PageBean();
        pageBean.setPageNum(1);
        pageBean.setPageSize(10);
        pageBean.setAllShops(true);

        when(adminShopScopeGuard.requireHeadquarters()).thenReturn(null);

        Page<User> mockPage = new Page<>(1, 10);
        when(userService.pageUserList(1, 10, null, null)).thenReturn(mockPage);

        R r = adminOrderController.getAllUser(pageBean);
        assertEquals(0, r.get("code"));
        verify(userService, times(1)).pageUserList(1, 10, null, null);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testGetUserInfo_WithExplicitShopId_PassesShopFilterAndStats() {
        Map<String, Object> body = new HashMap<>();
        body.put("shopId", 5);
        body.put("page", 1);
        body.put("limit", 20);

        doAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 5;
            return null;
        }).when(adminShopScopeGuard).resolveTargetShopId(eq(5), any(int[].class));

        Map<String, Object> mockResult = new HashMap<>();
        mockResult.put("records", Collections.emptyList());
        mockResult.put("total", 10L);
        when(userService.pageUserListWithStats(anyMap())).thenReturn(mockResult);

        R r = adminOrderController.getUserInfo(body);
        assertEquals(0, r.get("code"));

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(userService).pageUserListWithStats(captor.capture());
        Map<String, Object> params = captor.getValue();
        assertEquals(5, params.get("shopId"));
        assertEquals(true, params.get("includeStats"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void testGetUserInfo_ViaHeaderXShopId_PassesShopFilter() {
        Map<String, Object> body = new HashMap<>();
        body.put("page", 1);
        body.put("limit", 20);

        request.setAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID, 3);
        doAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 3;
            return null;
        }).when(adminShopScopeGuard).resolveTargetShopId(eq(3), any(int[].class));

        Map<String, Object> mockResult = new HashMap<>();
        mockResult.put("records", Collections.emptyList());
        mockResult.put("total", 5L);
        when(userService.pageUserListWithStats(anyMap())).thenReturn(mockResult);

        R r = adminOrderController.getUserInfo(body);
        assertEquals(0, r.get("code"));

        ArgumentCaptor<Map<String, Object>> captor = ArgumentCaptor.forClass(Map.class);
        verify(userService).pageUserListWithStats(captor.capture());
        Map<String, Object> params = captor.getValue();
        assertEquals(3, params.get("shopId"));
        assertEquals(true, params.get("includeStats"));
    }

    @Test
    void testAdminMemberList_DelegatesToGetUserInfo() {
        Map<String, Object> body = new HashMap<>();
        body.put("shopId", 5);

        doAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 5;
            return null;
        }).when(adminShopScopeGuard).resolveTargetShopId(eq(5), any(int[].class));

        Map<String, Object> mockResult = new HashMap<>();
        mockResult.put("records", Collections.emptyList());
        mockResult.put("total", 2L);
        when(userService.pageUserListWithStats(anyMap())).thenReturn(mockResult);

        R r = adminMemberController.memberList(body);
        assertEquals(0, r.get("code"));
    }

    @Test
    void testAdminUserStats_StoreIsolation() {
        doAnswer(invocation -> {
            int[] holder = invocation.getArgument(1);
            holder[0] = 5;
            return null;
        }).when(adminShopScopeGuard).resolveTargetShopId(eq(5), any(int[].class));

        when(userService.getSevenDaysUser(5)).thenReturn(new ArrayList<>());
        when(userService.getThisMonthUser(5)).thenReturn(new ArrayList<>());

        R r7 = adminUserController.sevenDays(5, null);
        assertEquals(0, r7.get("code"));
        verify(userService).getSevenDaysUser(5);

        R rMonth = adminUserController.thisMonth(5, null);
        assertEquals(0, rMonth.get("code"));
        verify(userService).getThisMonthUser(5);
    }

    @Test
    @SuppressWarnings("unchecked")
    void testIUserServiceImpl_ApplyShopMemberFilter_BuildsSubqueries() {
        IUserServiceImpl service = new IUserServiceImpl();
        QueryWrapper<User> qw = new QueryWrapper<>();

        ReflectionTestUtils.invokeMethod(service, "applyShopMemberFilter", qw, 5);
        String sqlSegment = qw.getSqlSegment();
        assertNotNull(sqlSegment);
        assertTrue(sqlSegment.contains("t_order"));
        assertTrue(sqlSegment.contains("t_member_recharge"));
        assertTrue(sqlSegment.contains("t_shop_member_wallet"));
        assertTrue(sqlSegment.contains("5"));
    }
}
