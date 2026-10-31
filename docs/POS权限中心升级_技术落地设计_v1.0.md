# 收银系统权限中心升级——技术落地设计

**文档版本**：v1.0  
**架构方式**：现有 RBAC 增量升级  
**核心组件**：RBAC / Scope / Policy / Approval / Session Version / Audit

---

# 1. 技术目标

在不破坏现有：

```text
t_admin
t_role
t_permission
t_role_permission
t_api_permission
管理员角色关系
管理员门店关系
JWT
X-Shop-Id / X-Shop-Code
```

的情况下新增：

- 策略约束；
- 审批授权；
- 临时授权；
- 显式 DENY；
- 权限版本；
- 员工状态；
- 会话失效；
- SoD；
- 统一决策服务。

---

# 2. 目标架构

```text
HTTP Request
   ↓
AuthenticationFilter
   ↓
AccountStatusGuard
   ↓
PermissionVersionGuard
   ↓
ShopScopeGuard
   ↓
ApiPermissionResolver
   ↓
AccessDecisionService
   ├─ RBAC Resolver
   ├─ Explicit Override Resolver
   ├─ Policy Engine
   ├─ Approval Resolver
   ├─ SoD Guard
   └─ Field Mask Resolver
   ↓
Business Service
   ↓
Audit Service
```

原则：

> Controller 不自行拼接权限规则。

所有高风险业务统一调用：

```java
accessDecisionService.check(...)
```

---

# 3. 核心数据结构

## 3.1 t_admin 扩展

建议新增：

```sql
ALTER TABLE t_admin
ADD COLUMN account_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
ADD COLUMN permission_version BIGINT NOT NULL DEFAULT 1,
ADD COLUMN failed_login_count INT NOT NULL DEFAULT 0,
ADD COLUMN locked_until DATETIME NULL,
ADD COLUMN last_login_at DATETIME NULL,
ADD COLUMN last_login_ip VARCHAR(64) NULL,
ADD COLUMN password_changed_at DATETIME NULL,
ADD COLUMN force_logout_at DATETIME NULL;
```

account_status：

```text
ACTIVE
DISABLED
LOCKED
RESIGNED
```

---

# 4. 角色扩展

`t_role`：

```sql
ALTER TABLE t_role
ADD COLUMN role_type VARCHAR(20) NOT NULL DEFAULT 'CUSTOM',
ADD COLUMN editable TINYINT NOT NULL DEFAULT 1,
ADD COLUMN system_protected TINYINT NOT NULL DEFAULT 0,
ADD COLUMN priority INT NOT NULL DEFAULT 100;
```

---

# 5. Policy 表

## 5.1 t_access_policy

```sql
CREATE TABLE t_access_policy (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  policy_code VARCHAR(100) NOT NULL UNIQUE,
  policy_name VARCHAR(100) NOT NULL,
  permission_code VARCHAR(100) NOT NULL,
  policy_type VARCHAR(50) NOT NULL,
  effect VARCHAR(10) NOT NULL DEFAULT 'ALLOW',
  priority INT NOT NULL DEFAULT 100,
  enabled TINYINT NOT NULL DEFAULT 1,
  config_json JSON NOT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);
```

例：

```json
{
  "maxAmount": 100,
  "currency": "CNY"
}
```

折扣：

```json
{
  "minDiscountRate": 0.95,
  "maxDiscountAmount": 30
}
```

---

# 6. Policy 绑定

## 6.1 角色策略

```sql
CREATE TABLE t_role_policy (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  role_id BIGINT NOT NULL,
  policy_id BIGINT NOT NULL,
  shop_id BIGINT NULL,
  UNIQUE KEY uk_role_policy_shop(role_id, policy_id, shop_id)
);
```

## 6.2 员工级覆盖

