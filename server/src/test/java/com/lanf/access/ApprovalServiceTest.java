package com.lanf.access;

import com.lanf.access.model.AccessContext;
import com.lanf.access.security.ApprovalTokenEnvelopeCipher;
import com.lanf.access.service.ApprovalService;
import com.lanf.access.service.ApprovalRateLimitService;
import com.lanf.common.ApiException;
import com.lanf.entity.AccessApproval;
import com.lanf.entity.Admin;
import com.lanf.mapper.AccessApprovalMapper;
import com.lanf.mapper.AdminMapper;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.security.SecurityAuditService;
import com.lanf.util.AdminPasswordUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;

class ApprovalServiceTest {

    private ApprovalService approvalService;
    private AccessApprovalMapper approvalMapper;
    private AdminMapper adminMapper;
    private IAdminPermissionService adminPermissionService;
    private IAdminShopAccessService adminShopAccessService;
    private ApprovalTokenEnvelopeCipher tokenEnvelopeCipher;
    private ApprovalRateLimitService rateLimitService;
    private SecurityAuditService securityAuditService;

    @BeforeEach
    void setUp() {
        approvalService = new ApprovalService();
        approvalMapper = mock(AccessApprovalMapper.class);
        adminMapper = mock(AdminMapper.class);
        adminPermissionService = mock(IAdminPermissionService.class);
        adminShopAccessService = mock(IAdminShopAccessService.class);
        tokenEnvelopeCipher = new ApprovalTokenEnvelopeCipher("unit-test-approval-envelope-key-32-bytes");
        rateLimitService = mock(ApprovalRateLimitService.class);
        securityAuditService = mock(SecurityAuditService.class);

        ReflectionTestUtils.setField(approvalService, "approvalMapper", approvalMapper);
        ReflectionTestUtils.setField(approvalService, "adminMapper", adminMapper);
        ReflectionTestUtils.setField(approvalService, "adminPermissionService", adminPermissionService);
        ReflectionTestUtils.setField(approvalService, "adminShopAccessService", adminShopAccessService);
        ReflectionTestUtils.setField(approvalService, "tokenEnvelopeCipher", tokenEnvelopeCipher);
        ReflectionTestUtils.setField(approvalService, "rateLimitService", rateLimitService);
        ReflectionTestUtils.setField(approvalService, "securityAuditService", securityAuditService);
    }

    private Admin manager(int id, String pin) {
        Admin m = new Admin();
        m.setId(id);
        m.setUserName("manager_" + id);
        m.setAccountStatus(Admin.STATUS_ACTIVE);
        m.setManagerPinHash(AdminPasswordUtil.encode(pin));
        m.setPassword(AdminPasswordUtil.encode("adminPass123"));
        return m;
    }

    @Test
    void authorizeWithValidPinGeneratesToken() {
        Admin mgr = manager(5, "123456");
        when(adminMapper.selectOne(any())).thenReturn(mgr);
        when(adminMapper.selectById(5)).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(5)).thenReturn(true);
        when(adminPermissionService.getPermissionCodesByAdminId(5))
                .thenReturn(new HashSet<>(Collections.singletonList("access:approve")));

        Map<String, Object> res = approvalService.authorizeAndCreateToken(
                10, 1, "order:refund", "ORDER_REFUND",
                "ord_123", new BigDecimal("88.00"), "Refund request",
                "manager_5", "123456", "PIN", "req_1", "term_1");

