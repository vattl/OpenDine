# Impact Map — WI-063

## Authoritative Owners
- 动作决策：`AccessDecisionService`。
- HTTP 高风险动作授权编排：新增共享动作授权门面。
- 审批签发/核销：`ApprovalService`。
- 业务金额与订单状态：既有订单/结账服务，不在本项重写。

## Change Propagation Path
```text
cashier:operate HTTP entry
→ exact action context
→ unified decision
→ ALLOW | REQUIRE_APPROVAL | DENY
→ optional strict onsite/QR approval
→ one-time token consumption
→ business mutation
```

## Layer Coverage
| Layer | Classification | Reason |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | 本仓库无生产 UI |
| Frontend/API client | AFFECTED | 需处理统一三态及动作级权限 |
| Request/response contract | AFFECTED_COMPATIBLE | 保留旧字段，补充标准授权结果 |
| Controllers | AFFECTED | 五个收银入口及运营退款迁移 |
| Domain/security | AFFECTED | 新增共享授权编排门面 |
| Persistence | AFFECTED | 精确执行/审批角色迁移 |
| Funds/order rules | VERIFIED_PRESERVED | 仅前置授权，不改变资金算法 |
| KDS | VERIFIED_UNAFFECTED | 不修改 KDS 权威、API、复制或容灾 |

## Consumers
| Consumer | Status | Obligation |
|---|---|---|
| Flutter 收银端 | HANDOFF | 按动作请求审批并携带严格绑定 token |
| 管理后台 | HANDOFF | 微信退款处理 REQUIRE_APPROVAL/DENY |
| 部署 | AFFECTED | 应用 V042 后再切换新 JAR |

## Risks
- 旧角色只拥有宽泛权限时可能失去直接执行权；V042 仅为明确管理角色回填，收银员走审批。
- 现场授权若仍走旧直验会绕过三态；共享门面必须通过 ApprovalService 签发并立即核销。
- 授权先于订单加载时金额可能来自客户端；退款金额必须使用请求执行金额绑定，后续 WI-066 统一价格模型不在本项范围。