```sql
CREATE TABLE t_admin_permission_override (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  admin_id BIGINT NOT NULL,
  permission_code VARCHAR(100) NOT NULL,
  effect VARCHAR(10) NOT NULL,
  shop_id BIGINT NULL,
  policy_json JSON NULL,
  valid_from DATETIME NULL,
  valid_until DATETIME NULL,
  source VARCHAR(30) NOT NULL,
  reason VARCHAR(255) NULL,
  created_by BIGINT NOT NULL,
  created_at DATETIME NOT NULL,
  INDEX idx_admin_perm(admin_id, permission_code, shop_id)
);
```

effect：

```text
ALLOW
DENY
```

source：

```text
MANUAL
TEMP_GRANT
SECURITY_BLOCK
```

---

# 7. 审批表

## 7.1 t_access_approval

```sql
CREATE TABLE t_access_approval (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  approval_no VARCHAR(64) NOT NULL UNIQUE,

  permission_code VARCHAR(100) NOT NULL,

  operator_id BIGINT NOT NULL,
  authorizer_id BIGINT NOT NULL,
  shop_id BIGINT NOT NULL,

  biz_type VARCHAR(50) NOT NULL,
  biz_id VARCHAR(100) NOT NULL,

  amount DECIMAL(12,2) NULL,
  reason VARCHAR(500) NOT NULL,

  auth_method VARCHAR(30) NOT NULL,

  status VARCHAR(20) NOT NULL,

  token_hash CHAR(64) NULL,
  max_amount DECIMAL(12,2) NULL,

  expires_at DATETIME NOT NULL,
  consumed_at DATETIME NULL,

  request_id VARCHAR(128) NULL,
  terminal_id VARCHAR(100) NULL,

  created_at DATETIME NOT NULL,

  INDEX idx_operator(operator_id),
  INDEX idx_biz(biz_type, biz_id),
  INDEX idx_expire(status, expires_at)
);
```

状态：

```text
APPROVED
CONSUMED
EXPIRED
REVOKED
REJECTED
```

---

# 8. Approval Token

不要直接把数据库 ID 当 token。

生成：

```text
random 256-bit secret
```

客户端得到原始 token。

数据库只存：

```text
SHA-256(token)
```

验证流程：

```text
hash(requestToken)
↓
查 t_access_approval.token_hash
↓
status == APPROVED
↓
expires_at > now
↓
operator/shop/biz/permission 匹配
↓
金额 <= max_amount
↓
CAS 更新 APPROVED → CONSUMED
```

SQL 必须保证单次消费：

```sql
UPDATE t_access_approval
SET status='CONSUMED', consumed_at=NOW()
WHERE id=?
  AND status='APPROVED'
  AND expires_at > NOW();
```

affected rows != 1：

```text
APPROVAL_INVALID_OR_CONSUMED
```

---

# 9. 权限决策上下文

统一 DTO：

```java
public class AccessContext {
    Long adminId;
    Long shopId;

    String permissionCode;

    String resourceType;
    String resourceId;

    BigDecimal amount;
    BigDecimal discountRate;

    String orderStatus;
    String paymentStatus;

    String terminalId;
    String requestId;

    String approvalToken;

    Map<String, Object> attributes;
}
```

---

# 10. 决策输出

```java
public class AccessDecision {
    boolean allow;

    boolean permissionGranted;
    boolean shopInScope;
    boolean policyPassed;
    boolean approvalRequired;

    String reasonCode;
    String explanation;

    List<String> matchedRoles;
    List<String> matchedPolicies;

    ApprovalRequirement approval;
}
```

---

# 11. AccessDecisionService

伪代码：

