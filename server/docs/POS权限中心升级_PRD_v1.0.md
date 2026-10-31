# 收银系统权限中心升级 PRD

**文档版本**：v1.0

**目标版本建议**：POS Access Control v2

**适用系统**：运营后台 / 收银端 / KDS 管理端 / 连锁多门店后台

**设计原则**：在现有 RBAC + 门店数据范围体系上增量升级，不推翻现有权限表、角色体系和接口权限映射。



***

## 1. 项目背景

当前系统已经具备较完整的基础权限能力，包括：



* 管理员 JWT 登录；

* 用户 - 角色 - 权限码 RBAC；

* 一个员工绑定多个角色；

* HQ / REGION / SHOP 数据范围；

* 员工多门店授权；

* 角色权限覆盖式配置；

* 角色版本乐观锁；

* API 与权限码映射；

* 权限解释 `evaluate`；

* 操作日志与安全日志；

* 部分敏感操作 `confirm=true`；

* 日结重开、长短款场景存在 “店长二级密码授权”。

现阶段主要问题不是 “有没有权限系统”，而是现有权限判断仍以：

> 用户是否拥有 permissionCode

为核心，无法完整解决餐饮收银中的以下问题：



1. 同一个权限，不同员工可执行额度不同；

2. 高风险操作需要临时由店长授权，而不是永久加权限；

3. 退款、退菜、改价、折扣、赠送、抹零等资金风险操作粒度不足；

4. 用户能访问某门店，不代表能看到该门店所有字段和财务数据；

5. 权限修改后，旧 JWT 可能继续存活；

6. 员工离职更适合停用，而不是直接删除；

7. 一个员工同时拥有 “操作 + 审批” 可能形成职责冲突；

8. 权限后台容易演化成几百个技术权限 checkbox，业务人员难以配置；

9. 现有 “二级密码” 散落在日结、钱箱等模块，没有统一审批模型；

10. `confirm=true` 只能防误触，不能作为真正的身份二次授权。

因此，本次目标是把现有 RBAC 升级为：

> **RBAC + Data Scope + Policy + Approval + Audit**

最终回答的不再只是：

> “这个人有没有权限？”

而是：

> “这个人，在这家店，对这个业务对象，在当前金额 / 折扣 / 订单状态下，是否可以执行；若不能，谁可以临时授权；执行完成后是否能完整追责？”



***

# 2. 产品目标

## 2.1 核心目标

构建适用于单店与连锁门店的商用级权限中心，使系统支持：



* 细粒度业务权限；

* 数据范围控制；

* 金额 / 折扣等条件策略；

* 临时授权；

* 二次审批；

* 字段级敏感数据保护；

* 权限冲突检测；

* 即时权限失效；

* 员工生命周期管理；

* 完整审计追踪；

* 权限来源解释。



***

## 2.2 非目标

本期不建设：



* 企业级 IAM / SSO；

* LDAP / AD；

* OAuth 第三方组织身份；

* 跨租户权限共享；

* 无限自由表达式规则引擎；

* 工作流 BPMN。

本期策略条件保持餐饮 POS 业务可控范围，不做通用低代码权限引擎。



***

# 3. 用户角色

系统建议预置以下系统角色：



| 角色               | 定位         |
| ---------------- | ---------- |
| super\_admin     | 平台 / 最高管理员 |
| owner            | 老板 / 总部负责人 |
| region\_manager  | 区域经理       |
| store\_manager   | 店长         |
| cashier          | 收银员        |
| waiter           | 服务员        |
| kitchen\_manager | 厨房负责人      |
| finance          | 财务         |
| auditor          | 审计只读       |

系统角色分为：



* `SYSTEM`：系统预置角色；

* `CUSTOM`：商户自定义角色。

系统角色默认不可删除。是否允许修改权限，由角色级 `editable` 控制。



***

# 4. 权限模型

## 4.1 权限判断模型

统一权限判定：



```
Subject
  ↓
Role
  ↓
Permission
  ↓
Policy
  ↓
Scope
  ↓
Resource
  ↓
Approval
  ↓
Decision
```

统一决策函数：



```
Can(
  user,
  permission,
  shop,
  resource,
  context,
  approval
)
```

输出：



```
{
  "allow": true,
  "permissionGranted": true,
  "shopInScope": true,
  "policyPassed": true,
  "approvalRequired": false,
  "reasonCode": "ALLOW",
  "explanation": "..."
}
```



***

# 5. 权限分类

## 5.1 业务功能权限

权限码统一采用：



```
domain:action
```

