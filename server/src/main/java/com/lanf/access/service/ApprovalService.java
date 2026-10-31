package com.lanf.access.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.access.model.AccessContext;
import com.lanf.access.security.ApprovalTokenEnvelopeCipher;
import com.lanf.access.security.ApprovalPermissionPolicy;
import com.lanf.common.ApiException;
import com.lanf.entity.AccessApproval;
import com.lanf.entity.Admin;
import com.lanf.mapper.AccessApprovalMapper;
import com.lanf.mapper.AdminMapper;
import com.lanf.security.SecurityAuditService;
import com.lanf.service.IAdminPermissionService;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.util.AdminPasswordUtil;
import com.lanf.util.StringUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/**
 * 统一审批与授权令牌服务 (POS Access Control v2)
 */
@Service
public class ApprovalService {

    private static final Logger log = LoggerFactory.getLogger(ApprovalService.class);
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();
    private static final long DEFAULT_EXPIRE_SECONDS = 120L; // 2 分钟有效
    private static final int LEGACY_BINDING_VERSION = 1;
    private static final int STRICT_BINDING_VERSION = 2;

    @Autowired
    private AccessApprovalMapper approvalMapper;
    @Autowired
    private AdminMapper adminMapper;
    @Autowired
    private IAdminPermissionService adminPermissionService;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;
    @Autowired
    private ApprovalTokenEnvelopeCipher tokenEnvelopeCipher;
    @Autowired
    private ApprovalRateLimitService rateLimitService;
    @Autowired
    private SecurityAuditService securityAuditService;

