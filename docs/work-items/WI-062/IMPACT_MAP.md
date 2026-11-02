# Impact Map — WI-062

## Authoritative Owners
- 业务授权决策：`AccessDecisionService`。
- 动作权限词汇：新增单一目录类。
- 接口入口映射：运行时 `t_api_permission` / `DbApiPermissionMapping`。
- `ApiPermissionMapping`：只读清单与差异验证，不参与请求授权。

## Change Propagation Path
```text
operator + shop + action + context
→ account/shop/override checks
→ action vocabulary (entry/action/approval)
→ RBAC + policy + approval token
→ ALLOW | REQUIRE_APPROVAL | DENY

HTTP route
→ t_api_permission cache
→ permission check
→ allow or fail closed
```

## Layer Coverage
| Layer | Classification | Reason |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | 本仓库无生产 UI 修改 |
| Frontend state/API client | AFFECTED | 新增 `outcome`，应以三态驱动审批交互 |
| Request contract | VERIFIED_COMPATIBLE | 不新增必填字段 |
| Response contract | AFFECTED | `outcome` 为新增字段，旧布尔字段保留 |
| Backend/domain | AFFECTED | 决策流程和词汇目录收敛 |
| Persistence | AFFECTED | 初始化权限映射必须与清单一致 |
| Security/config | AFFECTED | 移除内置运行时兜底，缺失即拒绝 |
| Tests/CI | AFFECTED | 新增三态和映射差异门禁 |
| KDS | VERIFIED_UNAFFECTED | 不修改 KDS 鉴权、API、复制或故障转移 |

## Consumer Coverage
| Consumer | Classification | Obligation |
|---|---|---|
| Flutter 收银端 | HANDOFF | 读取 `outcome`，REQUIRE_APPROVAL 打开授权流程，DENY 不重试 |
| 后台权限解释页 | HANDOFF | 显示三态与原因，兼容旧布尔值 |
| 运维/部署 | AFFECTED | 确保 Flyway/初始化数据完整；映射缺失将失败关闭 |
| WI-063 高风险动作迁移 | DEPENDENT | 复用词汇和决策器，不自行拼装二次授权 |

## Risks
- DB 数据缺失会暴露为 403；通过迁移/清单差异测试前置发现。
- 客户端只看 `allow=false` 可能把 REQUIRE_APPROVAL 当硬拒绝；保留 `approvalRequired` 并提供交接。
- 本项不切换四个业务 Controller，避免将基础设施改造与动作迁移混为一体。