必要时：



```
domain:subdomain:action
```

### 订单



```
order:view
order:create
order:add_item
order:item_void
order:void
order:transfer_table
order:merge
order:split
order:remark
order:reopen
```

### 退款



```
refund:view
refund:create
refund:partial
refund:full
refund:approve
```

### 价格和优惠



```
price:manual_override
discount:apply
discount:approve
gift:apply
rounding:apply
service_fee:modify
```

### 支付



```
payment:collect
payment:manual_confirm
payment:change_method
payment:reverse
payment:view_sensitive
```

### 钱箱



```
cash_drawer:open
cash_drawer:cash_in
cash_drawer:cash_out
cash_drawer:drop
cash_drawer:close
cash_drawer:variance_approve
```

### 日结



```
daily:view
daily:settle
daily:adjust
daily:reopen
daily:approve
```

### 会员



```
member:view
member:edit
member:recharge
member:balance_adjust
member:points_adjust
member:export
```

### 库存



```
inventory:view
inventory:inbound
inventory:outbound
inventory:adjust
inventory:cost_view
inventory:approve
```

### 财务与报表



```
report:view
report:profit_view
report:cost_view
report:export
reconciliation:view
reconciliation:manage
```

### 权限中心



```
access:view
access:manage
access:approve
access:audit
```



***

# 6. 策略 Policy

## 6.1 产品定义

Permission 解决 “有没有资格”，Policy 解决：

> 有资格以后，允许做到什么程度。

例如同样拥有 `discount:apply`：

### 收银员



```
max_discount_rate: 0.95
max_discount_amount: 30
```

### 店长



```
max_discount_rate: 0.80
max_discount_amount: 300
```



***

## 6.2 首期策略类型

### 金额策略



```
MAX_AMOUNT
```

用于：



* 退款；

* 赠送；

* 抹零；

* 现金支出；

* 会员余额调整。

### 折扣策略



```
MIN_DISCOUNT_RATE
MAX_DISCOUNT_AMOUNT
```

### 次数策略



```
MAX_DAILY_COUNT
```

例如：



* 单日最多手动开钱箱 5 次；

* 单日最多手动确认支付 10 次。

### 订单状态策略



```
ORDER_STATUS
```

例如：



* 已结账订单不可直接退菜；

* 已日结订单必须走退款 / 调整流程。

### 时间策略



```
TIME_WINDOW
```

例如：



* 财务导出仅工作时间允许；

* 某临时权限仅当天有效。



***

# 7. 高风险操作

系统将以下操作定义为 Risk Action。

## 7.1 P0 风险操作



* 整单退款；

* 大额部分退款；

* 已支付订单改价；

* 已支付订单取消；

* 手动修改支付方式；

* 手动确认 “已到账”；

* 钱箱现金支出；

* 钱箱长短款确认；

* 日结重开；

* 日结后财务调整；

* 会员余额人工调整；

* 删除 / 停用管理员；

* 修改角色权限；

* 修改员工门店范围；

* 日志导出；

* 财务报表导出。



***

# 8. 统一审批中心

## 8.1 产品目标

把目前散落在：



* 日结重开；

* 钱箱长短款；

* 其他 manager password；

中的授权能力统一。

所有业务模块不得自行实现第二套店长密码规则。



***

## 8.2 授权流程

示例：收银员整单退款 288 元。



```
点击退款
  ↓
权限引擎评估
  ↓
有 refund:full
  ↓
Policy 上限 100 元
  ↓
当前 288 > 100
  ↓
返回 APPROVAL_REQUIRED
  ↓
前端弹出店长授权
  ↓
店长 PIN / 密码验证
  ↓
生成 approval_token
  ↓
重新提交退款
  ↓
消费 approval_token
  ↓
执行退款
  ↓
审计日志
```



***

## 8.3 授权方式

首期支持：



1. 店长 PIN；

2. 店长账号密码；

3. 当前已登录店长确认。

后续可扩展：



* 扫员工码；

* NFC；

* 企业微信确认。



***

## 8.4 Approval Token

审批完成后，后端签发短期单次 Token：



```
{
  "approvalToken": "...",
  "permission": "refund:full",
  "operatorId": 22,
  "authorizerId": 8,
  "shopId": 3,
  "bizType": "order",
  "bizId": "88923",
  "maxAmount": 300,
  "expiresAt": "..."
}
```

规则：



* 默认 2 分钟有效；

* 默认 single-use；

* 绑定操作者；

* 绑定门店；

* 绑定业务对象；

* 绑定权限；