    /**
     * 校验店长凭证并签发短期单次审批 Token
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> authorizeAndCreateToken(
            Integer operatorId,
            Integer shopId,
            String permission,
            String bizType,
            String bizId,
            BigDecimal amount,
            String reason,
            String authorizerAccount,
            String credential,
            String authMethod,
            String requestId,
            String terminalId) {
        return authorizeAndCreateToken(operatorId, shopId, permission, bizType, bizId, amount,
                reason, authorizerAccount, credential, authMethod, requestId, terminalId,
                LEGACY_BINDING_VERSION);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> authorizeAndCreateToken(
            Integer operatorId,
            Integer shopId,
            String permission,
            String bizType,
            String bizId,
            BigDecimal amount,
            String reason,
            String authorizerAccount,
            String credential,
            String authMethod,
            String requestId,
            String terminalId,
            Integer bindingVersion) {

        int normalizedBindingVersion = normalizeBindingVersion(bindingVersion);
        validateIssuanceBinding(normalizedBindingVersion, operatorId, shopId, permission,
                bizType, bizId, terminalId);

        if (StringUtil.isEmpty(authorizerAccount) || StringUtil.isEmpty(credential)) {
            throw new ApiException(401, "ACCESS_CREDENTIALS_REQUIRED", "请输入授权店长账号与密码/PIN");
        }
        if (shopId == null) {
            throw new ApiException(400, "ACCESS_SHOP_REQUIRED", "缺少门店上下文");
        }
        if (StringUtil.isEmpty(permission)) {
            throw new ApiException(400, "ACCESS_PERMISSION_REQUIRED", "授权目标权限码不能为空");
        }

        rateLimitService.acquireRequest(ApprovalRateLimitService.Scope.ONSITE_AUTHORIZE,
                shopId, "operator:" + (operatorId == null ? 0 : operatorId));
        rateLimitService.assertCredentialAllowed(shopId, authorizerAccount, operatorId);

        // 1. 查找授权人
        Admin authorizer = adminMapper.selectOne(new QueryWrapper<Admin>()
                .eq("work_no", authorizerAccount.trim()).last("LIMIT 1"));
        if (authorizer == null) {
            authorizer = adminMapper.selectOne(new QueryWrapper<Admin>()
                    .eq("userName", authorizerAccount.trim()).last("LIMIT 1"));
        }
        if (authorizer == null) {
            rateLimitService.recordCredentialFailure(shopId, authorizerAccount, operatorId);
            auditCredentialRejection(shopId, operatorId, "ACCESS_AUTHORIZER_NOT_FOUND");
            throw new ApiException(401, "ACCESS_AUTHORIZER_NOT_FOUND", "授权人账号不存在");
        }

        // 2. 授权人状态检查
        String accountStatus = authorizer.getAccountStatus() != null ? authorizer.getAccountStatus() : Admin.STATUS_ACTIVE;
        if (Admin.STATUS_DISABLED.equals(accountStatus)) {
            throw new ApiException(403, "ACCESS_ACCOUNT_DISABLED", "授权人账号已被停用");
        }
        if (Admin.STATUS_RESIGNED.equals(accountStatus)) {
            throw new ApiException(403, "ACCESS_ACCOUNT_RESIGNED", "授权人已离职");
        }
        if (Admin.STATUS_LOCKED.equals(accountStatus)
                && authorizer.getLockedUntil() != null && authorizer.getLockedUntil().after(new Date())) {
            throw new ApiException(423, "ACCESS_ACCOUNT_LOCKED", "授权人账号已被锁定");
        }

        // 3. 授权人凭据校验 (PIN 或密码)
        boolean isPinAuth = AccessApproval.AUTH_METHOD_PIN.equalsIgnoreCase(authMethod);
        if (isPinAuth) {
            if (authorizer.getPinLockedUntil() != null && authorizer.getPinLockedUntil().after(new Date())) {
                throw new ApiException(423, "ACCESS_PIN_LOCKED", "授权人PIN码已锁定，请稍后再试或使用账号密码");
            }
            if (StringUtil.isEmpty(authorizer.getManagerPinHash())
                    || !AdminPasswordUtil.matches(credential, authorizer.getManagerPinHash())) {
                rateLimitService.recordCredentialFailure(shopId, authorizerAccount, operatorId);
                auditCredentialRejection(shopId, operatorId, "ACCESS_INVALID_PIN");
                throw new ApiException(401, "ACCESS_INVALID_PIN", "店长授权PIN码错误");
            }
            if (authorizer.getPinFailedCount() != null && authorizer.getPinFailedCount() > 0) {
                adminMapper.update(null, new UpdateWrapper<Admin>()
                        .set("pin_failed_count", 0)
                        .set("pin_locked_until", null)
                        .eq("id", authorizer.getId()));
            }
        } else {
            if (!AdminPasswordUtil.matches(credential, authorizer.getPassword())) {
                rateLimitService.recordCredentialFailure(shopId, authorizerAccount, operatorId);
                auditCredentialRejection(shopId, operatorId, "ACCESS_INVALID_CREDENTIALS");
                throw new ApiException(401, "ACCESS_INVALID_CREDENTIALS", "店长密码错误");
            }
        }
        rateLimitService.clearCredentialFailures(shopId, authorizerAccount);

        // 4. 授权人门店数据范围校验
        boolean isSuper = adminShopAccessService.isSuperAdmin(authorizer.getId());
        if (!isSuper) {
            Set<Integer> shopIds = adminShopAccessService.listAccessibleShopIds(authorizer.getId());
            if (shopIds == null || !shopIds.contains(shopId)) {
                throw new ApiException(403, "ACCESS_AUTHORIZER_OUT_OF_SCOPE", "授权人无当前门店管辖权限");
            }
        }

        // 5. 授权人权限校验：只接受目标动作的精确 :approve 权限。
        if (!isSuper) {
            Set<String> authorizerPerms = adminPermissionService.getPermissionCodesByAdminId(authorizer.getId());
            if (!ApprovalPermissionPolicy.hasApprovalPermission(authorizerPerms, permission)) {
                auditPermissionRejection(shopId, authorizer.getId(), permission, "onsite_authorize");
                throw new ApiException(403, "ACCESS_AUTHORIZER_NO_PERMISSION", "授权人缺少该业务的审批权限");
            }
        }

        // 6. 生成 256 位随机令牌
        String rawToken = generateToken();
        String tokenHash = sha256(rawToken);

        String approvalNo = "AP_" + shopId + "_" + System.currentTimeMillis() + "_" + (SECURE_RANDOM.nextInt(9000) + 1000);
        Date expiresAt = new Date(System.currentTimeMillis() + DEFAULT_EXPIRE_SECONDS * 1000L);

        AccessApproval approval = AccessApproval.builder()
                .approval_no(approvalNo)
                .permission_code(permission)
                .operator_id(operatorId != null ? operatorId : 0)
                .authorizer_id(authorizer.getId())
                .shop_id(shopId)
                .biz_type(StringUtil.isEmpty(bizType) ? "ORDER" : bizType)
                .biz_id(StringUtil.isEmpty(bizId) ? "N/A" : bizId)
                .amount(amount)
                .reason(StringUtil.isEmpty(reason) ? "店长现场授权" : reason)
                .auth_method(isPinAuth ? AccessApproval.AUTH_METHOD_PIN : AccessApproval.AUTH_METHOD_PASSWORD)
                .status(AccessApproval.STATUS_APPROVED)
                .token_hash(tokenHash)
                .binding_version(normalizedBindingVersion)
                .max_amount(normalizedBindingVersion >= STRICT_BINDING_VERSION
                        ? amount
                        : (amount != null ? amount.add(BigDecimal.valueOf(50)) : null))
                .expires_at(expiresAt)
                .request_id(requestId)
                .terminal_id(terminalId)
                .created_at(new Date())
                .build();

        approvalMapper.insert(approval);

        log.info("[approval] token issued: approvalNo={}, operator={}, authorizer={}, shop={}, perm={}, amount={}, expires={}",
                approvalNo, operatorId, authorizer.getId(), shopId, permission, amount, expiresAt);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("approvalNo", approvalNo);
        result.put("approvalToken", rawToken);
        result.put("permission", permission);
        result.put("requiredApprovalPermission", ApprovalPermissionPolicy.requiredPermission(permission));
        result.put("operatorId", operatorId);
        result.put("authorizerId", authorizer.getId());
        result.put("authorizerName", authorizer.getRealName() != null ? authorizer.getRealName() : authorizer.getUserName());
        result.put("shopId", shopId);
        result.put("bizType", approval.getBiz_type());
        result.put("bizId", approval.getBiz_id());
        result.put("maxAmount", approval.getMax_amount());
        result.put("bindingVersion", normalizedBindingVersion);
        result.put("legacyBinding", normalizedBindingVersion < STRICT_BINDING_VERSION);
        result.put("expiresAt", expiresAt);
        result.put("expireSeconds", DEFAULT_EXPIRE_SECONDS);
        return result;
    }

    /**
     * 校验并原子消费单次审批 Token (CAS 保证单次使用)
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean validateAndConsume(String approvalToken, AccessContext ctx) {
        if (StringUtil.isEmpty(approvalToken) || ctx == null) {
            return false;
        }

        String hash = sha256(approvalToken.trim());
        AccessApproval approval = approvalMapper.selectOne(new QueryWrapper<AccessApproval>()
                .eq("token_hash", hash)
                .last("LIMIT 1"));

        if (approval == null) {
            log.warn("[approval] token hash not found in db: {}", hash);
            return false;
        }

        if (!AccessApproval.STATUS_APPROVED.equals(approval.getStatus())) {
            log.warn("[approval] token status is not APPROVED: id={}, status={}", approval.getId(), approval.getStatus());
            return false;
        }

        if (approval.getExpires_at() == null || approval.getExpires_at().before(new Date())) {
            log.warn("[approval] token expired: id={}, expiresAt={}", approval.getId(), approval.getExpires_at());
            return false;
        }

        int bindingVersion = normalizeStoredBindingVersion(approval.getBinding_version());
        if (bindingVersion >= STRICT_BINDING_VERSION) {
            if (!strictBindingMatches(approval, ctx)) {
                return false;
            }
        } else {
            log.warn("[approval] approval_legacy_binding: id={}, approvalNo={}, permission={}",
                    approval.getId(), approval.getApproval_no(), approval.getPermission_code());
        }

        // v1 兼容绑定校验：历史客户端仍按旧规则运行；v2 已在上方完成全字段精确校验
        if (bindingVersion < STRICT_BINDING_VERSION) {
            if (ctx.getShopId() != null && !ctx.getShopId().equals(approval.getShop_id())) {
                log.warn("[approval] shop mismatch: req={}, token={}", ctx.getShopId(), approval.getShop_id());
                return false;
            }

            if (ctx.getAdminId() != null && approval.getOperator_id() != null
                    && approval.getOperator_id() > 0 && !ctx.getAdminId().equals(approval.getOperator_id())) {
                log.warn("[approval] operator mismatch: req={}, token={}", ctx.getAdminId(), approval.getOperator_id());
                return false;
            }

            if (ctx.getPermissionCode() != null && !ctx.getPermissionCode().equals(approval.getPermission_code())) {
                log.warn("[approval] permission mismatch: req={}, token={}", ctx.getPermissionCode(), approval.getPermission_code());
                return false;
            }

            // v1 only: placeholders keep their historical wildcard behavior during the measured compatibility window.
            String tokenBiz = approval.getBiz_id();
            boolean placeholderBiz = tokenBiz == null || "N/A".equals(tokenBiz) || tokenBiz.startsWith("ID:");
            if (ctx.getResourceId() != null && !placeholderBiz
                    && !ctx.getResourceId().equals(tokenBiz)) {
                log.warn("[approval] bizId mismatch: req={}, token={}", ctx.getResourceId(), tokenBiz);
                return false;
            }

            if (approval.getMax_amount() != null && ctx.getAmount() != null
                    && ctx.getAmount().compareTo(approval.getMax_amount()) > 0) {
                log.warn("[approval] amount exceeded max: req={}, max={}", ctx.getAmount(), approval.getMax_amount());
                return false;
            }
        }

        // CAS 原子更新状态 APPROVED -> CONSUMED（同时清空短期加密信封）
        int rows = approvalMapper.update(null, new UpdateWrapper<AccessApproval>()
                .set("status", AccessApproval.STATUS_CONSUMED)
                .set("consumed_at", new Date())
                .set("token_value", null)
                .eq("id", approval.getId())
                .eq("status", AccessApproval.STATUS_APPROVED)
                .gt("expires_at", new Date()));

        if (rows == 1) {
            log.info("[approval] token successfully consumed: id={}, approvalNo={}, operator={}, authorizer={}",
                    approval.getId(), approval.getApproval_no(), ctx.getAdminId(), approval.getAuthorizer_id());
            return true;
        } else {
            log.warn("[approval] CAS consume failed for token id={}", approval.getId());
            return false;
        }
    }

    // ---------------- 扫码授权 (方案 A) ----------------

    /**
     * 1. 收银端发起扫码授权申请，生成动态二维码识别码与短链票据
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> createQrApproval(
            Integer operatorId,
            Integer shopId,
            String permission,
            String bizType,
            String bizId,
            BigDecimal amount,
            String reason,
            String requestId,
            String terminalId) {
        return createQrApproval(operatorId, shopId, permission, bizType, bizId, amount,
                reason, requestId, terminalId, LEGACY_BINDING_VERSION);
    }

    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> createQrApproval(
            Integer operatorId,
            Integer shopId,
            String permission,
            String bizType,
            String bizId,
            BigDecimal amount,
            String reason,
            String requestId,
            String terminalId,
            Integer bindingVersion) {

        int normalizedBindingVersion = normalizeBindingVersion(bindingVersion);
        validateIssuanceBinding(normalizedBindingVersion, operatorId, shopId, permission,
                bizType, bizId, terminalId);

        if (operatorId == null) {
            throw new ApiException(400, "ACCESS_OPERATOR_REQUIRED", "未提供收银操作人身份");
        }
        if (shopId == null) {
            throw new ApiException(400, "ACCESS_SHOP_REQUIRED", "缺少门店上下文");
        }
        if (StringUtil.isEmpty(permission)) {
            throw new ApiException(400, "ACCESS_PERMISSION_REQUIRED", "授权目标权限码不能为空");
        }

        rateLimitService.acquireRequest(ApprovalRateLimitService.Scope.QR_CREATE,
                shopId, "operator:" + operatorId);

        Admin operator = adminMapper.selectById(operatorId);
        if (operator == null) {
            throw new ApiException(404, "ACCESS_OPERATOR_NOT_FOUND", "收银操作人不存在");
        }

        String approvalCode = "QAP_" + shopId + "_" + System.currentTimeMillis() + "_" + (1000 + SECURE_RANDOM.nextInt(9000));
        Date expiresAt = new Date(System.currentTimeMillis() + DEFAULT_EXPIRE_SECONDS * 1000L);

        AccessApproval approval = new AccessApproval();
        approval.setApproval_no(approvalCode);
        approval.setPermission_code(permission);
        approval.setOperator_id(operatorId);
        approval.setAuthorizer_id(0); // 待店长扫码后回填
        approval.setShop_id(shopId);
        approval.setBiz_type(StringUtil.isEmpty(bizType) ? "GENERAL" : bizType);
        approval.setBiz_id(StringUtil.isEmpty(bizId) ? "N/A" : bizId);
        approval.setAmount(amount);
        approval.setMax_amount(amount);
        approval.setReason(StringUtil.isEmpty(reason) ? "收银扫码授权申请" : reason);
        approval.setAuth_method(AccessApproval.AUTH_METHOD_QR);
        approval.setStatus(AccessApproval.STATUS_PENDING);
        approval.setToken_hash(sha256(approvalCode + "_PENDING"));
        approval.setBinding_version(normalizedBindingVersion);
        approval.setExpires_at(expiresAt);
        approval.setRequest_id(requestId);
        approval.setTerminal_id(terminalId);
        approval.setCreated_at(new Date());

        approvalMapper.insert(approval);
        log.info("[approval] qr approval created: code={}, shop={}, operator={}, perm={}, amount={}, expires={}",
                approvalCode, shopId, operatorId, permission, amount, expiresAt);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("approvalCode", approvalCode);
        result.put("qrPayload", "bbq://approval?code=" + approvalCode);
        result.put("status", AccessApproval.STATUS_PENDING);
        result.put("expiresAt", expiresAt);
        result.put("expireSeconds", DEFAULT_EXPIRE_SECONDS);
        result.put("bindingVersion", normalizedBindingVersion);
        result.put("legacyBinding", normalizedBindingVersion < STRICT_BINDING_VERSION);
        result.put("requiredApprovalPermission", ApprovalPermissionPolicy.requiredPermission(permission));
        return result;
    }

    /**
     * 2. 收银端轮询查询扫码授权状态
     */
    public Map<String, Object> getQrApprovalStatus(String approvalCode) {
        if (StringUtil.isEmpty(approvalCode)) {
            throw new ApiException(400, "ACCESS_VALIDATION", "approvalCode 必填");
        }

        AccessApproval approval = approvalMapper.selectOne(new QueryWrapper<AccessApproval>()
                .eq("approval_no", approvalCode.trim())
                .last("LIMIT 1"));
        if (approval == null) {
            throw new ApiException(404, "ACCESS_APPROVAL_NOT_FOUND", "授权申请不存在: " + approvalCode);
        }

        Date now = new Date();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("approvalCode", approvalCode);
        int bindingVersion = normalizeStoredBindingVersion(approval.getBinding_version());
        result.put("bindingVersion", bindingVersion);
        result.put("legacyBinding", bindingVersion < STRICT_BINDING_VERSION);

        // PENDING/APPROVED 都不得在过期后继续暴露审批结果或令牌信封。
        if (approval.getExpires_at() != null && approval.getExpires_at().before(now)
                && (AccessApproval.STATUS_PENDING.equals(approval.getStatus())
                || AccessApproval.STATUS_APPROVED.equals(approval.getStatus()))) {
            approvalMapper.update(null, new UpdateWrapper<AccessApproval>()
                    .set("status", AccessApproval.STATUS_EXPIRED)
                    .set("token_value", null)
                    .eq("id", approval.getId())
                    .in("status", AccessApproval.STATUS_PENDING, AccessApproval.STATUS_APPROVED));
            result.put("status", AccessApproval.STATUS_EXPIRED);
            return result;
        }

        result.put("status", approval.getStatus());
        if (AccessApproval.STATUS_REJECTED.equals(approval.getStatus())) {
            result.put("reason", approval.getReason());
            return result;
        }

        if (AccessApproval.STATUS_APPROVED.equals(approval.getStatus())) {
            String rawToken = decryptAndVerifyQrToken(approvalCode.trim(), approval);
            result.put("approvalToken", rawToken);
            result.put("authorizerId", approval.getAuthorizer_id());
            if (approval.getAuthorizer_id() != null && approval.getAuthorizer_id() > 0) {
                Admin authorizer = adminMapper.selectById(approval.getAuthorizer_id());
                result.put("authorizerName", com.lanf.util.AdminNameResolver.resolveDisplayName(authorizer));
            }
            result.put("expiresAt", approval.getExpires_at());
        }

        return result;
    }

