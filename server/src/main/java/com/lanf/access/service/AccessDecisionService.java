package com.lanf.access.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.access.model.AccessContext;
import com.lanf.access.model.AccessDecision;
import com.lanf.access.model.ApprovalRequirement;
import com.lanf.access.policy.AccessPolicyHandler;
import com.lanf.access.policy.PolicyResult;
import com.lanf.access.security.ActionPermissionVocabulary;
import com.lanf.constant.AdminDataScope;
import com.lanf.entity.AccessPolicy;
import com.lanf.entity.Admin;
import com.lanf.entity.AdminPermissionOverride;
import com.lanf.entity.AdminRole;
import com.lanf.entity.Role;
import com.lanf.entity.RolePolicy;
import com.lanf.mapper.AccessPolicyMapper;
import com.lanf.mapper.AdminMapper;
import com.lanf.mapper.AdminPermissionOverrideMapper;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.mapper.RolePolicyMapper;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 统一访问决策服务 (AccessDecisionService)
 * 聚合 RBAC + Data Scope + Policy + Override + Approval Token
 */
@Service
public class AccessDecisionService {

    private static final Logger log = LoggerFactory.getLogger(AccessDecisionService.class);

    @Autowired
    private AdminMapper adminMapper;
    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private RoleMapper roleMapper;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;
    @Autowired
    private AdminPermissionOverrideMapper overrideMapper;
    @Autowired
    private AccessPolicyMapper accessPolicyMapper;
    @Autowired
    private RolePolicyMapper rolePolicyMapper;
    @Autowired
    private ApprovalService approvalService;
    @Autowired
    private List<AccessPolicyHandler> policyHandlers;

    private final Map<String, AccessPolicyHandler> handlerMap = new HashMap<>();

    @PostConstruct
    public void initHandlers() {
        if (policyHandlers != null) {
            for (AccessPolicyHandler h : policyHandlers) {
                handlerMap.put(h.type(), h);
            }
        }
    }

