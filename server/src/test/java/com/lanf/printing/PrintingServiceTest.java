package com.lanf.printing;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.common.PageResult;
import com.lanf.printing.entity.PrintingDevice;
import com.lanf.printing.entity.PrintingJob;
import com.lanf.printing.entity.PrintingRule;
import com.lanf.printing.entity.PrintingTemplate;
import com.lanf.printing.mapper.PrintingDeviceMapper;
import com.lanf.printing.mapper.PrintingJobMapper;
import com.lanf.printing.mapper.PrintingRuleMapper;
import com.lanf.printing.mapper.PrintingTemplateMapper;
import com.lanf.printing.service.PrintingService;
import com.lanf.service.IFeieyunService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 打印模块服务单元测试：设备创建脱敏、版本冲突 409、测试任务 CLOUD/DEVICE 分流、任务列表分页、
 * 规则整体保存乐观锁、参数校验 400。
 */
class PrintingServiceTest {

    private PrintingService service;
    private PrintingDeviceMapper deviceMapper;
    private PrintingRuleMapper ruleMapper;
    private PrintingJobMapper jobMapper;
    private PrintingTemplateMapper templateMapper;
    private IFeieyunService feieyunService;

    @BeforeEach
    void setUp() {
        deviceMapper = mock(PrintingDeviceMapper.class);
        ruleMapper = mock(PrintingRuleMapper.class);
        jobMapper = mock(PrintingJobMapper.class);
        templateMapper = mock(PrintingTemplateMapper.class);
        feieyunService = mock(IFeieyunService.class);
        service = new PrintingService();
        ReflectionTestUtils.setField(service, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(service, "ruleMapper", ruleMapper);
        ReflectionTestUtils.setField(service, "jobMapper", jobMapper);
        ReflectionTestUtils.setField(service, "templateMapper", templateMapper);
        ReflectionTestUtils.setField(service, "feieyunService", feieyunService);
        ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
        // saveRules 校验规则引用的模板必须真实存在（validateRuleTemplate）
        PrintingTemplate anyTemplate = new PrintingTemplate();
        anyTemplate.setId(1L);
        anyTemplate.setShop_id(0);
        anyTemplate.setTemplate_code("tmpl_kitchen");
        when(templateMapper.selectOne(any())).thenReturn(anyTemplate);
    }

    // ---------------- 测试数据 ----------------

    private PrintingDevice device(long id, int shopId, String transport, String connectionJson, int version) {
        PrintingDevice d = new PrintingDevice();
        d.setId(id);
        d.setShop_id(shopId);
        d.setName("前台小票机");
        d.setTransport(transport);
        d.setBrand("飞鹅");
        d.setConnection_json(connectionJson);
        d.setStatus("UNKNOWN");
        d.setVersion(version);
        return d;
    }

    private PrintingRule rule(int shopId, String scenario, int version) {
        PrintingRule r = new PrintingRule();
        r.setId(31L);
        r.setShop_id(shopId);
        r.setScenario(scenario);
        r.setDevice_id(5L);
        r.setTemplate_code("tmpl_order");
        r.setCopies(1);
        r.setEnabled(1);
        r.setVersion(version);
        return r;
    }

    private PrintingJob job(long id, String status, String executor) {
        PrintingJob j = new PrintingJob();
        j.setId(id);
        j.setShop_id(1);
        j.setDevice_id(9L);
        j.setJob_type("order");
        j.setStatus(status);
        j.setExecutor(executor);
        j.setRetry_count(0);
        j.setPayload_text("==打印测试单==");
        return j;
    }

    private void stubInsertAssignsId() {
        when(jobMapper.insert(any(PrintingJob.class))).thenAnswer(inv -> {
            PrintingJob j = inv.getArgument(0);
            j.setId(101L);
            return 1;
        });
    }

    // ---------------- 设备创建与脱敏 ----------------

    @Test
    void createDeviceMasksSnAndKeyInResponseButStoresPlain() {
        Map<String, Object> connection = new LinkedHashMap<>();
        connection.put("ip", "192.168.1.9");
        connection.put("port", 9100);
        connection.put("sn", "987654321");
        connection.put("key", "abcdef88");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "前台小票机");
        body.put("transport", "cloud"); // 大小写不敏感，落库归一为 CLOUD
        body.put("brand", "飞鹅");
        body.put("connection", connection);
        java.util.concurrent.atomic.AtomicReference<PrintingDevice> inserted =
                new java.util.concurrent.atomic.AtomicReference<>();
        when(deviceMapper.insert(any(PrintingDevice.class))).thenAnswer(inv -> {
            PrintingDevice d = inv.getArgument(0);
            d.setId(9L);
            inserted.set(d);
            return 1;
        });

        Map<String, Object> device = service.createDevice(1, body, 7);

        assertEquals(9L, device.get("id"));
        assertEquals("CLOUD", device.get("transport"));
        assertEquals(1, device.get("version"));

        @SuppressWarnings("unchecked")
        Map<String, Object> masked = (Map<String, Object>) device.get("connection");
        assertEquals("987654321", masked.get("sn"), "sn 原样返回方便识别硬件");
        assertEquals("****", masked.get("key"), "密钥完全掩码");
        assertEquals("192.168.1.9", masked.get("ip"), "非敏感字段原样返回");
        assertEquals(9100, masked.get("port"));

        // 库内存明文，响应脱敏
        String stored = inserted.get().getConnection_json();
        assertTrue(stored.contains("987654321"));
        assertTrue(stored.contains("abcdef88"));
    }