    /**
     * 3. 店长移动端扫码后查看申请详情
     */
    public Map<String, Object> getQrApprovalDetails(String approvalCode, Integer managerAdminId) {
        if (StringUtil.isEmpty(approvalCode)) {
            throw new ApiException(400, "ACCESS_VALIDATION", "approvalCode 必填");
        }
        if (managerAdminId == null) {
            throw new ApiException(401, "ACCESS_AUTHENTICATION_REQUIRED", "未提供店长身份");
        }

        AccessApproval approval = approvalMapper.selectOne(new QueryWrapper<AccessApproval>()
                .eq("approval_no", approvalCode.trim())
                .last("LIMIT 1"));
        if (approval == null) {
            throw new ApiException(404, "ACCESS_APPROVAL_NOT_FOUND", "授权申请不存在: " + approvalCode);
        }

        Date now = new Date();
        if (approval.getExpires_at() != null && approval.getExpires_at().before(now)) {
            throw new ApiException(400, "ACCESS_APPROVAL_EXPIRED", "该授权申请二维码已过期");
        }

        // 校验店长身份与管辖门店
        Admin manager = adminMapper.selectById(managerAdminId);
        if (manager == null) {
            throw new ApiException(404, "ACCESS_AUTHORIZER_NOT_FOUND", "店长账号不存在");
        }
        String accountStatus = manager.getAccountStatus() != null ? manager.getAccountStatus() : Admin.STATUS_ACTIVE;
        if (!Admin.STATUS_ACTIVE.equals(accountStatus)) {
            throw new ApiException(403, "ACCESS_ACCOUNT_NOT_ACTIVE", "店长账号状态异常，无法审批");
        }

        boolean isSuper = adminShopAccessService.isSuperAdmin(managerAdminId);
        if (!isSuper) {
            Set<Integer> shops = adminShopAccessService.listAccessibleShopIds(managerAdminId);
            if (shops == null || !shops.contains(approval.getShop_id())) {
                throw new ApiException(403, "ACCESS_AUTHORIZER_OUT_OF_SCOPE", "您没有该门店的审批管辖权限");
            }
        }

        Admin operator = adminMapper.selectById(approval.getOperator_id());

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("approvalCode", approval.getApproval_no());
        int bindingVersion = normalizeStoredBindingVersion(approval.getBinding_version());
        out.put("bindingVersion", bindingVersion);
        out.put("legacyBinding", bindingVersion < STRICT_BINDING_VERSION);
        out.put("shopId", approval.getShop_id());
        out.put("permission", approval.getPermission_code());
        out.put("requiredApprovalPermission",
                ApprovalPermissionPolicy.requiredPermission(approval.getPermission_code()));
        out.put("bizType", approval.getBiz_type());
        out.put("bizId", approval.getBiz_id());
        out.put("amount", approval.getAmount());
        out.put("reason", approval.getReason());
        out.put("operatorId", approval.getOperator_id());
        out.put("operatorName", com.lanf.util.AdminNameResolver.resolveDisplayName(operator));
        out.put("operatorWorkNo", operator != null ? operator.getWorkNo() : null);
        out.put("status", approval.getStatus());
        out.put("createdAt", approval.getCreated_at());
        out.put("expiresAt", approval.getExpires_at());
        return out;
    }