```java
Decision evaluate(ctx) {

  Admin admin = adminService.requireActive(ctx.adminId);

  permissionVersionGuard.verify(admin);

  if (!scopeService.canAccess(admin, ctx.shopId)) {
      return deny("SHOP_OUT_OF_SCOPE");
  }

  PermissionResult base =
      rbacService.resolve(admin, ctx.permissionCode);

  OverrideResult override =
      overrideService.resolve(admin, ctx);

  if (override.hasDeny()) {
      return deny("EXPLICIT_DENY");
  }

  if (!base.allow() && !override.hasAllow()) {
      return deny("PERMISSION_DENIED");
  }

  PolicyResult policy =
      policyEngine.evaluate(admin, ctx);

  if (policy.pass()) {
      return allow();
  }

  if (policy.approvable()) {

      if (approvalService.validate(ctx.approvalToken, ctx)) {
          return allow("APPROVED_OVERRIDE");
      }

      return approvalRequired(policy.requirement());
  }

  return deny(policy.reason());
}
```

---

# 12. Policy Engine

首期不要实现动态脚本语言。

使用枚举 Handler：

```text
MAX_AMOUNT
MIN_DISCOUNT_RATE
MAX_DISCOUNT_AMOUNT
MAX_DAILY_COUNT
ORDER_STATUS
TIME_WINDOW
```

接口：

```java
interface AccessPolicyHandler {
    String type();
    PolicyResult evaluate(AccessPolicy policy, AccessContext ctx);
}
```

优势：

- 类型安全；
- 可测试；
- 无脚本执行安全风险；
- 规则可逐步扩展。

---

# 13. ScopeService

现有 HQ / REGION / SHOP 延续。

统一：

```java
boolean canAccess(
  AdminPrincipal principal,
  Long shopId
)
```

规则：

### HQ

允许租户内门店。

### REGION

shop.region_id ∈ principal.regionIds。

### SHOP

shop.id ∈ principal.shopIds。

任何 Controller 禁止自己判断。

---

# 14. API 权限拦截

现有 `t_api_permission` 保留。

建议：

```text
URL + HTTP Method
→ Permission Requirement
```

但业务高风险条件不能写在 t_api_permission。

例如：

```text
POST /cashier/refund
→ refund:create
```

金额判断必须在：

```text
AccessDecisionService
```

否则 API 权限表会失控。

---

# 15. 业务接入示例：退款

Controller：

```java
@PostMapping("/cashier/refund")
public R refund(@RequestBody RefundRequest req) {

    AccessContext ctx = AccessContext.builder()
        .adminId(currentAdminId())
        .shopId(currentShopId())
        .permissionCode(
             req.isFullRefund()
               ? "refund:full"
               : "refund:partial")
        .resourceType("ORDER")
        .resourceId(req.getOrderId().toString())
        .amount(req.getAmount())
        .approvalToken(req.getApprovalToken())
        .requestId(requestId())
        .build();

    AccessDecision d = accessDecisionService.evaluate(ctx);

    accessGuard.requireAllow(d);

    return refundService.refund(req);
}
```

如果需要审批：

HTTP 403/409 建议返回：

```json
{
  "code": 40320,
  "msg": "APPROVAL_REQUIRED",
  "data": {
    "permission": "refund:full",
    "reason": "REFUND_AMOUNT_EXCEEDED",
    "currentAmount": 288,
    "allowedAmount": 100,
    "requiredRole": ["store_manager", "owner"]
  }
}
```

前端弹授权框。

---

# 16. Approval API

## 发起授权验证

```http
POST /cashier/access/authorize
```

Request：

```json
{
  "permission": "refund:full",
  "bizType": "ORDER",
  "bizId": "88923",
  "amount": 288,
  "reason": "顾客投诉整单退款",
  "authorizerAccount": "manager01",
  "credential": "******"
}
```

服务端：

1. 查授权人；
2. 校验 ACTIVE；
3. 校验门店；
4. 校验授权人权限；
5. 校验其 Policy；
6. 创建 approval；
7. 返回 token。

---

# 17. 授权资格

不是“知道店长密码就可以”。

授权人必须：

```text
ACTIVE
+
shop scope 有效
+
拥有目标 approve 权限
+
自身 Policy 足够覆盖本次金额
```

例如退款：

操作者：

```text
refund:full
```

授权者：

```text
refund:approve
```

避免同一个 permission 既操作又审批。