    /**
     * 核心统一决策评估
     */
    public AccessDecision evaluate(AccessContext ctx) {
        if (ctx == null || ctx.getAdminId() == null) {
            return AccessDecision.deny("ACCESS_AUTHENTICATION_REQUIRED", "未提供操作人身份");
        }
        if (!org.springframework.util.StringUtils.hasText(ctx.getPermissionCode())) {
            return AccessDecision.deny("ACCESS_PERMISSION_REQUIRED", "未提供业务功能权限码");
        }

        // 1. 管理员账户状态校验
        Admin admin = adminMapper.selectById(ctx.getAdminId());
        if (admin == null) {
            return AccessDecision.deny("ACCESS_NOT_FOUND", "操作人管理员不存在: " + ctx.getAdminId());
        }

        String accountStatus = admin.getAccountStatus() != null ? admin.getAccountStatus() : Admin.STATUS_ACTIVE;
        if (Admin.STATUS_DISABLED.equals(accountStatus)) {
            return AccessDecision.deny("ACCESS_ACCOUNT_DISABLED", "操作人账号已被停用");
        }
        if (Admin.STATUS_RESIGNED.equals(accountStatus)) {
            return AccessDecision.deny("ACCESS_ACCOUNT_RESIGNED", "操作人员工已离职");
        }
        if (Admin.STATUS_LOCKED.equals(accountStatus)
                && admin.getLockedUntil() != null && admin.getLockedUntil().after(new Date())) {
            return AccessDecision.deny("ACCESS_ACCOUNT_LOCKED", "操作人账号处于锁定状态");
        }

        // 2. 门店数据范围校验
        boolean superAdmin = adminShopAccessService.isSuperAdmin(ctx.getAdminId());
        boolean shopInScope = true;
        if (ctx.getShopId() != null) {
            if (!superAdmin) {
                AdminDataScope scope = adminShopAccessService.resolveScope(ctx.getAdminId());
                if (scope != AdminDataScope.HQ) {
                    Set<Integer> shopIds = adminShopAccessService.listAccessibleShopIds(ctx.getAdminId());
                    shopInScope = shopIds != null && shopIds.contains(ctx.getShopId());
                }
            }
        }
        if (!shopInScope) {
            return AccessDecision.deny("ACCESS_SHOP_OUT_OF_SCOPE", "当前操作门店超出有效数据范围");
        }

        // 3. 显式覆盖校验 (Explicit Override: DENY 优先)
        Date now = new Date();
        List<AdminPermissionOverride> overrides = loadActiveOverrides(
                ctx.getAdminId(), ctx.getShopId(), ctx.getPermissionCode(), now);

        boolean hasExplicitAllow = false;
        for (AdminPermissionOverride ov : overrides) {
            if (AdminPermissionOverride.EFFECT_DENY.equalsIgnoreCase(ov.getEffect())) {
                return AccessDecision.deny("ACCESS_EXPLICIT_DENY", "该操作已被安全策略显式拒绝: " + ov.getReason());
            }
            if (AdminPermissionOverride.EFFECT_ALLOW.equalsIgnoreCase(ov.getEffect())) {
                hasExplicitAllow = true;
            }
        }

        // 4. RBAC 基础功能权限校验
        Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId(ctx.getAdminId());
        boolean rbacGranted = superAdmin || (permissions != null && permissions.contains(ctx.getPermissionCode()));
        if (!rbacGranted && !hasExplicitAllow) {
            ActionPermissionVocabulary.ActionPermission action =
                    ActionPermissionVocabulary.findByExecutePermission(ctx.getPermissionCode());
            List<AdminPermissionOverride> entryOverrides = action == null
                    ? Collections.emptyList()
                    : loadActiveOverrides(ctx.getAdminId(), ctx.getShopId(), action.getEntryPermission(), now);
            for (AdminPermissionOverride entryOverride : entryOverrides) {
                if (AdminPermissionOverride.EFFECT_DENY.equalsIgnoreCase(entryOverride.getEffect())) {
                    return AccessDecision.deny("ACCESS_EXPLICIT_DENY",
                            "敏感操作入口权限已被安全策略显式拒绝: " + entryOverride.getReason());
                }
            }
            boolean entryExplicitAllow = entryOverrides.stream().anyMatch(entryOverride ->
                    AdminPermissionOverride.EFFECT_ALLOW.equalsIgnoreCase(entryOverride.getEffect()));
            boolean canInitiate = action != null && (entryExplicitAllow || (permissions != null
                    && permissions.contains(action.getEntryPermission())));
            if (!canInitiate) {
                return AccessDecision.deny("ACCESS_PERMISSION_DENIED", "缺少业务功能权限: " + ctx.getPermissionCode());
            }

            if (org.springframework.util.StringUtils.hasText(ctx.getApprovalToken())) {
                boolean consumed = approvalService.validateAndConsume(ctx.getApprovalToken(), ctx);
                if (!consumed) {
                    return AccessDecision.deny("ACCESS_APPROVAL_INVALID", "授权令牌无效、已过期或已被使用");
                }
                AccessDecision approved = AccessDecision.allow("审批核销成功，允许执行");
                approved.setReasonCode("APPROVED_OVERRIDE");
                approved.setMatchedRoles(loadMatchedRoles(ctx.getAdminId(), action.getEntryPermission()));
                approved.setMatchedPolicies(Collections.emptyList());
                return approved;
            }

            ApprovalRequirement requirement = ApprovalRequirement.builder()
                    .required(true)
                    .permission(action.getApprovalPermission())
                    .reason("当前操作需要具备精确动作权限的员工审批")
                    .currentAmount(ctx.getAmount())
                    .build();
            AccessDecision required = AccessDecision.approvalRequired(
                    requirement, "当前账号可发起操作，但必须完成动作级审批");
            required.setMatchedRoles(loadMatchedRoles(ctx.getAdminId(), action.getEntryPermission()));
            required.setMatchedPolicies(Collections.emptyList());
            return required;
        }

        // 收集匹配的角色列表
        List<Map<String, Object>> matchedRoleViews = loadMatchedRoles(ctx.getAdminId(), ctx.getPermissionCode());

        // 5. 策略规则引擎匹配与判定
        List<AccessPolicy> policies = loadEffectivePolicies(ctx.getAdminId(), ctx.getShopId(), ctx.getPermissionCode());
        List<Map<String, Object>> matchedPolicyViews = new ArrayList<>();

        for (AccessPolicy policy : policies) {
            Map<String, Object> pv = new LinkedHashMap<>();
            pv.put("id", policy.getId());
            pv.put("policyCode", policy.getPolicy_code());
            pv.put("policyType", policy.getPolicy_type());
            matchedPolicyViews.add(pv);

            AccessPolicyHandler handler = handlerMap.get(policy.getPolicy_type());
            if (handler == null) {
                continue;
            }

            PolicyResult result = handler.evaluate(policy, ctx);
            if (!result.isPassed()) {
                // 如果需要审批，且携带了 approvalToken，尝试核销消费
                if (result.isApprovable()) {
                    if (org.springframework.util.StringUtils.hasText(ctx.getApprovalToken())) {
                        boolean consumed = approvalService.validateAndConsume(ctx.getApprovalToken(), ctx);
                        if (consumed) {
                            AccessDecision approvedDecision = AccessDecision.allow("审批核销成功，允许执行");
                            approvedDecision.setReasonCode("APPROVED_OVERRIDE");
                            approvedDecision.setMatchedRoles(matchedRoleViews);
                            approvedDecision.setMatchedPolicies(matchedPolicyViews);
                            return approvedDecision;
                        } else {
                            return AccessDecision.deny("ACCESS_APPROVAL_INVALID", "授权令牌无效、已过期或已被使用");
                        }
                    } else {
                        // 未携带 Token，直接返回审批需求
                        AccessDecision reqDecision = AccessDecision.approvalRequired(result.getRequirement(), result.getReason());
                        reqDecision.setMatchedRoles(matchedRoleViews);
                        reqDecision.setMatchedPolicies(matchedPolicyViews);
                        return reqDecision;
                    }
                } else {
                    return AccessDecision.deny("ACCESS_POLICY_DENIED", result.getReason());
                }
            }
        }

        // 所有策略与权限均通过
        AccessDecision decision = AccessDecision.allow("权限与策略校验全部通过");
        decision.setMatchedRoles(matchedRoleViews);
        decision.setMatchedPolicies(matchedPolicyViews);
        return decision;
    }