    /**
     * 4. 店长移动端确认/拒绝授权
     */
    @Transactional(rollbackFor = Exception.class)
    public Map<String, Object> confirmQrApproval(String approvalCode, Integer managerAdminId, String action, String reason) {
        if (StringUtil.isEmpty(approvalCode)) {
            throw new ApiException(400, "ACCESS_VALIDATION", "approvalCode 必填");
        }
        if (managerAdminId == null) {
            throw new ApiException(401, "ACCESS_AUTHENTICATION_REQUIRED", "未提供店长身份");
        }
        boolean isAgree = "AGREE".equalsIgnoreCase(action);
        boolean isReject = "REJECT".equalsIgnoreCase(action);
        if (!isAgree && !isReject) {
            throw new ApiException(400, "ACCESS_VALIDATION", "action 必须为 AGREE 或 REJECT");
        }

        AccessApproval approval = approvalMapper.selectOne(new QueryWrapper<AccessApproval>()
                .eq("approval_no", approvalCode.trim())
                .last("LIMIT 1"));
        if (approval == null) {
            throw new ApiException(404, "ACCESS_APPROVAL_NOT_FOUND", "授权申请不存在: " + approvalCode);
        }
        if (!AccessApproval.STATUS_PENDING.equals(approval.getStatus())) {
            throw new ApiException(400, "ACCESS_APPROVAL_ALREADY_PROCESSED", "该授权申请已被处理或已失效");
        }
        if (approval.getExpires_at() != null && approval.getExpires_at().before(new Date())) {
            throw new ApiException(400, "ACCESS_APPROVAL_EXPIRED", "该授权申请已过期");
        }

        rateLimitService.acquireRequest(ApprovalRateLimitService.Scope.QR_CONFIRM,
                approval.getShop_id(), "manager:" + managerAdminId);

        // 校验店长权限
        Admin manager = adminMapper.selectById(managerAdminId);
        if (manager == null) {
            throw new ApiException(404, "ACCESS_AUTHORIZER_NOT_FOUND", "店长账号不存在");
        }
        String accountStatus = manager.getAccountStatus() != null ? manager.getAccountStatus() : Admin.STATUS_ACTIVE;
        if (!Admin.STATUS_ACTIVE.equals(accountStatus)) {
            throw new ApiException(403, "ACCESS_ACCOUNT_NOT_ACTIVE", "店长账号状态异常，无法审批");
        }
        boolean isSuper = adminShopAccessService.isSuperAdmin(managerAdminId);
        if (!isSuper) {
            Set<Integer> shops = adminShopAccessService.listAccessibleShopIds(managerAdminId);
            if (shops == null || !shops.contains(approval.getShop_id())) {
                throw new ApiException(403, "ACCESS_AUTHORIZER_OUT_OF_SCOPE", "您没有该门店的审批管辖权限");
            }
            Set<String> perms = adminPermissionService.getPermissionCodesByAdminId(managerAdminId);
            if (!ApprovalPermissionPolicy.hasApprovalPermission(perms, approval.getPermission_code())) {
                auditPermissionRejection(approval.getShop_id(), managerAdminId,
                        approval.getPermission_code(), isAgree ? "qr_agree" : "qr_reject");
                Map<String, Object> data = new LinkedHashMap<>();
                data.put("requiredApprovalPermission",
                        ApprovalPermissionPolicy.requiredPermission(approval.getPermission_code()));
                throw new ApiException(403, "ACCESS_PERMISSION_DENIED", "您不具备审批该操作的权限", data);
            }
        }

        if (isReject) {
            String rejectReason = org.springframework.util.StringUtils.hasText(reason) ? reason.trim() : "店长拒绝授权";
            int rows = approvalMapper.update(null, new UpdateWrapper<AccessApproval>()
                    .set("status", AccessApproval.STATUS_REJECTED)
                    .set("authorizer_id", managerAdminId)
                    .set("reason", rejectReason)
                    .eq("id", approval.getId())
                    .eq("status", AccessApproval.STATUS_PENDING));
            if (rows != 1) {
                throw new ApiException(409, "ACCESS_CONFLICT", "审批状态变更冲突，请刷新后重试");
            }
            log.info("[approval] qr approval rejected: code={}, authorizer={}", approvalCode, managerAdminId);
            Map<String, Object> res = new LinkedHashMap<>();
            res.put("approvalCode", approvalCode);
            res.put("status", AccessApproval.STATUS_REJECTED);
            res.put("reason", rejectReason);
            return res;
        }

        // 同意授权：数据库仅保存哈希与短期认证加密信封，供多实例安全轮询。
        String rawToken = generateToken();
        String tokenHash = sha256(rawToken);
        String tokenEnvelope;
        try {
            tokenEnvelope = tokenEnvelopeCipher.encrypt(approvalCode.trim(), rawToken);
        } catch (IllegalStateException e) {
            log.error("[approval] qr token envelope unavailable: code={}", approvalCode);
            throw new ApiException(503, "ACCESS_TOKEN_ENVELOPE_UNAVAILABLE", "扫码授权令牌服务暂不可用，请联系管理员检查安全配置");
        }

        int rows = approvalMapper.update(null, new UpdateWrapper<AccessApproval>()
                .set("status", AccessApproval.STATUS_APPROVED)
                .set("authorizer_id", managerAdminId)
                .set("token_hash", tokenHash)
                .set("token_value", tokenEnvelope)
                .eq("id", approval.getId())
                .eq("status", AccessApproval.STATUS_PENDING));
        if (rows != 1) {
            throw new ApiException(409, "ACCESS_CONFLICT", "审批状态变更冲突，请刷新后重试");
        }

        log.info("[approval] qr approval granted: code={}, authorizer={}, expires={}",
                approvalCode, managerAdminId, approval.getExpires_at());

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("approvalCode", approvalCode);
        res.put("status", AccessApproval.STATUS_APPROVED);
        res.put("authorizerId", managerAdminId);
        res.put("authorizerName", com.lanf.util.AdminNameResolver.resolveDisplayName(manager));
        return res;
    }