---

# 18. PIN 设计

建议新增：

```text
manager_pin_hash
```

不要存明文 PIN。

使用：

- bcrypt；
- Argon2；

并增加：

```text
pin_failed_count
pin_locked_until
```

PIN 只用于本地二次授权，不替代账号密码。

---

# 19. permission_version

JWT Payload：

```json
{
  "adminId": 8,
  "permissionVersion": 23,
  "iat": 123,
  "exp": 456
}
```

鉴权时：

```text
JWT.permissionVersion
vs
t_admin.permission_version
```

缓存优化：

```text
Redis admin:permver:{id}
```

修改角色/员工范围后：

```text
DB ++
Redis update
```

---

# 20. 哪些动作增加 permission_version

以下操作必须 bump：

- 员工角色变化；
- 员工门店变化；
- scope 变化；
- 显式 override；
- 账号停用；
- 离职；
- 权限角色绑定变化；
- 角色删除；
- super_admin 降权。

角色权限修改后，应批量 bump 绑定该角色的管理员。

---

# 21. 会话失效

建议增加 Redis Session Registry：

```text
admin:sessions:{adminId}
```

每个登录 Session：

```json
{
  "jti": "...",
  "device": "...",
  "createdAt": "...",
  "lastSeen": "..."
}
```

强制下线：

```text
revoke JTI
```

所有会话下线：

```text
force_logout_at = now
```

JWT iat < force_logout_at：

```text
TOKEN_REVOKED
```

---

# 22. 员工状态

Authentication 前置校验：

```text
DISABLED → 403 ACCOUNT_DISABLED
RESIGNED → 403 ACCOUNT_RESIGNED
LOCKED → 423 ACCOUNT_LOCKED
```

无论 JWT 是否仍有效均拒绝。

---

# 23. 删除员工改造

现有 DELETE 接口建议保留兼容，但内部增加：

```java
employeeHistoryService.hasBusinessHistory(adminId)
```

检查：

- t_operation_log；
- t_order.order_admin_id；
- t_shift；
- t_access_approval；
- t_daily_adjustment；
- 退款/现金等。

有记录：

```text
409 ACCESS_EMPLOYEE_HAS_HISTORY
```

推荐前端展示“改为离职”。

新增：

```http
PUT /admin/access/employees/{id}/status
```

---

# 24. 字段权限

不要为每个字段开发一套 DTO。

推荐：

```java
SensitiveFieldMaskService
```

例如：

```java
if (!access.has("member:phone_full_view")) {
    member.setPhone(maskPhone(member.getPhone()));
}
```

建议注解扩展：

```java
@SensitiveField(
  permission = "member:phone_full_view",
  mask = PHONE
)
```

后期统一序列化处理。

---

# 25. SoD 数据表

```sql
CREATE TABLE t_access_conflict_rule (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  permission_a VARCHAR(100) NOT NULL,
  permission_b VARCHAR(100) NOT NULL,
  severity VARCHAR(20) NOT NULL,
  enabled TINYINT NOT NULL DEFAULT 1,
  message VARCHAR(255),
  UNIQUE KEY uk_conflict(permission_a, permission_b)
);
```

severity：

```text
HARD
SOFT
```

角色保存时：

```text
collect effective permissions
↓
pair match
↓
HARD → reject
↓
SOFT → warning / require force reason
```

---

# 26. 显式 DENY

员工 override：

```text
effect=DENY
```

优先级建议：

```text
SECURITY DENY 1000
ADMIN OVERRIDE 900
TEMP GRANT 800
CUSTOM ROLE 500
SYSTEM ROLE 400
DEFAULT 0
```

同优先级：

```text
DENY > ALLOW
```

---

# 27. 权限解释升级

现有 evaluate API 保留：

```http
POST /admin/access/evaluate
```

扩展 Request：

```json
{
  "userId": 12,
  "shopId": 3,
  "permission": "refund:full",
  "context": {
    "amount": 500,
    "resourceType": "ORDER",
    "resourceId": "88923"
  }
}
```

