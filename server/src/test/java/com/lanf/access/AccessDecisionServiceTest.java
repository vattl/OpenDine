package com.lanf.access;

import com.lanf.access.model.AccessContext;
import com.lanf.access.model.AccessDecision;
import com.lanf.access.policy.DiscountPolicyHandler;
import com.lanf.access.policy.MaxAmountPolicyHandler;
import com.lanf.access.service.AccessConflictService;
import com.lanf.access.service.AccessDecisionService;
import com.lanf.access.service.ApprovalService;
import com.lanf.common.ApiException;
import com.lanf.constant.AdminDataScope;
import com.lanf.entity.AccessConflictRule;
import com.lanf.entity.AccessPolicy;
import com.lanf.entity.Admin;
import com.lanf.entity.AdminPermissionOverride;
import com.lanf.entity.AdminRole;
import com.lanf.entity.Role;
import com.lanf.entity.RolePolicy;
import com.lanf.mapper.AccessConflictRuleMapper;
import com.lanf.mapper.AccessPolicyMapper;
import com.lanf.mapper.AdminMapper;
import com.lanf.mapper.AdminPermissionOverrideMapper;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.mapper.RolePolicyMapper;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AccessDecisionServiceTest {

    private AccessDecisionService decisionService;
    private AccessConflictService conflictService;

    private AdminMapper adminMapper;
    private AdminRoleMapper adminRoleMapper;
    private RoleMapper roleMapper;
    private IAdminPermissionService adminPermissionService;
    private IAdminShopAccessService adminShopAccessService;
    private AdminPermissionOverrideMapper overrideMapper;
    private AccessPolicyMapper accessPolicyMapper;
    private RolePolicyMapper rolePolicyMapper;
    private ApprovalService approvalService;
    private AccessConflictRuleMapper conflictRuleMapper;

    @BeforeEach
    void setUp() {
        decisionService = new AccessDecisionService();
        conflictService = new AccessConflictService();

        adminMapper = mock(AdminMapper.class);
        adminRoleMapper = mock(AdminRoleMapper.class);
        roleMapper = mock(RoleMapper.class);
        adminPermissionService = mock(IAdminPermissionService.class);
        adminShopAccessService = mock(IAdminShopAccessService.class);
        overrideMapper = mock(AdminPermissionOverrideMapper.class);
        accessPolicyMapper = mock(AccessPolicyMapper.class);
        rolePolicyMapper = mock(RolePolicyMapper.class);
        approvalService = mock(ApprovalService.class);
        conflictRuleMapper = mock(AccessConflictRuleMapper.class);

        ReflectionTestUtils.setField(decisionService, "adminMapper", adminMapper);
        ReflectionTestUtils.setField(decisionService, "adminRoleMapper", adminRoleMapper);
        ReflectionTestUtils.setField(decisionService, "roleMapper", roleMapper);
        ReflectionTestUtils.setField(decisionService, "adminPermissionService", adminPermissionService);
        ReflectionTestUtils.setField(decisionService, "adminShopAccessService", adminShopAccessService);
        ReflectionTestUtils.setField(decisionService, "overrideMapper", overrideMapper);
        ReflectionTestUtils.setField(decisionService, "accessPolicyMapper", accessPolicyMapper);
        ReflectionTestUtils.setField(decisionService, "rolePolicyMapper", rolePolicyMapper);
        ReflectionTestUtils.setField(decisionService, "approvalService", approvalService);
        ReflectionTestUtils.setField(decisionService, "policyHandlers", Arrays.asList(
                new MaxAmountPolicyHandler(),
                new DiscountPolicyHandler()
        ));
        decisionService.initHandlers();

        ReflectionTestUtils.setField(conflictService, "conflictRuleMapper", conflictRuleMapper);
    }

    private Admin activeAdmin(int id) {
        Admin a = new Admin();
        a.setId(id);
        a.setUserName("cashier_" + id);
        a.setAccountStatus(Admin.STATUS_ACTIVE);
        a.setPermissionVersion(1L);
        return a;
    }

    @Test
    void disabledAccountIsBlocked() {
        Admin a = activeAdmin(10);
        a.setAccountStatus(Admin.STATUS_DISABLED);
        when(adminMapper.selectById(10)).thenReturn(a);

        AccessContext ctx = AccessContext.builder().adminId(10).permissionCode("order:refund").build();
        AccessDecision decision = decisionService.evaluate(ctx);

        assertFalse(decision.isAllow());
        assertEquals("ACCESS_ACCOUNT_DISABLED", decision.getReasonCode());
    }

    @Test
    void shopOutOfScopeIsBlocked() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.isSuperAdmin(10)).thenReturn(false);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.SHOP);
        when(adminShopAccessService.listAccessibleShopIds(10)).thenReturn(new HashSet<>(Collections.singletonList(1)));

        AccessContext ctx = AccessContext.builder().adminId(10).shopId(2).permissionCode("order:refund").build();
        AccessDecision decision = decisionService.evaluate(ctx);

        assertFalse(decision.isAllow());
        assertEquals("ACCESS_SHOP_OUT_OF_SCOPE", decision.getReasonCode());
    }

    @Test
    void explicitDenyOverridesRbacGrant() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);

        AdminPermissionOverride ov = new AdminPermissionOverride();
        ov.setAdmin_id(10);
        ov.setPermission_code("order:refund");
        ov.setEffect(AdminPermissionOverride.EFFECT_DENY);
        ov.setReason("Security restriction");
        when(overrideMapper.selectList(any())).thenReturn(Collections.singletonList(ov));

        AccessContext ctx = AccessContext.builder().adminId(10).permissionCode("order:refund").build();
        AccessDecision decision = decisionService.evaluate(ctx);

        assertFalse(decision.isAllow());
        assertEquals("ACCESS_EXPLICIT_DENY", decision.getReasonCode());
    }

    @Test
    void rbacDeniedWhenNoGrant() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10)).thenReturn(Collections.emptySet());

        AccessContext ctx = AccessContext.builder().adminId(10).permissionCode("order:refund").build();
        AccessDecision decision = decisionService.evaluate(ctx);

        assertFalse(decision.isAllow());
        assertEquals("ACCESS_PERMISSION_DENIED", decision.getReasonCode());
        assertEquals(AccessDecision.Outcome.DENY, decision.getOutcome());
    }

    @Test
    void cashierEntryPermissionCanInitiateRefundApprovalButCannotBypassIt() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10))
                .thenReturn(new HashSet<>(Collections.singletonList("cashier:operate")));
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.emptyList());

        AccessDecision decision = decisionService.evaluate(AccessContext.builder()
                .adminId(10)
                .permissionCode("order:operate:refund")
                .resourceType("ORDER")
                .resourceId("ORDER-1")
                .build());

        assertEquals(AccessDecision.Outcome.REQUIRE_APPROVAL, decision.getOutcome());
        assertFalse(decision.isAllow());
        assertTrue(decision.isApprovalRequired());
        assertEquals("order:operate:refund:approve", decision.getApproval().getPermission());
    }

    @Test
    void validApprovalTokenAllowsEntryOnlyCashierForExactAction() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10))
                .thenReturn(new HashSet<>(Collections.singletonList("cashier:operate")));
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(approvalService.validateAndConsume(eq("strict-token"), any())).thenReturn(true);

        AccessDecision decision = decisionService.evaluate(AccessContext.builder()
                .adminId(10)
                .permissionCode("order:operate:refund")
                .approvalToken("strict-token")
                .build());

        assertEquals(AccessDecision.Outcome.ALLOW, decision.getOutcome());
        assertTrue(decision.isAllow());
        assertEquals("APPROVED_OVERRIDE", decision.getReasonCode());
    }

    @Test
    void invalidApprovalTokenCannotBypassActionPermission() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10))
                .thenReturn(new HashSet<>(Collections.singletonList("cashier:operate")));
        when(approvalService.validateAndConsume(eq("bad-token"), any())).thenReturn(false);

        AccessDecision decision = decisionService.evaluate(AccessContext.builder()
                .adminId(10)
                .permissionCode("order:operate:changePrice")
                .approvalToken("bad-token")
                .build());

        assertEquals(AccessDecision.Outcome.DENY, decision.getOutcome());
        assertFalse(decision.isAllow());
        assertEquals("ACCESS_APPROVAL_INVALID", decision.getReasonCode());
    }

    @Test
    void explicitDenyOnCashierEntryBlocksApprovalInitiation() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(adminPermissionService.getPermissionCodesByAdminId(10))
                .thenReturn(new HashSet<>(Collections.singletonList("cashier:operate")));
        AdminPermissionOverride entryDeny = new AdminPermissionOverride();
        entryDeny.setEffect(AdminPermissionOverride.EFFECT_DENY);
        entryDeny.setReason("cashier entry suspended");
        when(overrideMapper.selectList(any()))
                .thenReturn(Collections.emptyList())
                .thenReturn(Collections.singletonList(entryDeny));

        AccessDecision decision = decisionService.evaluate(AccessContext.builder()
                .adminId(10)
                .permissionCode("order:operate:refund")
                .build());

        assertEquals(AccessDecision.Outcome.DENY, decision.getOutcome());
        assertEquals("ACCESS_EXPLICIT_DENY", decision.getReasonCode());
    }

    @Test
    void refundExecutionPermissionDoesNotGrantChangePriceExecution() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10)).thenReturn(new HashSet<>(Arrays.asList(
                "cashier:operate", "order:operate:refund")));
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.emptyList());

        AccessDecision decision = decisionService.evaluate(AccessContext.builder()
                .adminId(10)
                .permissionCode("order:operate:changePrice")
                .build());

        assertEquals(AccessDecision.Outcome.REQUIRE_APPROVAL, decision.getOutcome());
        assertFalse(decision.isAllow());
        assertEquals("order:operate:changePrice:approve", decision.getApproval().getPermission());
    }

    @Test
    void superAdminCanExecuteKnownActionWithoutRoleGrant() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.isSuperAdmin(10)).thenReturn(true);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10)).thenReturn(Collections.emptySet());
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.emptyList());

        AccessDecision decision = decisionService.evaluate(AccessContext.builder()
                .adminId(10)
                .permissionCode("order:operate:refund")
                .build());

        assertEquals(AccessDecision.Outcome.ALLOW, decision.getOutcome());
    }

    @Test
    void policyExceedsAmountRequiresApproval() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10))
                .thenReturn(new HashSet<>(Collections.singletonList("order:refund")));

        AdminRole ar = new AdminRole();
        ar.setAdmin_id(10);
        ar.setRole_id(3);
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.singletonList(ar));

        Role role = new Role();
        role.setId(3);
        role.setRole_code("CASHIER");
        role.setRole_name("收银员");
        when(roleMapper.selectBatchIds(any())).thenReturn(Collections.singletonList(role));

        RolePolicy rp = new RolePolicy();
        rp.setRole_id(3);
        rp.setPolicy_id(100L);
        when(rolePolicyMapper.selectList(any())).thenReturn(Collections.singletonList(rp));

        AccessPolicy policy = new AccessPolicy();
        policy.setId(100L);
        policy.setPolicy_code("POL_REFUND_MAX");
        policy.setPolicy_type("MAX_AMOUNT");
        policy.setConfig_json("{\"maxAmount\": 50.00, \"approvalPermission\": \"access:approve\"}");
        policy.setEnabled(1);
        when(accessPolicyMapper.selectList(any())).thenReturn(Collections.singletonList(policy));

        // 退款 100 > 50 阈值，未传 token
        AccessContext ctx = AccessContext.builder()
                .adminId(10)
                .permissionCode("order:refund")
                .amount(new BigDecimal("100.00"))
                .build();

        AccessDecision decision = decisionService.evaluate(ctx);
        assertFalse(decision.isAllow());
        assertTrue(decision.isApprovalRequired());
        assertNotNull(decision.getApproval());
        assertEquals(AccessDecision.Outcome.REQUIRE_APPROVAL, decision.getOutcome());
    }

    @Test
    void policyExceedsAmountPassesWithValidApprovalToken() {
        Admin a = activeAdmin(10);
        when(adminMapper.selectById(10)).thenReturn(a);
        when(adminShopAccessService.resolveScope(10)).thenReturn(AdminDataScope.HQ);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(adminPermissionService.getPermissionCodesByAdminId(10))
                .thenReturn(new HashSet<>(Collections.singletonList("order:refund")));

        AdminRole ar = new AdminRole();
        ar.setAdmin_id(10);
        ar.setRole_id(3);
        when(adminRoleMapper.selectList(any())).thenReturn(Collections.singletonList(ar));

        Role role = new Role();
        role.setId(3);
        role.setRole_code("CASHIER");
        role.setRole_name("收银员");
        when(roleMapper.selectBatchIds(any())).thenReturn(Collections.singletonList(role));

        RolePolicy rp = new RolePolicy();
        rp.setRole_id(3);
        rp.setPolicy_id(100L);
        when(rolePolicyMapper.selectList(any())).thenReturn(Collections.singletonList(rp));

        AccessPolicy policy = new AccessPolicy();
        policy.setId(100L);
        policy.setPolicy_code("POL_REFUND_MAX");
        policy.setPolicy_type("MAX_AMOUNT");
        policy.setConfig_json("{\"maxAmount\": 50.00, \"approvalPermission\": \"access:approve\"}");
        policy.setEnabled(1);
        when(accessPolicyMapper.selectList(any())).thenReturn(Collections.singletonList(policy));

        when(approvalService.validateAndConsume(eq("valid-mock-token"), any())).thenReturn(true);

        AccessContext ctx = AccessContext.builder()
                .adminId(10)
                .permissionCode("order:refund")
                .amount(new BigDecimal("100.00"))
                .approvalToken("valid-mock-token")
                .build();

        AccessDecision decision = decisionService.evaluate(ctx);
        assertTrue(decision.isAllow());
        assertEquals("APPROVED_OVERRIDE", decision.getReasonCode());
        assertEquals(AccessDecision.Outcome.ALLOW, decision.getOutcome());
    }

    @Test
    void sodHardConflictThrowsException() {
        AccessConflictRule rule = new AccessConflictRule();
        rule.setMessage("收银与对账职责分离");
        rule.setPermission_a("cashier:cashbox:open");
        rule.setPermission_b("report:financial:view");
        rule.setSeverity(AccessConflictRule.SEVERITY_HARD);
        rule.setEnabled(1);

        when(conflictRuleMapper.selectList(any())).thenReturn(Collections.singletonList(rule));

        List<String> userCodes = Arrays.asList("cashier:cashbox:open", "report:financial:view");

        ApiException ex = assertThrows(ApiException.class, () ->
                conflictService.validateNoHardConflict(userCodes, false, null));
        assertEquals(409, ex.getHttpStatus());
        assertEquals("ACCESS_ROLE_CONFLICT", ex.getErrorCode());
    }
}
