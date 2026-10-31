# Scenario Matrix — WI-021

| ID | Scenario | Expected Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | ACTIVE attempt 成功关单 | DB active_key 写为 NULL，状态 CLOSED | INV-003 | entity metadata + service unit | PASS |
| S02 | 关单后再次创建 | 新 attempt 可占用相同活动键并向微信下单 | INV-001/003 | regression unit | PASS |
| S03 | UNKNOWN/CREATING 再次创建 | 继续返回安全阻断，不调用微信二次下单 | INV-001/002 | existing regression | PASS |
| S04 | 微信成功/关闭通知或查单终态 | 同一字段策略释放活动键 | INV-003 | shared entity metadata + regression | PASS |
| S05 | 历史 CLOSED 记录残留 active_key | 本地自愈释放，不重复调用微信关单，继续创建 | INV-003 | regression unit | PASS |