        assertNotNull(res.get("approvalToken"));
        assertEquals(120L, res.get("expireSeconds"));
        assertEquals(1, res.get("bindingVersion"));
        assertEquals(true, res.get("legacyBinding"));
        verify(approvalMapper).insert(any(AccessApproval.class));
    }

    @Test
    void authorizeWithWrongPinThrows401() {
        Admin mgr = manager(5, "123456");
        when(adminMapper.selectOne(any())).thenReturn(mgr);
        when(adminMapper.selectById(5)).thenReturn(mgr);

        ApiException ex = assertThrows(ApiException.class, () ->
                approvalService.authorizeAndCreateToken(
                        10, 1, "order:refund", "ORDER_REFUND",
                        "ord_123", new BigDecimal("88.00"), "Refund request",
                        "manager_5", "wrongPin", "PIN", "req_1", "term_1"));

        assertEquals(401, ex.getHttpStatus());
        assertEquals("ACCESS_INVALID_PIN", ex.getErrorCode());
        verify(rateLimitService).recordCredentialFailure(1, "manager_5", 10);
    }

    @Test
    void authorizeRejectsLegacyBroadPermissionAndAcceptsExactApprovalPermission() {
        Admin mgr = manager(5, "123456");
        when(adminMapper.selectOne(any())).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(5)).thenReturn(false);
        when(adminShopAccessService.listAccessibleShopIds(5)).thenReturn(Collections.singleton(1));
        when(adminPermissionService.getPermissionCodesByAdminId(5))
                .thenReturn(new HashSet<>(Arrays.asList("access:approve", "order:operate", "admin:manage")));

        ApiException denied = assertThrows(ApiException.class, () ->
                approvalService.authorizeAndCreateToken(
                        10, 1, "order:operate:refund", "ORDER", "ORD-1",
                        new BigDecimal("88.00"), "refund", "manager_5", "123456",
                        "PIN", "req-1", "POS-1"));
        assertEquals("ACCESS_AUTHORIZER_NO_PERMISSION", denied.getErrorCode());

        when(adminPermissionService.getPermissionCodesByAdminId(5))
                .thenReturn(Collections.singleton("order:operate:refund:approve"));
        Map<String, Object> result = approvalService.authorizeAndCreateToken(
                10, 1, "order:operate:refund", "ORDER", "ORD-1",
                new BigDecimal("88.00"), "refund", "manager_5", "123456",
                "PIN", "req-2", "POS-1");
        assertEquals("order:operate:refund:approve", result.get("requiredApprovalPermission"));
    }

    @Test
    void validateAndConsumeSucceedsThenReplayFails() {
        AccessApproval record = new AccessApproval();
        record.setId(88L);
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setPermission_code("order:refund");
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        record.setToken_hash("mockhash");

        when(approvalMapper.selectOne(any())).thenReturn(record);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        AccessContext ctx = AccessContext.builder()
                .adminId(10)
                .shopId(1)
                .permissionCode("order:refund")
                .build();

        boolean first = approvalService.validateAndConsume("raw-token", ctx);
        assertTrue(first);

        // 次回再次使用已变为 CONSUMED 状态
        record.setStatus(AccessApproval.STATUS_CONSUMED);
        boolean second = approvalService.validateAndConsume("raw-token", ctx);
        assertFalse(second);
    }

    @Test
    void createQrApprovalGeneratesPendingRecord() {
        Admin op = manager(10, "111111");
        when(adminMapper.selectById(10)).thenReturn(op);

        Map<String, Object> res = approvalService.createQrApproval(
                10, 1, "order:refund", "ORDER_REFUND",
                "ord_999", new BigDecimal("120.00"), "Cashier discount", "req_qr_1", "term_pos_1");

        assertNotNull(res.get("approvalCode"));
        assertNotNull(res.get("qrPayload"));
        assertEquals(120L, res.get("expireSeconds"));
        assertEquals("PENDING", res.get("status"));
        assertEquals(1, res.get("bindingVersion"));
        assertEquals(true, res.get("legacyBinding"));
        verify(approvalMapper).insert(any(AccessApproval.class));
    }

    @Test
    void getQrApprovalDetailsValidatesShopAccess() {
        AccessApproval record = new AccessApproval();
        record.setId(101L);
        record.setApproval_no("qr_test_code");
        record.setPermission_code("order:operate:refund");
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setStatus(AccessApproval.STATUS_PENDING);
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);

        Admin mgr = manager(8, "123456");
        when(adminMapper.selectById(8)).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(8)).thenReturn(false);

        // 没权限的店长 -> 403
        when(adminShopAccessService.listAccessibleShopIds(8)).thenReturn(Collections.singleton(99));
        ApiException ex = assertThrows(ApiException.class, () ->
                approvalService.getQrApprovalDetails("qr_test_code", 8));
        assertEquals(403, ex.getHttpStatus());

        // 有权限的店长 -> 成功
        when(adminShopAccessService.listAccessibleShopIds(8)).thenReturn(Collections.singleton(1));
        Map<String, Object> details = approvalService.getQrApprovalDetails("qr_test_code", 8);
        assertEquals("qr_test_code", details.get("approvalCode"));
        assertEquals(1, details.get("shopId"));
    }

    @Test
    void confirmQrApprovalRejectAndUpdateStatus() {
        AccessApproval record = new AccessApproval();
        record.setId(102L);
        record.setApproval_no("qr_reject_code");
        record.setShop_id(1);
        record.setStatus(AccessApproval.STATUS_PENDING);
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);

        Admin mgr = manager(5, "123456");
        when(adminMapper.selectById(5)).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(5)).thenReturn(true);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        Map<String, Object> res = approvalService.confirmQrApproval("qr_reject_code", 5, "REJECT", "Too high");
        assertEquals("REJECTED", res.get("status"));
    }

    @Test
    void confirmQrRejectRequiresSameExactPermissionAsAgree() {
        AccessApproval record = new AccessApproval();
        record.setId(112L);
        record.setApproval_no("qr_reject_permission");
        record.setPermission_code("order:operate:discount");
        record.setShop_id(1);
        record.setStatus(AccessApproval.STATUS_PENDING);
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);

        Admin mgr = manager(5, "123456");
        when(adminMapper.selectById(5)).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(5)).thenReturn(false);
        when(adminShopAccessService.listAccessibleShopIds(5)).thenReturn(Collections.singleton(1));
        when(adminPermissionService.getPermissionCodesByAdminId(5))
                .thenReturn(Collections.singleton("access:approve"));

        ApiException denied = assertThrows(ApiException.class,
                () -> approvalService.confirmQrApproval("qr_reject_permission", 5, "REJECT", "no"));
        assertEquals("ACCESS_PERMISSION_DENIED", denied.getErrorCode());
        assertEquals("order:operate:discount:approve",
                ((Map<?, ?>) denied.getData()).get("requiredApprovalPermission"));
        verify(approvalMapper, never()).update(any(), any());
    }

    @Test
    void confirmQrApprovalPersistsAuthenticatedEnvelopeAndAnotherInstanceCanPoll() {
        AccessApproval record = new AccessApproval();
        record.setId(103L);
        record.setApproval_no("qr_approve_code");
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setPermission_code("order:refund");
        record.setStatus(AccessApproval.STATUS_PENDING);
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);

        Admin mgr = manager(5, "123456");
        when(adminMapper.selectById(5)).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(5)).thenReturn(true);
        when(adminPermissionService.getPermissionCodesByAdminId(5))
                .thenReturn(new HashSet<>(Collections.singletonList("access:approve")));
        when(approvalMapper.update(any(), any())).thenReturn(1);

        // 1. 店长确认同意：只持久化哈希与认证加密信封。
        Map<String, Object> confirmRes = approvalService.confirmQrApproval("qr_approve_code", 5, "AGREE", null);
        assertEquals("APPROVED", confirmRes.get("status"));

        org.mockito.ArgumentCaptor<com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper> uwCaptor =
                org.mockito.ArgumentCaptor.forClass(com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper.class);
        verify(approvalMapper).update(org.mockito.ArgumentMatchers.isNull(), uwCaptor.capture());
        String confirmSqlSet = uwCaptor.getValue().getSqlSet();
        assertTrue(confirmSqlSet != null && confirmSqlSet.contains("token_value"),
                "确认同意必须将加密信封写入数据库以支持多实例轮询");
        String envelope = null;
        for (Object value : uwCaptor.getValue().getParamNameValuePairs().values()) {
            if (value instanceof String && ((String) value).startsWith("aet:v1:")) {
                envelope = (String) value;
                break;
            }
        }
        assertNotNull(envelope, "未持久化审批令牌加密信封");
        String rawToken = tokenEnvelopeCipher.decrypt("qr_approve_code", envelope);
        assertTrue(rawToken.matches("[0-9a-f]{64}"));
        assertTrue(confirmSqlSet.contains("token_hash"));

        // 2. 模拟另一实例：只共享数据库值和部署密钥，不依赖进程内缓存。
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setToken_hash(ApprovalService.sha256(rawToken));
        record.setToken_value(envelope);
        ApprovalService anotherInstance = new ApprovalService();
        ReflectionTestUtils.setField(anotherInstance, "approvalMapper", approvalMapper);
        ReflectionTestUtils.setField(anotherInstance, "adminMapper", adminMapper);
        ReflectionTestUtils.setField(anotherInstance, "tokenEnvelopeCipher",
                new ApprovalTokenEnvelopeCipher("unit-test-approval-envelope-key-32-bytes"));
        Map<String, Object> pollRes = anotherInstance.getQrApprovalStatus("qr_approve_code");
        assertEquals("APPROVED", pollRes.get("status"));
        assertEquals(rawToken, pollRes.get("approvalToken"));
    }

    @Test
    void confirmQrApprovalMissingEnvelopeKeyFailsBeforeStateMutation() {
        AccessApproval record = new AccessApproval();
        record.setId(105L);
        record.setApproval_no("qr_no_key");
        record.setShop_id(1);
        record.setStatus(AccessApproval.STATUS_PENDING);
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);
        Admin mgr = manager(5, "123456");
        when(adminMapper.selectById(5)).thenReturn(mgr);
        when(adminShopAccessService.isSuperAdmin(5)).thenReturn(true);
        ReflectionTestUtils.setField(approvalService, "tokenEnvelopeCipher", new ApprovalTokenEnvelopeCipher(""));

        ApiException ex = assertThrows(ApiException.class,
                () -> approvalService.confirmQrApproval("qr_no_key", 5, "AGREE", null));
        assertEquals(503, ex.getHttpStatus());
        assertEquals("ACCESS_TOKEN_ENVELOPE_UNAVAILABLE", ex.getErrorCode());
        verify(approvalMapper, never()).update(any(), any());
    }

    @Test
    void pollRejectsEnvelopeWhosePlainTokenDoesNotMatchStoredHash() {
        AccessApproval record = new AccessApproval();
        record.setId(106L);
        record.setApproval_no("qr_hash_mismatch");
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        record.setToken_hash(ApprovalService.sha256("different-token"));
        record.setToken_value(tokenEnvelopeCipher.encrypt("qr_hash_mismatch", "actual-token"));
        when(approvalMapper.selectOne(any())).thenReturn(record);

        ApiException ex = assertThrows(ApiException.class,
                () -> approvalService.getQrApprovalStatus("qr_hash_mismatch"));
        assertEquals("ACCESS_TOKEN_ENVELOPE_INVALID", ex.getErrorCode());
    }

    @Test
    void pollNeverReturnsExpiredApprovedTokenAndClearsEnvelope() {
        AccessApproval record = new AccessApproval();
        record.setId(107L);
        record.setApproval_no("qr_expired_approved");
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setExpires_at(new Date(System.currentTimeMillis() - 1000));
        record.setToken_hash(ApprovalService.sha256("expired-token"));
        record.setToken_value(tokenEnvelopeCipher.encrypt("qr_expired_approved", "expired-token"));
        when(approvalMapper.selectOne(any())).thenReturn(record);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        Map<String, Object> result = approvalService.getQrApprovalStatus("qr_expired_approved");

        assertEquals(AccessApproval.STATUS_EXPIRED, result.get("status"));
        assertFalse(result.containsKey("approvalToken"));
        org.mockito.ArgumentCaptor<com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper> captor =
                org.mockito.ArgumentCaptor.forClass(com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper.class);
        verify(approvalMapper).update(org.mockito.ArgumentMatchers.isNull(), captor.capture());
        assertTrue(captor.getValue().getSqlSet().contains("token_value"));
    }

    @Test
    void validateAndConsumeClearsTokenValueOnConsume() {
        AccessApproval record = new AccessApproval();
        record.setId(104L);
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setPermission_code("order:refund");
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        record.setToken_value(tokenEnvelopeCipher.encrypt("qr_consume", "raw-token-persisted"));
        when(approvalMapper.selectOne(any())).thenReturn(record);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        AccessContext ctx = AccessContext.builder()
                .adminId(10)
                .shopId(1)
                .permissionCode("order:refund")
                .build();
        boolean ok = approvalService.validateAndConsume("raw-token-persisted", ctx);
        assertTrue(ok);

        org.mockito.ArgumentCaptor<com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper> uwCaptor =
                org.mockito.ArgumentCaptor.forClass(com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper.class);
        verify(approvalMapper).update(org.mockito.ArgumentMatchers.isNull(), uwCaptor.capture());
        String consumeSqlSet = uwCaptor.getValue().getSqlSet();
        assertTrue(consumeSqlSet != null && consumeSqlSet.contains("token_value"),
                "核销时必须清空 token 明文，防止泄露与复用");
    }

    @Test
    void validateAndConsumeAcceptsPlaceholderBizIdButBindsRealOrderNo() {
        // 占位业务号（订单号缺失时客户端以 'ID: 账单id' 签发）不参与强绑定，
        // 否则退款授权后重试将 40321 二次弹窗
        AccessApproval placeholder = new AccessApproval();
        placeholder.setId(200L);
        placeholder.setStatus(AccessApproval.STATUS_APPROVED);
        placeholder.setShop_id(1);
        placeholder.setOperator_id(10);
        placeholder.setPermission_code("order:operate:refund");
        placeholder.setBiz_id("ID: 12345");
        placeholder.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(placeholder);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        AccessContext ctx = AccessContext.builder()
                .adminId(10)
                .shopId(1)
                .permissionCode("order:operate:refund")
                .resourceId("wx_transaction_998")
                .build();
        assertTrue(approvalService.validateAndConsume("placeholder-token", ctx),
                "占位业务号（ID: 前缀）应放行，避免订单号缺失场景二次弹窗");

        // 真实业务号仍必须强绑定：签发 orderNo 与核销单号不一致时拒绝
        AccessApproval real = new AccessApproval();
        real.setId(201L);
        real.setStatus(AccessApproval.STATUS_APPROVED);
        real.setShop_id(1);
        real.setOperator_id(10);
        real.setPermission_code("order:operate:refund");
        real.setBiz_id("LAOFEI-ORDER-001");
        real.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(real);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        AccessContext mismatchCtx = AccessContext.builder()
                .adminId(10)
                .shopId(1)
                .permissionCode("order:operate:refund")
                .resourceId("LAOFEI-ORDER-002")
                .build();
        assertFalse(approvalService.validateAndConsume("real-token", mismatchCtx),
                "真实业务号不一致必须拒绝核销");
    }

    @Test
    void strictV2IssuanceRejectsPlaceholderResourceAndMissingTerminal() {
        ApiException placeholder = assertThrows(ApiException.class, () ->
                approvalService.authorizeAndCreateToken(
                        10, 1, "order:operate:refund", "ORDER", "ID: 123",
                        new BigDecimal("88.00"), "refund", "manager_5", "123456",
                        "PIN", "req-1", "POS-01", 2));
        assertEquals("ACCESS_RESOURCE_REQUIRED", placeholder.getErrorCode());

        ApiException terminal = assertThrows(ApiException.class, () ->
                approvalService.authorizeAndCreateToken(
                        10, 1, "order:operate:refund", "ORDER", "ORD-123",
                        new BigDecimal("88.00"), "refund", "manager_5", "123456",
                        "PIN", "req-1", null, 2));
        assertEquals("ACCESS_TERMINAL_REQUIRED", terminal.getErrorCode());
    }

    @Test
    void strictV2RequiresExactBindingAndDoesNotConsumeMismatch() {
        AccessApproval record = new AccessApproval();
        record.setId(300L);
        record.setBinding_version(2);
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setPermission_code("order:operate:refund");
        record.setBiz_type("ORDER");
        record.setBiz_id("ORD-123");
        record.setAmount(new BigDecimal("88.00"));
        record.setTerminal_id("POS-01");
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);

        List<AccessContext> mismatches = Arrays.asList(
                AccessContext.builder().adminId(11).shopId(1).permissionCode("order:operate:refund").resourceType("ORDER").resourceId("ORD-123").amount(new BigDecimal("88.00")).terminalId("POS-01").build(),
                AccessContext.builder().adminId(10).shopId(2).permissionCode("order:operate:refund").resourceType("ORDER").resourceId("ORD-123").amount(new BigDecimal("88.00")).terminalId("POS-01").build(),
                AccessContext.builder().adminId(10).shopId(1).permissionCode("order:delete").resourceType("ORDER").resourceId("ORD-123").amount(new BigDecimal("88.00")).terminalId("POS-01").build(),
                AccessContext.builder().adminId(10).shopId(1).permissionCode("order:operate:refund").resourceType("REFUND").resourceId("ORD-123").amount(new BigDecimal("88.00")).terminalId("POS-01").build(),
                AccessContext.builder().adminId(10).shopId(1).permissionCode("order:operate:refund").resourceType("ORDER").resourceId("ORD-999").amount(new BigDecimal("88.00")).terminalId("POS-01").build(),
                AccessContext.builder().adminId(10).shopId(1).permissionCode("order:operate:refund").resourceType("ORDER").resourceId("ORD-123").amount(new BigDecimal("88.00")).terminalId("POS-02").build(),
                AccessContext.builder().adminId(10).shopId(1).permissionCode("order:operate:refund").resourceType("ORDER").resourceId("ORD-123").amount(new BigDecimal("88.01")).terminalId("POS-01").build(),
                AccessContext.builder().adminId(10).shopId(1).permissionCode("order:operate:refund").resourceType("ORDER").resourceId("ORD-123").amount(null).terminalId("POS-01").build()
        );
        for (AccessContext mismatch : mismatches) {
            assertFalse(approvalService.validateAndConsume("strict-token", mismatch));
        }
        verify(approvalMapper, never()).update(any(), any());
    }

    @Test
    void strictV2ConsumesOnceWhenEveryBindingMatches() {
        AccessApproval record = new AccessApproval();
        record.setId(301L);
        record.setBinding_version(2);
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setPermission_code("order:operate:refund");
        record.setBiz_type("ORDER");
        record.setBiz_id("ORD-123");
        record.setAmount(new BigDecimal("88.00"));
        record.setTerminal_id("POS-01");
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        AccessContext exact = AccessContext.builder()
                .adminId(10).shopId(1).permissionCode("order:operate:refund")
                .resourceType("ORDER").resourceId("ORD-123")
                .amount(new BigDecimal("88.0")).terminalId("POS-01").build();
        assertTrue(approvalService.validateAndConsume("strict-token", exact));
        verify(approvalMapper).update(any(), any());
    }

    @Test
    void strictV2OrderDeleteAllowsContextAmountAdaptation() {
        AccessApproval record = new AccessApproval();
        record.setId(302L);
        record.setBinding_version(2);
        record.setStatus(AccessApproval.STATUS_APPROVED);
        record.setShop_id(1);
        record.setOperator_id(10);
        record.setPermission_code("order:delete");
        record.setBiz_type("ORDER");
        record.setBiz_id("ORD-DEL-101");
        record.setAmount(new BigDecimal("58.00")); // 前端发起审批时携带了账单金额
        record.setTerminal_id("cashier-pos-01");
        record.setExpires_at(new Date(System.currentTimeMillis() + 60000));
        when(approvalMapper.selectOne(any())).thenReturn(record);
        when(approvalMapper.update(any(), any())).thenReturn(1);

        // 1. 上下文无金额 (amount=null) 仍可匹配核销
        AccessContext ctxNoAmount = AccessContext.builder()
                .adminId(10).shopId(1).permissionCode("order:delete")
                .resourceType("ORDER").resourceId("ORD-DEL-101")
                .amount(null).terminalId("cashier-pos-01").build();
        assertTrue(approvalService.validateAndConsume("del-token-1", ctxNoAmount));

        // 2. 上下文计算出的金额一致仍可匹配核销
        AccessContext ctxSameAmount = AccessContext.builder()
                .adminId(10).shopId(1).permissionCode("order:delete")
                .resourceType("ORDER").resourceId("ORD-DEL-101")
                .amount(new BigDecimal("58.00")).terminalId("cashier-pos-01").build();
        assertTrue(approvalService.validateAndConsume("del-token-2", ctxSameAmount));

        // 3. 关键字段不匹配（如终端、订单号或操作人不同）依然被拦截拒绝
        AccessContext ctxWrongTerminal = AccessContext.builder()
                .adminId(10).shopId(1).permissionCode("order:delete")
                .resourceType("ORDER").resourceId("ORD-DEL-101")
                .amount(new BigDecimal("58.00")).terminalId("wrong-pos").build();
        assertFalse(approvalService.validateAndConsume("del-token-3", ctxWrongTerminal));

        AccessContext ctxWrongOrder = AccessContext.builder()
                .adminId(10).shopId(1).permissionCode("order:delete")
                .resourceType("ORDER").resourceId("ORD-DEL-OTHER")
                .amount(new BigDecimal("58.00")).terminalId("cashier-pos-01").build();
        assertFalse(approvalService.validateAndConsume("del-token-4", ctxWrongOrder));
    }
 }
