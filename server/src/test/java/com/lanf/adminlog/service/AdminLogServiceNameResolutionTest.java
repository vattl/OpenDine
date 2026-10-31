package com.lanf.adminlog.service;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Admin;
import com.lanf.entity.OperationLog;
import com.lanf.entity.Shop;
import com.lanf.service.IAdminService;
import com.lanf.service.IOperationLogService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * D030 日志名称回填：/admin/logs 返回项 adminName/shopName 由 t_admin/t_shop 批量解析。
 */
class AdminLogServiceNameResolutionTest {

    private AdminLogService logService;
    private IOperationLogService operationLogService;
    private IAdminService adminService;
    private IShopService shopService;

    private OperationLog row(Integer adminId, Integer shopId) {
        OperationLog r = new OperationLog();
        r.setId(1L);
        r.setShop_id(shopId);
        r.setModule("order");
        r.setAction("force_delete");
        r.setAdmin_id(adminId);
        r.setCreated_at(new Date());
        r.setResult_status("SUCCESS");
        return r;
    }

    private Page<OperationLog> pageOf(List<OperationLog> rows) {
        Page<OperationLog> p = new Page<>(1, 20);
        p.setTotal(rows.size());
        p.setRecords(rows);
        return p;
    }

    @BeforeEach
    void setUp() {
        operationLogService = mock(IOperationLogService.class);
        adminService = mock(IAdminService.class);
        shopService = mock(IShopService.class);
        logService = new AdminLogService();
        ReflectionTestUtils.setField(logService, "operationLogService", operationLogService);
        ReflectionTestUtils.setField(logService, "objectMapper", new ObjectMapper());
        ReflectionTestUtils.setField(logService, "adminService", adminService);
        ReflectionTestUtils.setField(logService, "shopService", shopService);
    }

    @Test
    @DisplayName("queryLogs 返回项带 adminName/shopName")
    void queryLogsResolvesNames() {
        when(operationLogService.page(any(), any())).thenReturn(
                pageOf(Arrays.asList(row(7, 3), row(2, null))));
        Admin a = new Admin();
        a.setId(7);
        a.setUserName("root");
        when(adminService.listByIds(anyCollection())).thenReturn(Collections.singletonList(a));
        Shop s = new Shop();
        s.setId(3);
        s.setName("旗舰店");
        when(shopService.listByIds(anyCollection())).thenReturn(Collections.singletonList(s));

        Map<String, Object> out = logService.queryLogs(1, null, null, null, null, null, 1, 20);
        List<Map<String, Object>> items = (List<Map<String, Object>>) out.get("items");
        assertEquals(2, items.size());
        assertEquals("root", items.get(0).get("adminName"));
        assertEquals("旗舰店", items.get(0).get("shopName"));
        // 无 admin_id/shop_id 的行返回 null 而非报错
        assertNull(items.get(1).get("adminName"));
        assertNull(items.get(1).get("shopName"));
    }

    @Test
    @DisplayName("服务缺失时（如单测未注入）联查静默跳过，不 NPE")
    void missingServicesSkipGracefully() {
        logService = new AdminLogService();
        ReflectionTestUtils.setField(logService, "operationLogService", operationLogService);
        ReflectionTestUtils.setField(logService, "objectMapper", new ObjectMapper());
        when(operationLogService.page(any(), any())).thenReturn(
                pageOf(Collections.singletonList(row(7, 3))));
        Map<String, Object> out = logService.queryLogs(1, null, null, null, null, null, 1, 20);
        List<Map<String, Object>> items = (List<Map<String, Object>>) out.get("items");
        assertEquals(1, items.size());
        assertNull(items.get(0).get("adminName"));
        assertNull(items.get(0).get("shopName"));
    }
}
