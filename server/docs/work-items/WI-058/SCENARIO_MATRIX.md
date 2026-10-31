# Scenario Matrix — WI-058

| ID | Family | Input / Context | Expected business outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | normal | JSON 与 Markdown 包含相同 invariant IDs | 一致性校验通过 | ALL | `validate_business_rules.py` | PASS |
| S02 | invalid | 临时视图缺少任一 JSON invariant ID | 校验明确失败并列出缺失 ID | ALL | Python unit test | PASS |
| S03 | repeated | 连续生成契约清单两次 | 第二次无 diff，排序稳定 | N/A | generator `--check` | PASS |
| S04 | compatibility | 运行治理脚本后执行现有后端测试 | 运行时行为无变化 | INV-PAY-001~003, INV-KDS-001 | 68 targeted Maven tests | PASS |
| S05 | historical | 已有四条 invariant ID | ID 与语义保持，不被重编号 | INV-PAY-001~003, INV-KDS-001 | candidate JSON review | PASS |