    @Test
    void createDeviceRejectsInvalidTransport() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "后厨打印机");
        body.put("transport", "NFC");
        ApiException ex = assertThrows(ApiException.class, () -> service.createDevice(1, body, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_TRANSPORT_INVALID", ex.getErrorCode());
        verify(deviceMapper, never()).insert(any(PrintingDevice.class));
    }

    @Test
    void createDeviceRejectsMissingName() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("transport", "LAN");
        ApiException ex = assertThrows(ApiException.class, () -> service.createDevice(1, body, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_NAME_REQUIRED", ex.getErrorCode());
    }

    // ---------------- 设备更新版本冲突 ----------------

    @Test
    void updateDeviceConflictReturns409WithLatestSummary() {
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 1, "LAN", "{\"sn\":\"8888\"}", 3));
        when(deviceMapper.update(any(PrintingDevice.class), any())).thenReturn(0); // 乐观锁未命中

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "新名字");
        body.put("version", 2); // 过期版本

        ApiException ex = assertThrows(ApiException.class, () -> service.updateDevice(1, 5L, body, 7));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRINTING_VERSION_CONFLICT", ex.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertEquals(3, data.get("version"), "409 data 携带最新版本摘要");
        assertEquals(5L, data.get("deviceId"));
    }

    @Test
    void updateDeviceBumpsVersionWhenMatched() {
        PrintingDevice after = device(5L, 1, "LAN", "{\"sn\":\"8888\"}", 3);
        after.setName("新名字");
        when(deviceMapper.selectById(5L))
                .thenReturn(device(5L, 1, "LAN", "{\"sn\":\"8888\"}", 2)) // 更新前
                .thenReturn(after);                                       // 更新后重查
        when(deviceMapper.update(any(PrintingDevice.class), any())).thenReturn(1);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "新名字");
        body.put("version", 2);

        Map<String, Object> device = service.updateDevice(1, 5L, body, 7);
        assertEquals(3, device.get("version"));
        assertEquals("新名字", device.get("name"));

        ArgumentCaptor<PrintingDevice> patch = ArgumentCaptor.forClass(PrintingDevice.class);
        verify(deviceMapper).update(patch.capture(), any());
        assertEquals(3, patch.getValue().getVersion(), "更新实体携带 version+1 作为乐观锁");
    }

    @Test
    void updateDeviceRequiresVersion() {
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 1, "LAN", null, 2));
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "新名字");
        ApiException ex = assertThrows(ApiException.class, () -> service.updateDevice(1, 5L, body, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_VERSION_REQUIRED", ex.getErrorCode());
    }

    @Test
    void deviceOfOtherShopIs404() {
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 2, "LAN", null, 1)); // 别的门店
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", 1);
        ApiException ex = assertThrows(ApiException.class, () -> service.updateDevice(1, 5L, body, 7));
        assertEquals(404, ex.getHttpStatus());
        assertEquals("PRINTING_DEVICE_NOT_FOUND", ex.getErrorCode());
    }

    // ---------------- 打印测试：CLOUD / DEVICE 分流 ----------------

    @Test
    void testJobCloudCallsFeieyunAndMarksSent() throws Exception {
        when(deviceMapper.selectById(9L))
                .thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"key\":\"k\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        stubInsertAssignsId();
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), eq("12345678"), anyString(), eq(1)))
                .thenReturn("{\"ret\":0}");

        Map<String, Object> job = service.createTestJob(1, 9L, "order", 7);

        assertEquals(101L, job.get("jobId"));
        assertEquals("SENT", job.get("status"));
        assertEquals("CLOUD", job.get("executor"));
        verify(feieyunService).printWithCredential(anyString(), anyString(), anyString(), eq("12345678"), anyString(), eq(1));
    }

    @Test
    void testJobCloudFailureMarksFailedWithError() throws Exception {
        when(deviceMapper.selectById(9L))
                .thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        stubInsertAssignsId();
        when(feieyunService.printWithCredential(anyString(), anyString(), anyString(), eq("12345678"), anyString(), eq(1)))
                .thenThrow(new IOException("飞鹅云请求失败(ret=-1): 打印机不存在"));

        Map<String, Object> job = service.createTestJob(1, 9L, "order", 7);

        assertEquals("FAILED", job.get("status"));
        assertEquals("CLOUD", job.get("executor"));
        ArgumentCaptor<PrintingJob> inserted = ArgumentCaptor.forClass(PrintingJob.class);
        verify(jobMapper).insert(inserted.capture());
        assertTrue(inserted.getValue().getError().contains("飞鹅云请求失败"));
    }

    @Test
    void testJobCloudWithoutSnMarksNotConfigured() throws Exception {
        when(deviceMapper.selectById(9L))
                .thenReturn(device(9L, 1, "CLOUD", "{\"ip\":\"1.2.3.4\"}", 1));
        stubInsertAssignsId();

        Map<String, Object> job = service.createTestJob(1, 9L, "order", 7);

        assertEquals("FAILED", job.get("status"));
        assertEquals("CLOUD", job.get("executor"));
        assertEquals(PrintingService.CLOUD_NOT_CONFIGURED, job.get("error"));
        verify(feieyunService, never()).printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt());
    }

    @Test
    void testJobDeviceTransportStaysPendingDevice() throws Exception {
        when(deviceMapper.selectById(9L))
                .thenReturn(device(9L, 1, "BLUETOOTH", "{\"sn\":\"BT-0099\"}", 1));
        stubInsertAssignsId();

        Map<String, Object> job = service.createTestJob(1, 9L, "refund", 7);

        assertEquals("PENDING_DEVICE", job.get("status"), "LAN/USB/蓝牙任务等待端侧执行");
        assertEquals("DEVICE", job.get("executor"));
        assertEquals(101L, job.get("jobId"));
        verify(feieyunService, never()).printWithCredential(anyString(), anyString(), anyString(), anyString(), anyString(), anyInt());
        ArgumentCaptor<PrintingJob> inserted = ArgumentCaptor.forClass(PrintingJob.class);
        verify(jobMapper).insert(inserted.capture());
        assertEquals("refund", inserted.getValue().getJob_type());
        assertNull(inserted.getValue().getError());
    }

    @Test
    void testJobRejectsInvalidTestType() {
        when(deviceMapper.selectById(9L)).thenReturn(device(9L, 1, "LAN", null, 1));
        ApiException ex = assertThrows(ApiException.class,
                () -> service.createTestJob(1, 9L, "不合法 类型!", 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_TEST_TYPE_INVALID", ex.getErrorCode());
    }

    // ---------------- 任务列表分页 ----------------

    @Test
    void listJobsPaginatesAndMapsFields() {
        when(jobMapper.selectPage(any(), any())).thenAnswer(inv -> {
            Page<PrintingJob> page = inv.getArgument(0);
            page.setRecords(Arrays.asList(job(21L, "SENT", "CLOUD"), job(20L, "PENDING_DEVICE", "DEVICE")));
            page.setTotal(11);
            return page;
        });

        PageResult pr = service.listJobs(1, "SENT", 9L, "2026-01-01 00:00:00", "2026-01-31 23:59:59", 2, 5);

        assertEquals(2, pr.getPage());
        assertEquals(5, pr.getPageSize());
        assertEquals(11, pr.getTotal());
        assertEquals(2, pr.getItems().size());

        Map<String, Object> first = (Map<String, Object>) pr.getItems().get(0);
        assertEquals(21L, first.get("id"));
        assertEquals("SENT", first.get("status"));
        assertEquals("CLOUD", first.get("executor"));
        assertEquals(0, first.get("retryCount"));
    }

    @Test
    void listJobsCapsPageSize() {
        when(jobMapper.selectPage(any(), any())).thenAnswer(inv -> {
            Page<PrintingJob> page = inv.getArgument(0);
            page.setRecords(Collections.emptyList());
            page.setTotal(0);
            return page;
        });
        PageResult pr = service.listJobs(1, null, null, null, null, 1, 5000);
        assertEquals(100, pr.getPageSize(), "pageSize 上限 100");
    }

    @Test
    void listJobsRejectsUnknownStatus() {
        ApiException ex = assertThrows(ApiException.class,
                () -> service.listJobs(1, "REBOOTING", null, null, null, 1, 20));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_STATUS_INVALID", ex.getErrorCode());
    }

    @Test
    void listJobsRejectsInvalidTimeRange() {
        ApiException ex = assertThrows(ApiException.class,
                () -> service.listJobs(1, null, null, "昨天", null, 1, 20));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_TIME_INVALID", ex.getErrorCode());
    }

    // ---------------- 规则整体保存 ----------------

    @Test
    void saveRulesConflictReturns409WithLatestVersion() {
        when(ruleMapper.selectList(any()))
                .thenReturn(Collections.singletonList(rule(1, "order", 4)));

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", 3); // 过期
        body.put("rules", new java.util.ArrayList<>());

        ApiException ex = assertThrows(ApiException.class, () -> service.saveRules(1, body, 7));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("PRINTING_VERSION_CONFLICT", ex.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertEquals(4, data.get("version"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void saveRulesReplacesWholeListAndBumpsVersion() {
        java.util.concurrent.atomic.AtomicReference<PrintingRule> insertedRule =
                new java.util.concurrent.atomic.AtomicReference<>();
        when(ruleMapper.selectList(any()))
                .thenReturn(Collections.singletonList(rule(1, "order", 4)))  // 现有（整体版本 4）
                .thenAnswer(inv -> {                                          // 保存后 getRules 重查
                    PrintingRule r = insertedRule.get();
                    return r == null ? Collections.emptyList() : Collections.singletonList(r);
                });
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 1, "CLOUD", "{\"sn\":\"12345678\"}", 2));
        when(ruleMapper.insert(any(PrintingRule.class))).thenAnswer(inv -> {
            insertedRule.set(inv.getArgument(0));
            return 1;
        });

        Map<String, Object> ruleItem = new LinkedHashMap<>();
        ruleItem.put("scenario", "Kitchen"); // 归一为小写
        ruleItem.put("deviceId", 5);
        ruleItem.put("templateCode", "tmpl_kitchen");
        ruleItem.put("copies", 2);
        ruleItem.put("enabled", true);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", 4);
        body.put("rules", Collections.singletonList(ruleItem));

        Map<String, Object> result = service.saveRules(1, body, 7);

        assertEquals(5, result.get("version"), "整体版本 = 基准 + 1");
        List<Map<String, Object>> rules = (List<Map<String, Object>>) result.get("rules");
        assertEquals(1, rules.size());
        assertEquals("kitchen", rules.get(0).get("scenario"));
        assertEquals(Boolean.TRUE, rules.get(0).get("enabled"));
        verify(ruleMapper).delete(any());
        ArgumentCaptor<PrintingRule> inserted = ArgumentCaptor.forClass(PrintingRule.class);
        verify(ruleMapper).insert(inserted.capture());
        assertEquals(5, inserted.getValue().getVersion());
    }

    @Test
    void saveRulesRejectsForeignDevice() {
        when(ruleMapper.selectList(any()))
                .thenReturn(Collections.singletonList(rule(1, "order", 4)));
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 2, "LAN", null, 1)); // 别的门店

        Map<String, Object> ruleItem = new LinkedHashMap<>();
        ruleItem.put("scenario", "order");
        ruleItem.put("deviceId", 5);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", 4);
        body.put("rules", Collections.singletonList(ruleItem));

        ApiException ex = assertThrows(ApiException.class, () -> service.saveRules(1, body, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINTING_DEVICE_NOT_IN_SHOP", ex.getErrorCode());
    }

    // ---------------- 设备列表（脱敏出参） ----------------

    @Test
    void listDevicesFiltersAndMasksConnection() {
        when(deviceMapper.selectPage(any(), any())).thenAnswer(inv -> {
            Page<PrintingDevice> page = inv.getArgument(0);
            page.setRecords(Collections.singletonList(
                    device(5L, 1, "CLOUD", "{\"sn\":\"987654321\",\"key\":\"abcdef88\",\"ip\":\"10.0.0.2\"}", 1)));
            page.setTotal(1);
            return page;
        });

        PageResult pr = service.listDevices(1, "cloud", "unknown", 1, 20);

        assertEquals(1, pr.getPage());
        assertEquals(1, pr.getTotal());
        Map<String, Object> item = (Map<String, Object>) pr.getItems().get(0);
        Map<String, Object> connection = (Map<String, Object>) item.get("connection");
        assertEquals("987654321", connection.get("sn"));
        assertEquals("****", connection.get("key"));
        assertEquals("10.0.0.2", connection.get("ip"));
    }

    // ---------------- 设备详情与删除 ----------------

    @Test
    void getDeviceDetailReturnsMaskedFields() {
        when(deviceMapper.selectById(5L)).thenReturn(
            device(5L, 1, "CLOUD", "{\"sn\":\"987654321\",\"ukey\":\"REDACTED_ROTATE_CREDENTIAL\",\"apiUrl\":\"http://api.feieyun.cn\"}", 2));

        Map<String, Object> detail = service.getDeviceDetail(1, 5L);

        assertEquals(5L, detail.get("id"));
        assertEquals("前台小票机", detail.get("name"));
        assertEquals("CLOUD", detail.get("transport"));
        assertEquals("987654321", detail.get("sn"));
        assertEquals("REDA****TIAL", detail.get("ukey"));
        assertEquals("http://api.feieyun.cn", detail.get("apiUrl"));
    }

    @Test
    void deleteDeviceRejectsWhenInUseByEnabledRule() {
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 1, "LAN", null, 1));
        when(ruleMapper.selectList(any())).thenReturn(Collections.singletonList(rule(1, "kitchen", 1)));

        ApiException ex = assertThrows(ApiException.class, () -> service.deleteDevice(1, 5L));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("PRINT_DEVICE_IN_USE_BY_RULE", ex.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) ex.getData();
        assertNotNull(data.get("rules"));
        verify(deviceMapper, never()).deleteById(5L);
    }

    @Test
    void deleteDeviceSucceedsWhenNotInUse() {
        when(deviceMapper.selectById(5L)).thenReturn(device(5L, 1, "LAN", null, 1));
        when(ruleMapper.selectList(any())).thenReturn(Collections.emptyList());

        service.deleteDevice(1, 5L);
        verify(deviceMapper).deleteById(5L);
    }

    // ---------------- 探活与测试出票 ----------------

    @Test
    void probeDeviceStatusFeieyun() throws Exception {
        when(deviceMapper.selectById(9L)).thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        when(feieyunService.queryPrinterStatusWithCredential(anyString(), anyString(), anyString(), eq("12345678"))).thenReturn("{\"ret\":0,\"msg\":\"ok\",\"data\":\"在线，工作状态正常\"}");

        Map<String, Object> status = service.probeDeviceStatus(1, 9L);
        assertEquals(Boolean.TRUE, status.get("online"));
        assertEquals("ONLINE", status.get("status"));
        assertEquals("NORMAL", status.get("paperStatus"));
        assertEquals("CLOSED", status.get("coverStatus"));
    }

    @Test
    void probeDeviceStatusFeieyunStatusCode0Offline() throws Exception {
        when(deviceMapper.selectById(9L)).thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        when(feieyunService.queryPrinterStatusWithCredential(anyString(), anyString(), anyString(), eq("12345678"))).thenReturn("{\"ret\":0,\"msg\":\"ok\",\"data\":\"0\"}");

        Map<String, Object> status = service.probeDeviceStatus(1, 9L);
        assertEquals(Boolean.FALSE, status.get("online"));
        assertEquals("OFFLINE", status.get("status"));
    }

    @Test
    void probeDeviceStatusFeieyunStatusCode1Normal() throws Exception {
        when(deviceMapper.selectById(9L)).thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        when(feieyunService.queryPrinterStatusWithCredential(anyString(), anyString(), anyString(), eq("12345678"))).thenReturn("{\"ret\":0,\"msg\":\"ok\",\"data\":\"1\"}");

        Map<String, Object> status = service.probeDeviceStatus(1, 9L);
        assertEquals(Boolean.TRUE, status.get("online"));
        assertEquals("ONLINE", status.get("status"));
        assertEquals("NORMAL", status.get("paperStatus"));
    }

    @Test
    void probeDeviceStatusFeieyunStatusCode2Abnormal() throws Exception {
        when(deviceMapper.selectById(9L)).thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        when(feieyunService.queryPrinterStatusWithCredential(anyString(), anyString(), anyString(), eq("12345678"))).thenReturn("{\"ret\":0,\"msg\":\"ok\",\"data\":\"2\"}");

        Map<String, Object> status = service.probeDeviceStatus(1, 9L);
        assertEquals(Boolean.TRUE, status.get("online"));
        assertEquals("ERROR", status.get("status"));
    }

    @Test
    void probeDeviceStatusFeieyunOutOfPaper() throws Exception {
        when(deviceMapper.selectById(9L)).thenReturn(device(9L, 1, "CLOUD", "{\"sn\":\"12345678\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1));
        when(feieyunService.queryPrinterStatusWithCredential(anyString(), anyString(), anyString(), eq("12345678"))).thenReturn("{\"ret\":0,\"msg\":\"ok\",\"data\":\"在线，缺纸\"}");

        Map<String, Object> status = service.probeDeviceStatus(1, 9L);
        assertEquals(Boolean.TRUE, status.get("online"));
        assertEquals("ERROR", status.get("status"));
        assertEquals("OUT_OF_PAPER", status.get("paperStatus"));
    }

    @Test
    void updateDevicePreservesMaskedSecret() {
        PrintingDevice existing = device(5L, 1, "CLOUD", "{\"sn\":\"987654321\",\"ukey\":\"originalSecretKey123\"}", 1);
        when(deviceMapper.selectById(5L)).thenReturn(existing).thenReturn(existing);
        when(deviceMapper.update(any(), any())).thenReturn(1);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "修改后的打印机");
        body.put("ukey", "orig****y123"); // 传入掩码
        body.put("version", 1);

        service.updateDevice(1, 5L, body, 7);

        ArgumentCaptor<PrintingDevice> captor = ArgumentCaptor.forClass(PrintingDevice.class);
        verify(deviceMapper).update(captor.capture(), any());
        assertTrue(captor.getValue().getConnection_json().contains("originalSecretKey123"), "原始密钥被保留");
    }

    @Test
    void createAndGetDeviceWithTicketTypes() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "前台多功能小票机");
        body.put("transport", "CLOUD");
        body.put("vendor", "飞鹅云");
        body.put("sn", "924698188");
        body.put("user", "feie_printer@example.com");
        body.put("ukey", "REDACTED_ROTATE_CREDENTIAL");
        body.put("ticketTypes", Arrays.asList("FULL_ORDER", "PRE_CHECKOUT", "CHECKOUT"));

        java.util.concurrent.atomic.AtomicReference<PrintingDevice> inserted =
                new java.util.concurrent.atomic.AtomicReference<>();
        when(deviceMapper.insert(any(PrintingDevice.class))).thenAnswer(inv -> {
            PrintingDevice d = inv.getArgument(0);
            d.setId(88L);
            inserted.set(d);
            return 1;
        });

        Map<String, Object> device = service.createDevice(1, body, 7);
        assertEquals(88L, device.get("id"));
        @SuppressWarnings("unchecked")
        List<String> types = (List<String>) device.get("ticketTypes");
        assertNotNull(types);
        assertEquals(3, types.size());
        assertTrue(types.contains("FULL_ORDER"));
        assertTrue(types.contains("PRE_CHECKOUT"));
        assertTrue(types.contains("CHECKOUT"));

        // 验证持久化 JSON 包含 ticketTypes
        assertTrue(inserted.get().getConnection_json().contains("FULL_ORDER"));
    }

    @Test
    void listDevicesSupportsErrorStatusAndNormalizesTicketTypes() {
        when(deviceMapper.selectPage(any(), any())).thenAnswer(inv -> {
            Page<PrintingDevice> page = inv.getArgument(0);
            PrintingDevice d = device(12L, 1, "LAN", "{\"ip\":\"192.168.1.199\",\"port\":9100,\"ticketTypes\":\"KITCHEN,EXPEDITE\"}", 3);
            d.setStatus("ERROR");
            page.setRecords(Collections.singletonList(d));
            page.setTotal(1);
            return page;
        });

        PageResult pr = service.listDevices(1, "LAN", "ERROR", 1, 20);
        assertEquals(1, pr.getTotal());
        Map<String, Object> item = (Map<String, Object>) pr.getItems().get(0);
        assertEquals(12L, item.get("id"));
        assertEquals("ERROR", item.get("status"));
        assertEquals(3, item.get("version"));
        @SuppressWarnings("unchecked")
        List<String> types = (List<String>) item.get("ticketTypes");
        assertEquals(2, types.size());
        assertTrue(types.contains("KITCHEN"));
        assertTrue(types.contains("EXPEDITE"));
    }

    @Test
    void clearDeviceQueue_success() throws Exception {
        PrintingDevice dev = device(10L, 1, "CLOUD", "{\"sn\":\"987654321\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1);
        when(deviceMapper.selectById(10L)).thenReturn(dev);
        when(feieyunService.clearPrintQueueWithCredential(anyString(), anyString(), anyString(), eq("987654321"))).thenReturn("{\"ret\":0,\"msg\":\"ok\"}");

        Map<String, Object> res = service.clearDeviceQueue(1, 10L, 1);
        assertNotNull(res);
        assertEquals(10L, res.get("deviceId"));
        assertEquals("987654321", res.get("sn"));
        assertEquals(true, res.get("success"));
        verify(feieyunService).clearPrintQueueWithCredential(anyString(), anyString(), anyString(), eq("987654321"));
    }

    @Test
    void clearDeviceQueue_usesDeviceCredentialsWhenConfigured() throws Exception {
        PrintingDevice dev = device(10L, 1, "CLOUD",
                "{\"sn\":\"2205130322\",\"user\":\"feie_printer@example.com\",\"ukey\":\"secretUkey\",\"apiUrl\":\"http://api.feieyun.cn/Api/Open/\"}", 1);
        when(deviceMapper.selectById(10L)).thenReturn(dev);
        when(feieyunService.clearPrintQueueWithCredential(anyString(), anyString(), anyString(), anyString()))
                .thenReturn("{\"ret\":0,\"msg\":\"ok\"}");

        Map<String, Object> res = service.clearDeviceQueue(1, 10L, 1);
        assertNotNull(res);
        assertEquals(10L, res.get("deviceId"));
        assertEquals("2205130322", res.get("sn"));
        assertEquals(true, res.get("success"));
        verify(feieyunService).clearPrintQueueWithCredential("http://api.feieyun.cn/Api/Open/", "feie_printer@example.com", "secretUkey", "2205130322");
    }

    @Test
    void clearDeviceQueue_rejectsNonCloudDevice() {
        PrintingDevice dev = device(11L, 1, "LAN", "{\"ip\":\"192.168.1.100\"}", 1);
        when(deviceMapper.selectById(11L)).thenReturn(dev);

        ApiException ex = assertThrows(ApiException.class, () -> service.clearDeviceQueue(1, 11L, 1));
        assertEquals("PRINTING_CLEAR_QUEUE_UNSUPPORTED", ex.getErrorCode());
    }

    @Test
    void createDevice_cloudAutoBindsFeieyun() throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", "飞鹅云前台机");
        body.put("transport", "CLOUD");
        body.put("sn", "987654321");
        body.put("key", "secretKey123");
        body.put("user", "u1");
        body.put("ukey", "k1");
        body.put("url", "http://api.feieyun.cn/Api/Open/");

        when(deviceMapper.insert(any(PrintingDevice.class))).thenAnswer(inv -> {
            PrintingDevice d = inv.getArgument(0);
            d.setId(99L);
            return 1;
        });

        Map<String, Object> created = service.createDevice(1, body, 1);
        assertNotNull(created);
        verify(feieyunService).addPrinterWithCredential(eq("http://api.feieyun.cn/Api/Open/"), eq("u1"), eq("k1"), eq("987654321#secretKey123#飞鹅云前台机"));
    }

    @Test
    void deleteDevice_cloudAutoUnbindsFeieyun() throws Exception {
        PrintingDevice dev = device(10L, 1, "CLOUD", "{\"sn\":\"987654321\",\"user\":\"u1\",\"ukey\":\"k1\",\"url\":\"http://api.feieyun.cn/Api/Open/\"}", 1);
        when(deviceMapper.selectById(10L)).thenReturn(dev);
        when(ruleMapper.selectList(any())).thenReturn(Collections.emptyList());

        service.deleteDevice(1, 10L);
        verify(feieyunService).deletePrinterWithCredential(eq("http://api.feieyun.cn/Api/Open/"), eq("u1"), eq("k1"), eq("987654321"));
        verify(deviceMapper).deleteById(10L);
    }
}