    private void auditCredentialRejection(Integer shopId, Integer operatorId, String reasonCode) {
        if (securityAuditService == null) {
            return;
        }
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("credentialType", "approval");
        securityAuditService.recordRejected(null, shopId, "access", "approval_credential_rejected",
                null, operatorId, snapshot, 401, reasonCode);
    }

    private void auditPermissionRejection(Integer shopId, Integer authorizerId,
                                          String permission, String action) {
        if (securityAuditService == null) {
            return;
        }
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("requiredApprovalPermission", ApprovalPermissionPolicy.requiredPermission(permission));
        securityAuditService.recordRejected(null, shopId, "access", action,
                null, authorizerId, snapshot, 403, "ACCESS_PERMISSION_DENIED");
    }

    private String decryptAndVerifyQrToken(String approvalCode, AccessApproval approval) {
        String rawToken;
        try {
            rawToken = tokenEnvelopeCipher.decrypt(approvalCode, approval.getToken_value());
        } catch (IllegalStateException e) {
            log.error("[approval] qr token envelope invalid or unavailable: code={}, id={}",
                    approvalCode, approval.getId());
            String errorCode = tokenEnvelopeCipher.isConfigured()
                    ? "ACCESS_TOKEN_ENVELOPE_INVALID"
                    : "ACCESS_TOKEN_ENVELOPE_UNAVAILABLE";
            throw new ApiException(503, errorCode, "扫码授权令牌暂不可用，请重新发起授权");
        }
        String computedHash = sha256(rawToken);
        if (!constantTimeEquals(computedHash, approval.getToken_hash())) {
            log.error("[approval] qr token envelope hash mismatch: code={}, id={}", approvalCode, approval.getId());
            throw new ApiException(503, "ACCESS_TOKEN_ENVELOPE_INVALID", "扫码授权令牌校验失败，请重新发起授权");
        }
        return rawToken;
    }