* 可绑定最大金额；

* 使用后立即失效；

* 不允许跨订单复用。



***

# 9. 临时授权

员工没有某权限时，不应必须去后台永久修改角色。

支持：



```
临时授权一次
临时授权本班次
临时授权至某时间
```

首期推荐仅实现：

### SINGLE\_USE

单次业务授权。

### UNTIL\_SHIFT\_END

当前班次内有效。



***

# 10. 字段级权限

## 10.1 产品目标

同一个 API 可以根据权限返回不同敏感字段。

例如供应商接口已有 “只有 manage 才可见 settlementInfo” 的思路，应扩展为统一字段策略。

## 10.2 字段权限建议

### 会员



```
member:phone_full_view
member:balance_view
member:recharge_view
member:consumption_view
```

### 财务



```
finance:cost_view
finance:gross_profit_view
finance:net_profit_view
finance:cash_view
finance:settlement_view
```

### 员工



```
employee:phone_view
employee:salary_view
employee:login_security_view
```

### 支付



```
payment:merchant_config_view
payment:merchant_secret_manage
```



***

# 11. 数据范围 Scope

保留现有：



```
HQ
REGION
SHOP
```

并增加 “功能权限与数据范围同时判定”。

例如：



```
report:view = true
scope = SHOP
shops = [1, 3]
```

只允许读取 1、3 店。

任何业务接口禁止仅依赖前端传 `X-Shop-Id`。

服务端必须：



```
请求门店 ∈ 当前管理员有效数据范围
```



***

# 12. ALLOW / DENY

现阶段已有权限解释中的 deny 规则描述，但没有显式 deny 数据。

本期建议增加显式：



```
ALLOW
DENY
```

同优先级：



```
DENY wins
```

优先级：



```
临时明确 DENY
>
员工级覆盖
>
自定义角色
>
系统角色
>
默认
```



***

# 13. 职责分离 SoD

角色保存 / 员工授权时进行权限冲突检查。

首期冲突规则：



```
refund:create × refund:approve
inventory:adjust × inventory:approve
cash_drawer:variance_create × cash_drawer:variance_approve
reconciliation:manage × reconciliation:approve
```

普通用户：



* HARD 冲突：禁止保存；

* SOFT 冲突：允许，但必须提示风险并记录审计。

super\_admin 可强制覆盖，但必须填写原因。



***

# 14. 权限即时失效

## 14.1 permission\_version

每个管理员增加：



```
permission_version
```

JWT 中写入：



```
permissionVersion
```

角色、门店范围、账号状态发生改变时：



```
permission_version = permission_version + 1
```

请求鉴权：



```
JWT.permissionVersion != DB.permission_version
→ ACCESS_PERMISSION_CHANGED
```

客户端：



1. 清理权限缓存；

2. 调 `/admin/me/permissions`；

3. 如账号禁用则退出登录。



***

# 15. 员工生命周期

员工状态：



```
ACTIVE
DISABLED
LOCKED
RESIGNED
```

默认不再使用 “删除员工” 作为离职处理。

## 15.1 停用

停用后：



* 立即禁止登录；

* 当前会话失效；

* 保留历史业务数据；

* 保留审计操作者 ID；

* 保留历史角色快照；

* 不参与排班选择。

## 15.2 删除

仅允许：



* 误创建；

* 没有关联任何业务；

* 无审计记录；

* 无订单；

* 无班次；

* 无审批记录。

否则返回：



```
ACCESS_EMPLOYEE_HAS_HISTORY
```

建议前端提示：

> 该员工已有业务记录，不能删除，可改为离职 / 停用。



***

# 16. 登录安全

增加：



* failed\_login\_count；

* locked\_until；

* last\_login\_at；

* last\_login\_ip；

* last\_login\_device；

* password\_changed\_at；

* force\_logout\_at。

后台功能：



* 停用；

* 解除锁定；

* 重置密码；

* 强制下线；

* 查看最近登录。



***

# 17. 权限中心后台 IA

一级菜单：



```
权限中心
├─ 员工
├─ 角色
├─ 权限策略
├─ 审批记录
├─ 权限解释
└─ 安全日志
```

技术 API 映射放到：



```
系统开发设置
└─ 接口权限映射
```

普通店长不得看到 API Path / Method。



***

# 18. 员工页面

列表字段：



* 姓名；

* 状态；

* 角色；

* 所属门店；

* 最近登录；

* 是否在线；

* 风险标记。

操作：



* 编辑角色；

* 编辑门店范围；

* 临时授权；

* 停用；