Response：

```json
{
  "allow": false,
  "permissionGranted": true,
  "shopInScope": true,
  "policyPassed": false,
  "approvalRequired": true,

  "matchedRoles": [
    {
      "roleCode": "cashier",
      "effect": "ALLOW"
    }
  ],

  "matchedPolicies": [
    {
      "type": "MAX_AMOUNT",
      "limit": 100,
      "actual": 500
    }
  ],

  "approval": {
    "required": true,
    "permission": "refund:approve"
  },

  "explanation": "拥有整单退款权限，但单笔退款额度上限100元，本次500元，需要店长审批"
}
```

---

# 28. 审计统一

建议新建统一结构，不要求替换现有 t_operation_log。

可以新增：

```text
audit_detail_json
```

保存：

```json
{
  "permission": "refund:full",
  "decision": "APPROVED_OVERRIDE",
  "operatorId": 12,
  "authorizerId": 3,
  "approvalNo": "...",
  "resourceType": "ORDER",
  "resourceId": "88923",
  "amount": 288,
  "before": {},
  "after": {}
}
```

---

# 29. 事务边界

Approval 的 CONSUME 与业务操作必须保证一致性。

推荐：

```text
业务事务开始
↓
锁定 approval / CAS consume
↓
执行退款
↓
写业务账本
↓
写 audit
↓
COMMIT
```

如果退款失败：

Approval 不应永久丢失。

可选方案 A：

- approval consume 与业务同事务；

优先推荐。

---

# 30. 幂等

高风险业务接口要求：

```text
X-Client-Request-Id
```

服务端：

```text
operator + permission + resource + requestId
```

做幂等。

防止：

- 双击退款；
- 网络重试重复审批；
- POS 卡顿重复提交。

---

# 31. 前端状态机

调用业务 API：

```text
REQUEST
↓
ALLOW → success
↓
APPROVAL_REQUIRED
↓
打开 ApprovalDialog
↓
提交店长凭证
↓
获得 approvalToken
↓
重试原业务请求
↓
success
```

前端不得自己判断金额阈值作为权威。

前端可以提前提示，但最终以后端为准。

---

# 32. 前端权限缓存

前端缓存：

```text
permissions
roles
scope
shops
regionIds
permissionVersion
```

当 API 返回：

```text
ACCESS_PERMISSION_CHANGED
```

执行：

```text
GET /admin/me/permissions
```

刷新。

如果：

```text
ACCOUNT_DISABLED
TOKEN_REVOKED
```

立即退出。

---

# 33. API 建议

新增：

```text
GET  /admin/access/policies
POST /admin/access/policies
PUT  /admin/access/policies/{id}
DELETE /admin/access/policies/{id}

POST /cashier/access/authorize

GET /admin/access/approvals
GET /admin/access/approvals/{id}

PUT /admin/access/employees/{id}/status
POST /admin/access/employees/{id}/force-logout

GET /admin/access/employees/{id}/effective-permissions

POST /admin/access/conflicts/check
```

扩展：

```text
POST /admin/access/evaluate
GET /admin/me/permissions
```

---

# 34. 错误码

建议统一：

```text
ACCESS_PERMISSION_DENIED
ACCESS_SHOP_OUT_OF_SCOPE
ACCESS_POLICY_DENIED
ACCESS_APPROVAL_REQUIRED
ACCESS_APPROVAL_INVALID
ACCESS_APPROVAL_EXPIRED
ACCESS_APPROVAL_CONSUMED
ACCESS_PERMISSION_CHANGED
ACCESS_ACCOUNT_DISABLED
ACCESS_ACCOUNT_RESIGNED
ACCESS_ACCOUNT_LOCKED
ACCESS_ROLE_CONFLICT
ACCESS_EMPLOYEE_HAS_HISTORY
ACCESS_SESSION_REVOKED
```

---

