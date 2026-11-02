# Scenario Matrix — WI-062

| ID | Family | Context | Expected | Verification | Result |
|---|---|---|---|---|---|
| S01 | direct grant | 拥有动作执行权限 | ALLOW，兼容布尔一致 | unit test | PASS |
| S02 | initiate approval | 仅有 `cashier:operate`，敏感动作无 token | REQUIRE_APPROVAL | unit test | PASS |
| S03 | approval consume | 仅入口权限 + 严格有效 token | ALLOW/APPROVED_OVERRIDE | unit test | PASS |
| S04 | invalid approval | 仅入口权限 + 无效 token | DENY，不绕过 | unit test | PASS |
| S05 | no entry | 无动作权限且无入口权限 | DENY | unit test | PASS |
| S06 | explicit deny | 动作或入口显式 DENY | DENY | regression | PASS |
| S07 | cross action | 只有退款权限请求改价 | REQUIRE_APPROVAL，绝不直接 ALLOW | unit test | PASS |
| S08 | response | evaluate 无/有 context | 都含唯一 outcome，旧字段一致 | service/model test | PASS |
| S09 | DB mapping | DB 命中 | 按 DB 权限校验 | interceptor test | PASS |
| S10 | missing mapping | DB 未命中、代码清单命中 | 403 mapping missing | interceptor test | PASS |
| S11 | reload failure | 已有快照后 DB 重载失败 | 保留旧快照并告警 | mapping test | PASS |
| S12 | inventory drift | V041 与代码清单差异 | CI test 失败 | contract test | PASS |
| S13 | compatibility | 旧客户端只读布尔字段 | 仍可区分 allow/approvalRequired | regression/docs | PASS |

