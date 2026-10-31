package com.lanf.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.adminlog.service.AdminLogService;
import com.lanf.controller.cashier.CashierShiftController;
import com.lanf.entity.Admin;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.OperationLog;
import com.lanf.entity.R;
import com.lanf.entity.Shift;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.service.impl.DrawerSessionServiceImpl;
import com.lanf.util.AdminShopRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import javax.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.util.*;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class OperatorDisplayNameTest {

    @Test
    @DisplayName("DrawerSession: 班次报告与交班操作人显示为真实姓名")
    void testDrawerSessionOperatorRealName() {
        DrawerSessionServiceImpl drawerService = spy(new DrawerSessionServiceImpl());
        IAdminService adminService = mock(IAdminService.class);
        ReflectionTestUtils.setField(drawerService, "adminService", adminService);

        Admin opener = new Admin();
        opener.setId(101);
        opener.setUserName("op_user");
        opener.setRealName("张晓明");
        when(adminService.getById(101)).thenReturn(opener);

        Admin closer = new Admin();
        closer.setId(102);
        closer.setUserName("cl_user");
        closer.setRealName("李店长");
        when(adminService.getById(102)).thenReturn(closer);

        DrawerSession session = new DrawerSession();
        session.setId(1L);
        session.setSession_no("DS20261004001");
        session.setShop_id(1);
        session.setTerminal_id("T01");
        session.setDrawer_code("MAIN");
        session.setState(DrawerSession.STATE_CLOSED);
        session.setOpened_by(101);
        session.setClosed_by(102);
        session.setApproved_by(102);
        session.setOpening_float_fen(10000);
        session.setExpected_cash_fen(10000);
        session.setCounted_cash_fen(10000);
        session.setVariance_fen(0);
        session.setOpened_at(new Date());
        session.setClosed_at(new Date());

        doReturn(session).when(drawerService).getById(1L);
        doReturn(Collections.emptyList()).when(drawerService).listMovements(1L);

        Map<String, Object> report = drawerService.getShiftSummaryReport(1L);
        assertNotNull(report);
        assertEquals("张晓明", report.get("operator_name"));
        assertEquals("张晓明", report.get("opened_by_name"));
        assertEquals("李店长", report.get("closed_by_name"));
        assertEquals("李店长", report.get("approved_by_name"));
    }

    @Test
    @DisplayName("AdminLogService: 日志查询返回项回填员工真实姓名")
    void testAdminLogOperatorRealName() {
        AdminLogService logService = new AdminLogService();
        IOperationLogService operationLogService = mock(IOperationLogService.class);
        IAdminService adminService = mock(IAdminService.class);
        ReflectionTestUtils.setField(logService, "operationLogService", operationLogService);
        ReflectionTestUtils.setField(logService, "adminService", adminService);
        ReflectionTestUtils.setField(logService, "objectMapper", new com.fasterxml.jackson.databind.ObjectMapper());

        OperationLog row = new OperationLog();
        row.setId(1L);
        row.setAdmin_id(88);
        row.setModule("order");
        row.setAction("refund");
        row.setResult_status("SUCCESS");
        row.setCreated_at(new Date());

        com.baomidou.mybatisplus.extension.plugins.pagination.Page<OperationLog> page =
                new com.baomidou.mybatisplus.extension.plugins.pagination.Page<>(1, 20);
        page.setRecords(Collections.singletonList(row));
        page.setTotal(1);

        when(operationLogService.page(any(), any())).thenReturn(page);

        Admin admin = new Admin();
        admin.setId(88);
        admin.setUserName("admin88");
        admin.setRealName("王小花");
        when(adminService.listByIds(anyCollection())).thenReturn(Collections.singletonList(admin));

        Map<String, Object> out = logService.queryLogs(1, null, null, null, null, null, 1, 20);
        List<Map<String, Object>> items = (List<Map<String, Object>>) out.get("items");
        assertEquals(1, items.size());
        assertEquals("王小花", items.get(0).get("adminName"));
        assertEquals("王小花", items.get(0).get("operator_name"));
    }

    @Test
    @DisplayName("CashierShiftController: /cashier/shift/current 返回操作人真实姓名")
    void testCashierShiftCurrentRealName() {
        CashierShiftController controller = new CashierShiftController();
        IShiftService shiftService = mock(IShiftService.class);
        DrawerSessionService drawerSessionService = mock(DrawerSessionService.class);
        IPaymentService paymentService = mock(IPaymentService.class);
        IAdminService adminService = mock(IAdminService.class);
        HttpServletRequest request = mock(HttpServletRequest.class);

        ReflectionTestUtils.setField(controller, "shiftService", shiftService);
        ReflectionTestUtils.setField(controller, "drawerSessionService", drawerSessionService);
        ReflectionTestUtils.setField(controller, "paymentService", paymentService);
        ReflectionTestUtils.setField(controller, "adminService", adminService);
        ReflectionTestUtils.setField(controller, "request", request);

        when(paymentService.list(any())).thenReturn(Collections.emptyList());

        when(request.getAttribute(SysInterceptor.ATTR_ADMIN_ID)).thenReturn(50);
        when(request.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID)).thenReturn(1);

        Admin admin = new Admin();
        admin.setId(50);
        admin.setUserName("cashier50");
        admin.setRealName("赵六");
        when(adminService.getById(50)).thenReturn(admin);

        Shift shift = new Shift();
        shift.setId(100L);
        shift.setAdmin_id(50);
        shift.setShop_id(1);
        shift.setStart_cash(BigDecimal.ZERO);
        shift.setStart_time(new Date());
        when(shiftService.getOne(any(QueryWrapper.class))).thenReturn(shift);

        R r = controller.current(false);
        assertEquals(0, r.get("code"));

        Shift resultShift = (Shift) r.get("shift");
        assertNotNull(resultShift);
        assertEquals("赵六", resultShift.getAdmin_name());
    }
}