    private boolean constantTimeEquals(String left, String right) {
        if (left == null || right == null) {
            return false;
        }
        return MessageDigest.isEqual(left.getBytes(StandardCharsets.US_ASCII),
                right.getBytes(StandardCharsets.US_ASCII));
    }

    private String generateToken() {
        byte[] randomBytes = new byte[32];
        SECURE_RANDOM.nextBytes(randomBytes);
        return bytesToHex(randomBytes);
    }

    private int normalizeBindingVersion(Integer bindingVersion) {
        int version = bindingVersion == null ? LEGACY_BINDING_VERSION : bindingVersion;
        if (version != LEGACY_BINDING_VERSION && version != STRICT_BINDING_VERSION) {
            throw new ApiException(400, "ACCESS_BINDING_VERSION_INVALID", "bindingVersion 仅支持 1 或 2");
        }
        return version;
    }

    private int normalizeStoredBindingVersion(Integer bindingVersion) {
        return bindingVersion == null ? LEGACY_BINDING_VERSION : bindingVersion;
    }

    private void validateIssuanceBinding(int bindingVersion, Integer operatorId, Integer shopId,
                                         String permission, String bizType, String bizId,
                                         String terminalId) {
        if (bindingVersion < STRICT_BINDING_VERSION) {
            return;
        }
        if (operatorId == null) {
            throw new ApiException(400, "ACCESS_OPERATOR_REQUIRED", "严格绑定授权缺少操作人");
        }
        if (shopId == null) {
            throw new ApiException(400, "ACCESS_SHOP_REQUIRED", "严格绑定授权缺少门店");
        }
        if (StringUtil.isEmpty(permission)) {
            throw new ApiException(400, "ACCESS_PERMISSION_REQUIRED", "严格绑定授权缺少动作权限码");
        }
        if (StringUtil.isEmpty(bizType)) {
            throw new ApiException(400, "ACCESS_RESOURCE_TYPE_REQUIRED", "严格绑定授权缺少资源类型");
        }
        if (isPlaceholderResource(bizId)) {
            throw new ApiException(400, "ACCESS_RESOURCE_REQUIRED", "严格绑定授权必须提供真实业务对象标识");
        }
        if (StringUtil.isEmpty(terminalId)) {
            throw new ApiException(400, "ACCESS_TERMINAL_REQUIRED", "严格绑定授权缺少终端标识");
        }
    }