# 35. 迁移策略

## Step 1

先建立新表，不切业务。

## Step 2

给现有角色初始化 Policy。

例如 cashier：

```text
refund amount = 0 or very low
discount >= 0.95
```

## Step 3

接入一个高风险场景：

```text
整单退款
```

验证统一审批中心。

## Step 4

接：

- 折扣；
- 改价；
- 钱箱；
- 日结；
- 会员余额。

## Step 5

把原有模块内部 manager password 迁移到 ApprovalService。

## Step 6

旧二级密码逻辑进入兼容期后下线。

---

# 36. 性能

普通请求不能每次查 6~10 张表。

推荐缓存 Effective Access Snapshot：

```text
access:snapshot:{adminId}:{shopId}:{permissionVersion}
```

缓存：

```json
{
  "permissions": [],
  "policies": {},
  "roles": [],
  "scope": {}
}
```

角色/权限变化通过 permission_version 自动换 Key。

无需复杂缓存失效广播。

---

# 37. 安全

- PIN/密码只保存 hash；
- approval token 数据库存 hash；
- 日志不得记录密码/PIN/token 原文；
- approval token 单次消费；
- 所有敏感接口必须 Bearer；
- shopId 永远服务端 scope 校验；
- 金额全部服务端从业务数据复核；
- 前端提交 amount 只能作为请求意图，不作为最终真实金额；
- authorizerId 不允许客户端直接指定为可信身份；
- 授权人身份必须通过 credential 解析。

---

# 38. 重点风险：不要信任 approved_by

现有类似：

```text
approved_by: 管理员ID
```

的业务参数不应作为授权证明。

客户端传：

```json
{
  "approved_by": 1
}
```

不能代表管理员 1 真正授权。

新设计必须：

```text
approval_token
```

服务端从 token 反查：

```text
authorizer_id
```

业务表中的 approved_by 由服务器写入。

---

# 39. 测试矩阵

必须覆盖：

### RBAC

- 无角色；
- 单角色；
- 多角色；
- 角色权限更新。

### Scope

- SHOP 越店；
- REGION 越区域；
- HQ。

### Policy

- 刚好等于额度；
- 超 0.01；
- 折扣边界；
- 空金额。

### Approval

- 正常；
- 过期；
- 重复；
- 跨订单；
- 跨门店；
- 跨操作者；
- 金额超授权额度。

### Session

- 权限修改；
- 停用；
- 强制下线；
- JWT 旧 version。

### SoD

- HARD；
- SOFT；
- super_admin override。

---

# 40. 发布检查

上线前：

1. 全量 API 权限映射扫描；
2. 无 permission 的后台写接口报告；
3. 所有高危接口列清单；
4. 所有 `approved_by` 客户端字段审计；
5. 所有 manager password 散点逻辑审计；
6. 所有 delete employee 逻辑审计；
7. 所有 shopId 查询必须经过 scope；
8. 导出类接口单独复核；
9. 财务字段脱敏复核；
10. 旧 JWT 升级策略验证。

---

# 41. 推荐代码模块

```text
security/
  authentication/
  authorization/
    AccessDecisionService
    RbacResolver
    ScopeResolver
    OverrideResolver
    PolicyEngine
    ApprovalService
    ConflictService
    PermissionVersionService
  audit/
  sensitive/
```

---

# 42. 最终落地原则

### 权限码

回答：

> 能不能做这个动作。

### Scope

回答：

> 可以在哪些门店做。

### Policy

回答：

> 可以做到什么程度。

### Approval

回答：

> 超限时谁可以授权。

### permission_version

回答：

> 权限变化什么时候真正生效。

### Audit

回答：

> 事后能否完整追责。

最终所有高风险业务统一使用：

```text
AccessDecisionService
```

而不是：

```text
if (role == manager)
```

或：

```text
if (password correct)
```

这样现有权限系统可以逐步演进成可支持单店、直营连锁和多层级组织的商用 POS 权限架构。