    private List<AdminPermissionOverride> loadActiveOverrides(Integer adminId, Integer shopId,
                                                               String permissionCode, Date now) {
        List<AdminPermissionOverride> overrides = overrideMapper.selectList(
                new QueryWrapper<AdminPermissionOverride>()
                        .eq("admin_id", adminId)
                        .eq("permission_code", permissionCode)
                        .and(w -> w.isNull("shop_id").or().eq("shop_id", shopId))
                        .and(w -> w.isNull("valid_from").or().le("valid_from", now))
                        .and(w -> w.isNull("valid_until").or().ge("valid_until", now)));
        return overrides != null ? overrides : Collections.emptyList();
    }

    private List<Map<String, Object>> loadMatchedRoles(Integer adminId, String permissionCode) {
        List<AdminRole> adminRoles = adminRoleMapper.selectList(new QueryWrapper<AdminRole>().eq("admin_id", adminId));
        if (adminRoles.isEmpty()) {
            return Collections.emptyList();
        }
        List<Integer> roleIds = adminRoles.stream().map(AdminRole::getRole_id).distinct().collect(Collectors.toList());
        List<Role> roles = roleMapper.selectBatchIds(roleIds);
        if (roles == null) {
            return Collections.emptyList();
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (Role r : roles) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("roleId", r.getId());
            m.put("roleCode", r.getRole_code());
            m.put("roleName", r.getRole_name());
            out.add(m);
        }
        return out;
    }

    private List<AccessPolicy> loadEffectivePolicies(Integer adminId, Integer shopId, String permissionCode) {
        List<AdminRole> adminRoles = adminRoleMapper.selectList(new QueryWrapper<AdminRole>().eq("admin_id", adminId));
        if (adminRoles.isEmpty()) {
            return Collections.emptyList();
        }
        List<Integer> roleIds = adminRoles.stream().map(AdminRole::getRole_id).distinct().collect(Collectors.toList());

        List<RolePolicy> rolePolicies = rolePolicyMapper.selectList(new QueryWrapper<RolePolicy>()
                .in("role_id", roleIds)
                .and(w -> w.isNull("shop_id").or().eq("shop_id", shopId)));

        if (rolePolicies.isEmpty()) {
            return Collections.emptyList();
        }
        List<Long> policyIds = rolePolicies.stream().map(RolePolicy::getPolicy_id).distinct().collect(Collectors.toList());
        return accessPolicyMapper.selectList(new QueryWrapper<AccessPolicy>()
                .in("id", policyIds)
                .eq("permission_code", permissionCode)
                .eq("enabled", 1)
                .orderByAsc("priority"));
    }
}