* 强制下线；

* 重置密码；

* 查看权限；

* 查看授权记录；

* 查看操作日志。



***

# 19. 角色页面

创建 / 编辑角色时展示 “业务权限树”，而非接口列表。

例如：



```
订单
☑ 查看订单
☑ 开单
☑ 加菜
☑ 退菜
☐ 整单取消

退款
☑ 部分退款
☐ 整单退款

价格
☑ 使用折扣
  最低折扣：[95] %
  单笔最大优惠：[30] 元
```



***

# 20. 权限解释页面

输入：



* 员工；

* 门店；

* 权限；

* 可选业务对象。

结果：



```
最终：允许

功能权限：允许
来源：店长角色
数据范围：深圳宝安店
策略：退款上限 300 元
当前金额：128 元
审批：无需
DENY：无
```

拒绝：



```
最终：拒绝

原因：
当前退款 500 元
角色策略最大退款 300 元

可处理方式：
请求 owner 临时授权
```



***

# 21. 审批记录

字段：



* approvalNo；

* 操作者；

* 授权者；

* 门店；

* 权限；

* 业务类型；

* 业务 ID；

* 金额；

* 原因；

* 授权方式；

* 创建时间；

* 使用时间；

* 状态。

状态：



```
PENDING
APPROVED
REJECTED
CONSUMED
EXPIRED
REVOKED
```



***

# 22. 审计要求

以下事件必须审计：



* 角色新增 / 编辑 / 删除；

* 权限变化；

* 员工角色变化；

* 数据范围变化；

* 员工停用 / 启用；

* 密码重置；

* 强制下线；

* 高危业务操作；

* 临时授权；

* 授权失败；

* SoD 冲突强制覆盖；

* 报表导出；

* 日志导出。

日志中记录：



```
operator_id
authorizer_id
shop_id
permission
resource_type
resource_id
before_snapshot
after_snapshot
reason
request_id
ip
terminal_id
created_at
```



***

# 23. 默认角色建议

## 收银员

允许：



* 开单；

* 加菜；

* 收款；

* 查看本店订单；

* 小额折扣；

* 小额退菜；

* 交班。

限制：



* 不可看成本；

* 不可看利润；

* 不可日结重开；

* 不可整单大额退款；

* 不可改权限；

* 不可改支付配置。

## 店长

增加：



* 退款授权；

* 折扣授权；

* 长短款审批；

* 日结；

* 日结重开；

* 门店员工授权；

* 门店库存调整。

## 老板

增加：



* 多店数据；

* 成本 / 利润；

* 角色管理；

* 财务；

* 高额度审批。



***

# 24. 兼容策略

现有：



```
t_role
t_permission
t_role_permission
t_api_permission
管理员-角色
管理员-门店
```

全部保留。

新增 Policy / Approval / Override 能力，不修改 permission\_code 的基本语义。

旧接口继续通过原 permission 判断。

新高风险接口逐步接入统一 AccessDecisionService。



***

# 25. 分阶段上线

## Phase 1 / P0



* 权限码重新拆分；

* 店长审批中心；

* approval\_token；

* permission\_version；

* 员工 DISABLED / RESIGNED；

* 高危退款 / 折扣 / 改价接入；

* 审批审计。

## Phase 2 / P1



* Policy；

* 字段级权限；

* SoD；

* 临时授权；

* 强制下线。

## Phase 3 / P2



* ALLOW/DENY；

* 权限解释增强；

* 权限模板；

* 风险看板。



***

# 26. 验收标准

### 权限



* 无权限直接调用 API 必须被后端拒绝；

* 前端隐藏不视为权限控制；

* 门店范围不可通过修改 Header 越权。

### Policy



* 95 折权限用户输入 9 折必须返回 APPROVAL\_REQUIRED 或 DENY；

* 退款额度不可由客户端修改绕过。

### Approval



* Token 不可跨用户；

* 不可跨门店；

* 不可跨订单；

* 不可重复消费；

* 过期失效。

### 员工



* 停用后所有有效 Token 立即失效；

* 历史订单仍显示原操作者。

### 审计



* 任意高危操作可定位：


  * 谁操作；

  * 谁授权；

  * 对什么业务；

  * 修改前后；

  * 原因；

  * 时间；

  * 门店。



***

# 27. 产品最终原则

权限系统不应该只回答：

> “有没有 permissionCode？”

最终应回答：

> **谁，在什么门店，对什么资源，在什么条件下，可以做什么；如果超出权限，由谁授权；授权只适用于什么范围；执行后谁负责。**