    private boolean strictBindingMatches(AccessApproval approval, AccessContext ctx) {
        if (ctx.getShopId() == null || !ctx.getShopId().equals(approval.getShop_id())
                || ctx.getAdminId() == null || !ctx.getAdminId().equals(approval.getOperator_id())
                || StringUtil.isEmpty(ctx.getPermissionCode()) || !ctx.getPermissionCode().equals(approval.getPermission_code())
                || StringUtil.isEmpty(ctx.getResourceType()) || !ctx.getResourceType().equals(approval.getBiz_type())
                || isPlaceholderResource(ctx.getResourceId()) || !ctx.getResourceId().equals(approval.getBiz_id())
                || StringUtil.isEmpty(ctx.getTerminalId()) || !ctx.getTerminalId().equals(approval.getTerminal_id())
                || !strictAmountsMatch(approval, ctx)) {
            log.warn("[approval] strict binding mismatch: approvalNo={}, operator={}, shop={}, permission={}, resourceType={}, resourceId={}, terminal={}",
                    approval.getApproval_no(), ctx.getAdminId(), ctx.getShopId(), ctx.getPermissionCode(),
                    ctx.getResourceType(), ctx.getResourceId(), ctx.getTerminalId());
            return false;
        }
        return true;
    }

    private boolean strictAmountsMatch(AccessApproval approval, AccessContext ctx) {
        if (amountsEqual(ctx.getAmount(), approval.getAmount())) {
            return true;
        }
        // 销毁型操作（如订单删除）非金额变更业务，前端审批申请可能带入账单金额用于界面展示，
        // 在订单唯一标识（order_no）、门店、操作人及终端强绑定一致的前提下，允许金额自适应匹配
        if ("order:delete".equals(approval.getPermission_code())) {
            return true;
        }
        return false;
    }

    private boolean amountsEqual(BigDecimal left, BigDecimal right) {
        return left == null ? right == null : right != null && left.compareTo(right) == 0;
    }

    private boolean isPlaceholderResource(String resourceId) {
        return StringUtil.isEmpty(resourceId)
                || "N/A".equalsIgnoreCase(resourceId.trim())
                || resourceId.trim().toUpperCase().startsWith("ID:");
    }

    public static String sha256(String input) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(hash);
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 algorithm unavailable", e);
        }
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b & 0xff));
        }
        return sb.toString();
    }
}
